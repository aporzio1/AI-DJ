import Foundation

/// Errors surfaced from the Spotify service at the protocol boundary. Phase 2a
/// ships read-only — every playback-control method on `MusicProviderService`
/// throws `.notSupportedYet`. Phase 2b wires SPTAppRemote playback and
/// replaces these throws with real implementations.
enum SpotifyServiceError: Error, Equatable {
    case notSupportedYet
    case notAuthenticated
}

/// `MusicProviderService` implementation backed by the Spotify Web API. Read
/// paths (playlists, playlist tracks, search) work in Phase 2a; playback
/// paths (start/pause/resume/stop/seek/skip/startStation) deliberately throw
/// `SpotifyServiceError.notSupportedYet` until Phase 2b adds the iOS SDK.
@MainActor
final class SpotifyService: MusicProviderService {

    let providerID: AIDJ.Track.MusicProviderID = .spotify

    private let auth: SpotifyAuthCoordinator
    private let api: SpotifyAPIClient
    private var artworkCache: [String: URL] = [:]

    init(auth: SpotifyAuthCoordinator, api: SpotifyAPIClient) {
        self.auth = auth
        self.api = api
    }

    // MARK: - Auth

    var authorizationStatus: ProviderAuthStatus {
        auth.tokens != nil ? .authorized : .notAuthorized
    }

    func requestAuthorization() async -> ProviderAuthStatus {
        do {
            _ = try await auth.beginAuthFlow()
            return .authorized
        } catch SpotifyAuthError.cancelledByUser {
            return .notAuthorized
        } catch {
            Log.spotify.error("auth failed: \(String(describing: error), privacy: .public)")
            return .notAuthorized
        }
    }

    func signOut() async {
        auth.signOut()
        artworkCache.removeAll()
    }

    // MARK: - Playback (Phase 2a throws; Phase 2b fills in)

    func start(track: Track) async throws { throw SpotifyServiceError.notSupportedYet }
    func pause() async throws { throw SpotifyServiceError.notSupportedYet }
    func resume() async throws { throw SpotifyServiceError.notSupportedYet }
    func stop() async throws { throw SpotifyServiceError.notSupportedYet }
    func seek(to time: TimeInterval) async throws { throw SpotifyServiceError.notSupportedYet }
    func skipToNext() async throws { throw SpotifyServiceError.notSupportedYet }
    func startStation(id: String) async throws { throw SpotifyServiceError.notSupportedYet }

    var currentPlaybackTime: TimeInterval { 0 }
    var currentTrackDuration: TimeInterval? { nil }
    var currentTrack: Track? { nil }
    var playbackStatus: MusicPlaybackStatus { .stopped }

    // MARK: - Library

    func playlists() async throws -> [PlaylistInfo] {
        guard auth.tokens != nil else { return [] }
        let page = try await api.myPlaylists()
        return page.items.map { item in
            let url = item.images?.first?.url
            if let url { artworkCache[item.id] = url }
            return PlaylistInfo(id: item.id, name: item.name, artworkURL: url)
        }
    }

    func songs(inPlaylistWith id: String) async throws -> [Track] {
        guard auth.tokens != nil else { return [] }
        let page = try await api.tracks(inPlaylist: id)
        return page.items.compactMap { item in
            guard let s = item.track else { return nil }
            return cacheAndMap(s)
        }
    }

    func songs(inAlbumWith id: String) async throws -> [Track] {
        // Spotify exposes /albums/{id}/tracks — not wired yet in 2a because
        // the Library Spotify tab only surfaces playlists for the MVP.
        // Revisit once the library UX has an "Albums" row for Spotify.
        []
    }

    func searchCatalogSongs(query: String, limit: Int) async throws -> [Track] {
        guard !query.isEmpty, auth.tokens != nil else { return [] }
        let response = try await api.searchTracks(query: query, limit: limit)
        return response.tracks.items.map { cacheAndMap($0) }
    }

    func recentlyPlayed() async throws -> [LibraryItem] { [] }
    func recommendations() async throws -> [LibraryItem] { [] }

    func isPlayable(trackId: String) async -> Bool {
        // Phase 2a has no playback. 2b will verify against SPTAppRemote state.
        false
    }

    func artwork(for trackId: String) -> ProviderArtwork? {
        if let url = artworkCache[trackId] { return .url(url) }
        return nil
    }

    // MARK: - Helpers

    private func cacheAndMap(_ s: SpotifyTrack) -> Track {
        if let url = s.album.images?.first?.url { artworkCache[s.id] = url }
        return Track(
            id: s.id,
            title: s.name,
            artist: s.artists.map(\.name).joined(separator: ", "),
            album: s.album.name,
            artworkURL: s.album.images?.first?.url,
            duration: TimeInterval(s.durationMs) / 1000,
            providerID: .spotify
        )
    }
}
