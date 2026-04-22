import Foundation

// MARK: - Wire format

/// Spotify Web API paged response. Every list endpoint returns this shape.
struct SpotifyPage<Item: Decodable & Sendable & Equatable>: Decodable, Sendable, Equatable {
    let items: [Item]
    let limit: Int
    let offset: Int
    let total: Int
    let next: URL?
    let previous: URL?
}

struct SpotifyUser: Decodable, Sendable, Equatable {
    let id: String
    let displayName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
    }
}

struct SpotifyImage: Decodable, Sendable, Equatable {
    let url: URL
    let height: Int?
    let width: Int?
}

struct SpotifyPlaylistOwner: Decodable, Sendable, Equatable {
    let id: String
}

struct SpotifyPlaylist: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let owner: SpotifyPlaylistOwner?
}

struct SpotifyArtist: Decodable, Sendable, Equatable {
    let id: String
    let name: String
}

struct SpotifyAlbum: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
}

struct SpotifyTrack: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case id, name, artists, album
        case durationMs = "duration_ms"
    }
}

/// Envelope returned by `/me/playlists/{id}/tracks`. Each entry is a track
/// plus metadata; local or removed tracks can have a nil `track`, so we
/// model it as optional and filter at the service layer.
struct SpotifyPlaylistItem: Decodable, Sendable, Equatable {
    let track: SpotifyTrack?
}

struct SpotifySearchResponse: Decodable, Sendable, Equatable {
    let tracks: SpotifyPage<SpotifyTrack>
}

// MARK: - Errors

enum SpotifyAPIError: Error, Equatable {
    case httpError(status: Int, body: String)
    case malformedResponse
    /// Returned when a 401 persists after forcing a token refresh and retrying
    /// once — likely the refresh token was revoked. Callers surface this as
    /// `ProviderAuthStatus.needsReauth` and prompt the user to reconnect.
    case needsReauth
}

extension SpotifyAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .httpError(let status, _):
            switch status {
            case 403:
                // Spotify's Development Mode + Nov-2024 algorithmic-content
                // restrictions return 403 on playlists/{id}/tracks for
                // Spotify-owned personalized playlists (Discover Weekly,
                // Your Top Songs, Daily Mixes, Release Radar). User-owned
                // playlists work fine.
                return "Spotify blocked this one. Personalized playlists like Discover Weekly or Your Top Songs aren't accessible to third-party apps — try a playlist you created yourself."
            case 404:
                return "Spotify couldn't find that playlist (maybe deleted or made private)."
            case 429:
                return "Spotify rate limit hit. Wait a minute and try again."
            case 500...599:
                return "Spotify had a server error (\(status)). Try again in a moment."
            default:
                return "Spotify returned HTTP \(status)."
            }
        case .malformedResponse:
            return "Spotify returned an unexpected response format."
        case .needsReauth:
            return "Spotify session expired. Reconnect in Settings → Music Services."
        }
    }
}

// MARK: - Client

/// Talks to `https://api.spotify.com/v1/` using the access token vended by
/// `SpotifyAuthCoordinator`. Refreshes the token preemptively when inside the
/// expiry leeway, and retries 401 responses once after a forced refresh.
actor SpotifyAPIClient {

    private let auth: SpotifyAuthCoordinator
    private let baseURL: URL
    private let urlSession: URLSession

    init(auth: SpotifyAuthCoordinator,
         baseURL: URL = URL(string: "https://api.spotify.com/v1/")!,
         urlSession: URLSession = .shared) {
        self.auth = auth
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    // MARK: - Endpoints

    func me() async throws -> SpotifyUser {
        try await request(path: "me", as: SpotifyUser.self)
    }

    func myPlaylists(limit: Int = 50, offset: Int = 0) async throws -> SpotifyPage<SpotifyPlaylist> {
        try await request(
            path: "me/playlists",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ],
            as: SpotifyPage<SpotifyPlaylist>.self
        )
    }

    func tracks(inPlaylist id: String, limit: Int = 100, offset: Int = 0) async throws -> SpotifyPage<SpotifyPlaylistItem> {
        try await request(
            path: "playlists/\(id)/tracks",
            query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ],
            as: SpotifyPage<SpotifyPlaylistItem>.self
        )
    }

    func searchTracks(query: String, limit: Int = 20) async throws -> SpotifySearchResponse {
        try await request(
            path: "search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "track"),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            as: SpotifySearchResponse.self
        )
    }

    // MARK: - Core request path

    private func request<T: Decodable>(path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        // Preemptive refresh: if we're inside the expiry leeway, refresh now
        // to avoid the 401-retry round trip. This is the hot path for normal
        // operation; 401 retry below only fires when the token was rejected
        // despite looking valid (e.g. revoked mid-flight).
        try? await auth.refreshIfNeeded()

        let urlRequest = try await buildRequest(path: path, query: query)
        let (data, response) = try await urlSession.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.malformedResponse
        }

        if http.statusCode == 401 {
            // Force a refresh even if the stored token looked valid — Spotify
            // rejected it. Then retry exactly once. If the retry also 401s the
            // refresh token is almost certainly revoked; surface needsReauth.
            do {
                try await auth.forceRefresh()
            } catch {
                throw SpotifyAPIError.needsReauth
            }
            let retryRequest = try await buildRequest(path: path, query: query)
            let (retryData, retryResponse) = try await urlSession.data(for: retryRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw SpotifyAPIError.malformedResponse
            }
            if retryHTTP.statusCode == 401 {
                throw SpotifyAPIError.needsReauth
            }
            return try decode(retryData, status: retryHTTP.statusCode, as: type)
        }

        return try decode(data, status: http.statusCode, as: type)
    }

    private func buildRequest(path: String, query: [URLQueryItem]) async throws -> URLRequest {
        let url = try buildURL(path: path, query: query)
        guard let accessToken = await auth.tokens?.accessToken else {
            throw SpotifyAPIError.needsReauth
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Internal for tests — constructs the URL the client would send.
    func buildURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw SpotifyAPIError.malformedResponse
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw SpotifyAPIError.malformedResponse
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let full = components.url else {
            throw SpotifyAPIError.malformedResponse
        }
        return full
    }

    private func decode<T: Decodable>(_ data: Data, status: Int, as type: T.Type) throws -> T {
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable>"
            Log.spotify.error("HTTP \(status) response: \(body, privacy: .public)")
            throw SpotifyAPIError.httpError(status: status, body: body)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SpotifyAPIError.malformedResponse
        }
    }
}
