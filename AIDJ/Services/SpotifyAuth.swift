import Foundation
import CryptoKit
import AuthenticationServices

/// Spotify OAuth constants. Client ID is intentionally not a secret — D2 locks
/// a single public Client ID shipped in the binary, per hobby-app scope. The
/// value lands in Phase 2a Commit 2 after Andrew registers the app at
/// developer.spotify.com; this placeholder keeps Commit 1 self-contained and
/// unit-testable.
enum SpotifyAuth {
    static let clientID: String = "PLACEHOLDER_CLIENT_ID"
    static let redirectURI: String = "aidj://spotify-callback"
    static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!

    /// Minimum scope set for Phase 2a+2b. Requested once so the user consents
    /// once — asking for `streaming` and `app-remote-control` up front means
    /// the Phase 2b SPTAppRemote playback wiring won't force a re-consent.
    static let scopes: [String] = [
        "user-read-private",
        "user-read-email",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "streaming",
        "app-remote-control",
    ]
}

/// Persisted Spotify OAuth tokens. Access tokens expire (Spotify hands out
/// ~1hr lifespans); refresh tokens typically persist until the user revokes
/// consent or Spotify rotates them on refresh.
struct SpotifyTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    /// True when the access token is within `leeway` of expiring. Callers
    /// should refresh before the next API call to avoid a 401-retry round trip.
    func isExpiring(leeway: TimeInterval = 60, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }
}

enum SpotifyAuthError: Error, Equatable {
    case cancelledByUser
    case invalidRedirect
    case missingCode
    case stateMismatch
    case tokenExchangeFailed(String)
    case noRefreshToken
    case notAuthenticated
}

@MainActor
final class SpotifyAuthCoordinator: NSObject {

    // MARK: - Config

    private let clientID: String
    private let redirectURI: String
    private let authorizeEndpoint: URL
    private let tokenEndpoint: URL
    private let scopes: [String]
    private let urlSession: URLSession

    // MARK: - State

    private(set) var tokens: SpotifyTokens?

    var isAuthenticated: Bool { tokens != nil }

    // MARK: - Init

    init(clientID: String = SpotifyAuth.clientID,
         redirectURI: String = SpotifyAuth.redirectURI,
         authorizeEndpoint: URL = SpotifyAuth.authorizeEndpoint,
         tokenEndpoint: URL = SpotifyAuth.tokenEndpoint,
         scopes: [String] = SpotifyAuth.scopes,
         urlSession: URLSession = .shared) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.authorizeEndpoint = authorizeEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
        self.urlSession = urlSession
        super.init()
        self.tokens = Self.loadTokens()
    }

    // MARK: - Public API

    /// Opens the Spotify consent screen via `ASWebAuthenticationSession`, waits
    /// for the callback, and exchanges the returned auth code for tokens.
    /// Persists to Keychain on success.
    func beginAuthFlow() async throws -> SpotifyTokens {
        let pkce = Self.generatePKCEPair()
        let state = Self.randomState()
        let authURL = try buildAuthorizeURL(pkce: pkce, state: state)

        let callback = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme(from: redirectURI)
            ) { url, error in
                if let nsError = error as NSError?,
                   nsError.domain == ASWebAuthenticationSessionErrorDomain,
                   nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    cont.resume(throwing: SpotifyAuthError.cancelledByUser)
                } else if let error {
                    cont.resume(throwing: error)
                } else if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: SpotifyAuthError.invalidRedirect)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        let params = Self.queryItems(from: callback)
        guard params["state"] == state else { throw SpotifyAuthError.stateMismatch }
        guard let code = params["code"] else { throw SpotifyAuthError.missingCode }

        let newTokens = try await exchangeCode(code, verifier: pkce.verifier)
        persist(newTokens)
        return newTokens
    }

    /// Refreshes the access token if it's within the default 60-second leeway
    /// of expiry. No-op if tokens are still valid. Throws if unauthenticated
    /// or Spotify revoked the refresh token (401).
    func refreshIfNeeded() async throws {
        guard let current = tokens else { throw SpotifyAuthError.notAuthenticated }
        guard current.isExpiring() else { return }
        let refreshed = try await refresh(using: current.refreshToken)
        persist(refreshed)
    }

    /// Unconditionally refreshes, bypassing the leeway check. Used by
    /// `SpotifyAPIClient` when Spotify rejects the current token with 401 —
    /// the token looked valid to us but Spotify revoked it.
    func forceRefresh() async throws {
        guard let current = tokens else { throw SpotifyAuthError.notAuthenticated }
        let refreshed = try await refresh(using: current.refreshToken)
        persist(refreshed)
    }

    /// Clears persisted tokens. No-op if not authenticated.
    func signOut() {
        Keychain.remove(KeychainKey.spotifyAccessToken)
        Keychain.remove(KeychainKey.spotifyRefreshToken)
        Keychain.remove(KeychainKey.spotifyExpiresAt)
        tokens = nil
    }

    /// Test-only seed. Directly injects tokens without touching the Keychain,
    /// so unit tests don't have to stub the Security framework. Not intended
    /// for production code paths — production must go through `beginAuthFlow`
    /// or `refreshIfNeeded` so tokens land in the Keychain.
    func setTestTokens(access: String, refresh: String, expiresAt: Date) {
        self.tokens = SpotifyTokens(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String, verifier: String) async throws -> SpotifyTokens {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]).data(using: .utf8)
        return try await performTokenRequest(request, previousRefreshToken: nil)
    }

    private func refresh(using refreshToken: String) async throws -> SpotifyTokens {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]).data(using: .utf8)
        return try await performTokenRequest(request, previousRefreshToken: refreshToken)
    }

    private func performTokenRequest(_ request: URLRequest, previousRefreshToken: String?) async throws -> SpotifyTokens {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "<unreadable>"
            throw SpotifyAuthError.tokenExchangeFailed(msg)
        }
        let payload = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        let expiresAt = Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        // Spotify sometimes omits `refresh_token` on refresh responses — the
        // existing one stays valid. If we never had one and none came back,
        // that's an auth error.
        let refresh = payload.refreshToken ?? previousRefreshToken
        guard let refresh else { throw SpotifyAuthError.noRefreshToken }
        return SpotifyTokens(accessToken: payload.accessToken, refreshToken: refresh, expiresAt: expiresAt)
    }

    // MARK: - URL building (internal for tests)

    func buildAuthorizeURL(pkce: PKCEPair, state: String) throws -> URL {
        guard var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false) else {
            throw SpotifyAuthError.invalidRedirect
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw SpotifyAuthError.invalidRedirect }
        return url
    }

    // MARK: - Persistence

    private func persist(_ tokens: SpotifyTokens) {
        Keychain.set(tokens.accessToken, forKey: KeychainKey.spotifyAccessToken)
        Keychain.set(tokens.refreshToken, forKey: KeychainKey.spotifyRefreshToken)
        Keychain.set(Self.iso8601Formatter.string(from: tokens.expiresAt), forKey: KeychainKey.spotifyExpiresAt)
        self.tokens = tokens
    }

    private static func loadTokens() -> SpotifyTokens? {
        guard let access = Keychain.get(KeychainKey.spotifyAccessToken),
              let refresh = Keychain.get(KeychainKey.spotifyRefreshToken),
              let expiresAtString = Keychain.get(KeychainKey.spotifyExpiresAt),
              let expiresAt = iso8601Formatter.date(from: expiresAtString) else {
            return nil
        }
        return SpotifyTokens(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - PKCE (pure; exposed for tests)

    struct PKCEPair: Equatable, Sendable {
        let verifier: String
        let challenge: String
    }

    static func generatePKCEPair() -> PKCEPair {
        let verifier = randomVerifier()
        return PKCEPair(verifier: verifier, challenge: challenge(from: verifier))
    }

    /// 64 random bytes base64url-encoded → ~86 chars, inside RFC 7636's 43-128 verifier range.
    static func randomVerifier() -> String {
        base64URLEncode(randomBytes(count: 64))
    }

    /// 32 random bytes base64url-encoded — the OAuth `state` value that binds
    /// the redirect to the originating request to defeat CSRF.
    static func randomState() -> String {
        base64URLEncode(randomBytes(count: 32))
    }

    static func challenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes)
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Form encoding + query parsing (pure; exposed for tests)

    static func formEncode(_ params: [String: String]) -> String {
        params
            .map { key, value in "\(percentEncode(key))=\(percentEncode(value))" }
            .sorted()
            .joined(separator: "&")
    }

    private static func percentEncode(_ s: String) -> String {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: set) ?? s
    }

    static func queryItems(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var dict: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { dict[item.name] = value }
        }
        return dict
    }

    private static func callbackScheme(from redirectURI: String) -> String {
        URL(string: redirectURI)?.scheme ?? "aidj"
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SpotifyAuthCoordinator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
#if os(iOS)
        return MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
#elseif os(macOS)
        return MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
        }
#else
        return ASPresentationAnchor()
#endif
    }
}

// MARK: - Wire format

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}
