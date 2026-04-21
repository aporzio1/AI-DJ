import Testing
import Foundation
@testable import AIDJ

@Suite("SpotifyAuthCoordinator")
@MainActor
struct SpotifyAuthCoordinatorTests {

    // MARK: - Token expiry math

    @Test func tokensAreExpiringInsideTheLeeway() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tokens = SpotifyTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(30)   // 30s until expiry
        )
        #expect(tokens.isExpiring(leeway: 60, now: now))
    }

    @Test func tokensAreNotExpiringOutsideTheLeeway() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tokens = SpotifyTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(3_600) // 1hr out
        )
        #expect(!tokens.isExpiring(leeway: 60, now: now))
    }

    @Test func tokensAlreadyExpiredAreExpiring() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tokens = SpotifyTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: now.addingTimeInterval(-10)   // already past
        )
        #expect(tokens.isExpiring(leeway: 60, now: now))
    }

    // MARK: - PKCE

    @Test func rfc7636ReferenceVector() {
        // Appendix B of RFC 7636 — canonical test pair used by every PKCE
        // implementation. If this drifts, the SHA256 / base64url pipeline is
        // broken.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        #expect(SpotifyAuthCoordinator.challenge(from: verifier) == expectedChallenge)
    }

    @Test func generatePKCEPairProducesBase64URLVerifier() {
        let pair = SpotifyAuthCoordinator.generatePKCEPair()
        // 64 random bytes → 86 chars base64url (no padding).
        #expect(pair.verifier.count == 86)
        // base64url alphabet: A-Z a-z 0-9 - _
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        let invalid = pair.verifier.unicodeScalars.first { !allowed.contains($0) }
        #expect(invalid == nil, "verifier contained non-base64url char: \(String(describing: invalid))")
        // Challenge must equal SHA256(verifier) base64url.
        #expect(pair.challenge == SpotifyAuthCoordinator.challenge(from: pair.verifier))
    }

    @Test func randomVerifiersAreUnique() {
        var seen = Set<String>()
        for _ in 0..<32 {
            seen.insert(SpotifyAuthCoordinator.randomVerifier())
        }
        #expect(seen.count == 32)
    }

    // MARK: - Authorize URL

    @Test func authorizeURLHasAllRequiredParams() throws {
        let coordinator = SpotifyAuthCoordinator(
            clientID: "client-123",
            redirectURI: "aidj://spotify-callback",
            scopes: ["user-read-email", "playlist-read-private"]
        )
        let pair = SpotifyAuthCoordinator.PKCEPair(
            verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
            challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
        let url = try coordinator.buildAuthorizeURL(pkce: pair, state: "state-xyz")
        let items = SpotifyAuthCoordinator.queryItems(from: url)

        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == "client-123")
        #expect(items["redirect_uri"] == "aidj://spotify-callback")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == pair.challenge)
        #expect(items["state"] == "state-xyz")
        #expect(items["scope"] == "user-read-email playlist-read-private")
        #expect(url.host == "accounts.spotify.com")
        #expect(url.path == "/authorize")
    }

    // MARK: - Form encoding

    @Test func formEncodeIsDeterministicAndSorted() {
        let encoded = SpotifyAuthCoordinator.formEncode([
            "grant_type": "authorization_code",
            "code": "abc",
            "client_id": "client-123"
        ])
        // Alphabetized by key after percent-encoding, joined with `&`.
        #expect(encoded == "client_id=client-123&code=abc&grant_type=authorization_code")
    }

    @Test func formEncodePercentEncodesReservedChars() {
        let encoded = SpotifyAuthCoordinator.formEncode([
            "redirect_uri": "aidj://spotify-callback"
        ])
        #expect(encoded == "redirect_uri=aidj%3A%2F%2Fspotify-callback")
    }

    @Test func queryItemsParsesCallbackURL() {
        let url = URL(string: "aidj://spotify-callback?code=abc123&state=xyz")!
        let items = SpotifyAuthCoordinator.queryItems(from: url)
        #expect(items["code"] == "abc123")
        #expect(items["state"] == "xyz")
    }
}
