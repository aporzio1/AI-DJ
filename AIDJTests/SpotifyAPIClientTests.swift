import Testing
import Foundation
@testable import AIDJ

@Suite("SpotifyAPIClient")
struct SpotifyAPIClientTests {

    // MARK: - Harness

    private static func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async -> (SpotifyAPIClient, SpotifyAuthCoordinator) {
        MockURLProtocol.register(handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        // Unauthenticated tests drop the Keychain-backed token side-load;
        // use a mock token endpoint so `forceRefresh` can fake a refresh.
        let auth = await MainActor.run {
            let a = SpotifyAuthCoordinator(
                clientID: "test-client",
                redirectURI: "aidj://spotify-callback",
                authorizeEndpoint: URL(string: "https://accounts.spotify.test/authorize")!,
                tokenEndpoint: URL(string: "https://accounts.spotify.test/api/token")!,
                scopes: [],
                urlSession: session
            )
            a.setTestTokens(access: "access-1", refresh: "refresh-1", expiresAt: Date().addingTimeInterval(3_600))
            return a
        }
        let client = SpotifyAPIClient(
            auth: auth,
            baseURL: URL(string: "https://api.spotify.com/v1/")!,
            urlSession: session
        )
        return (client, auth)
    }

    // MARK: - Endpoints

    @Test func meParsesDisplayName() async throws {
        let (client, _) = await Self.makeClient { _ in
            let body = #"""
            { "id": "user-1", "display_name": "T", "email": "t@example.com" }
            """#
            return (Self.ok(), Data(body.utf8))
        }
        let user = try await client.me()
        #expect(user.id == "user-1")
        #expect(user.displayName == "T")
        #expect(user.email == "t@example.com")
    }

    @Test func myPlaylistsParsesPage() async throws {
        let (client, _) = await Self.makeClient { request in
            #expect(request.url?.path == "/v1/me/playlists")
            #expect(request.url?.query?.contains("limit=50") == true)
            let body = #"""
            {
              "items": [
                { "id": "p1", "name": "Workout", "images": [{ "url": "https://img/1.jpg", "height": 200, "width": 200 }] },
                { "id": "p2", "name": "Chill", "images": null }
              ],
              "limit": 50, "offset": 0, "total": 2, "next": null, "previous": null
            }
            """#
            return (Self.ok(), Data(body.utf8))
        }
        let page = try await client.myPlaylists()
        #expect(page.items.count == 2)
        #expect(page.items[0].id == "p1")
        #expect(page.items[0].images?.first?.url.absoluteString == "https://img/1.jpg")
        #expect(page.total == 2)
    }

    @Test func playlistTracksHandlesNilTrack() async throws {
        let (client, _) = await Self.makeClient { _ in
            let body = #"""
            {
              "items": [
                { "track": { "id": "t1", "name": "Song", "artists": [{"id": "a1", "name": "Artist"}],
                             "album": { "id": "al1", "name": "Album", "images": [] },
                             "duration_ms": 210000 } },
                { "track": null }
              ],
              "limit": 100, "offset": 0, "total": 2, "next": null, "previous": null
            }
            """#
            return (Self.ok(), Data(body.utf8))
        }
        let page = try await client.tracks(inPlaylist: "p1")
        #expect(page.items.count == 2)
        #expect(page.items[0].track?.id == "t1")
        #expect(page.items[1].track == nil)
    }

    @Test func searchTracksDecodes() async throws {
        let (client, _) = await Self.makeClient { request in
            #expect(request.url?.path == "/v1/search")
            #expect(request.url?.query?.contains("type=track") == true)
            let body = #"""
            {
              "tracks": {
                "items": [
                  { "id": "t1", "name": "Song", "artists": [{"id": "a1","name":"Artist"}],
                    "album": {"id":"al1","name":"Album","images":[]}, "duration_ms": 180000 }
                ],
                "limit": 20, "offset": 0, "total": 1, "next": null, "previous": null
              }
            }
            """#
            return (Self.ok(), Data(body.utf8))
        }
        let result = try await client.searchTracks(query: "foo")
        #expect(result.tracks.items.count == 1)
        #expect(result.tracks.items[0].name == "Song")
    }

    // MARK: - 401 retry

    @Test func retriesOnceAfter401WithForcedRefresh() async throws {
        let callCounter = SendableCounter()
        let (client, _) = await Self.makeClient { request in
            let count = callCounter.incrementAndGet()
            // 1st API call → 401. Auth coordinator's forceRefresh hits token
            // endpoint (call #2), returning a new access token. Then the API
            // client retries → call #3 returns 200.
            if request.url?.host == "accounts.spotify.test" {
                let body = #"""
                { "access_token": "access-2", "token_type": "Bearer", "expires_in": 3600 }
                """#
                return (Self.ok(), Data(body.utf8))
            }
            if count == 1 {
                return (Self.status(401), Data(#"{"error":"invalid_token"}"#.utf8))
            }
            let body = #"""
            { "id": "user-1", "display_name": "T", "email": null }
            """#
            return (Self.ok(), Data(body.utf8))
        }
        let user = try await client.me()
        #expect(user.id == "user-1")
        #expect(callCounter.current >= 3)
    }

    @Test func surfacesNeedsReauthAfterPersistent401() async throws {
        let (client, _) = await Self.makeClient { request in
            if request.url?.host == "accounts.spotify.test" {
                let body = #"""
                { "access_token": "access-2", "token_type": "Bearer", "expires_in": 3600 }
                """#
                return (Self.ok(), Data(body.utf8))
            }
            return (Self.status(401), Data(#"{"error":"invalid_token"}"#.utf8))
        }
        await #expect(throws: SpotifyAPIError.needsReauth) {
            try await client.me()
        }
    }

    // MARK: - Decoder errors

    @Test func malformedResponseThrows() async throws {
        let (client, _) = await Self.makeClient { _ in
            return (Self.ok(), Data("not json".utf8))
        }
        await #expect(throws: SpotifyAPIError.malformedResponse) {
            _ = try await client.me()
        }
    }

    // MARK: - URL building

    @Test func buildURLMergesPathAndQuery() async throws {
        let (client, _) = await Self.makeClient { _ in (Self.ok(), Data()) }
        let url = try await client.buildURL(
            path: "search",
            query: [URLQueryItem(name: "q", value: "hello world"), URLQueryItem(name: "type", value: "track")]
        )
        #expect(url.host == "api.spotify.com")
        #expect(url.path == "/v1/search")
        #expect(url.query?.contains("q=hello%20world") == true || url.query?.contains("q=hello+world") == true)
        #expect(url.query?.contains("type=track") == true)
    }

    // MARK: - Helpers

    private static func ok() -> HTTPURLResponse {
        status(200)
    }

    private static func status(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.spotify.com/v1/me")!,
                        statusCode: code, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"])!
    }
}

// MARK: - URLProtocol mock

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func register(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
    }

    private static var currentHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock(); defer { lock.unlock() }
        return _handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Sendable counter

final class SendableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    func incrementAndGet() -> Int {
        lock.lock(); defer { lock.unlock() }
        _count += 1
        return _count
    }
    var current: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
}
