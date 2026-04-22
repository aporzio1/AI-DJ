import Foundation
#if os(iOS)
@preconcurrency import SpotifyiOS
#endif

/// Errors surfaced from the Spotify service at the protocol boundary. Phase 2a
/// shipped read-only; Phase 2b wires playback on iOS via SPTAppRemote. macOS
/// playback throws `.notSupportedYet` and surfaces a friendly iOS-only message
/// via the LibraryViewModel gate (D6-locked).
enum SpotifyServiceError: Error, Equatable {
    case notSupportedYet
    case notAuthenticated
    case appRemoteUnavailable
    case playbackFailed(String)
    case spotifyAppNotRunning
}

extension SpotifyServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notSupportedYet:
            return "Spotify playback isn't wired up on this platform yet."
        case .notAuthenticated:
            return "Connect your Spotify account in Settings → Music Services."
        case .appRemoteUnavailable:
            return "Couldn't reach the Spotify app. Make sure it's installed and open on your iPhone."
        case .playbackFailed(let message):
            return "Spotify playback failed: \(message)"
        case .spotifyAppNotRunning:
            return "Open the Spotify app on your iPhone, start any song there, then come back to AIDJ and try again."
        }
    }
}

/// `MusicProviderService` implementation backed by the Spotify Web API for
/// browsing and `SPTAppRemote` for playback on iOS. macOS conforms for the
/// compile-time abstraction but every playback method throws — D6 ships the
/// "Spotify is iOS-only for now" message until the WKWebView spike under D4.
@MainActor
final class SpotifyService: NSObject, MusicProviderService {

    let providerID: AIDJ.Track.MusicProviderID = .spotify

    private let auth: SpotifyAuthCoordinator
    private let api: SpotifyAPIClient
    private var artworkCache: [String: URL] = [:]

#if os(iOS)
    /// SPTAppRemote talks to the Spotify app over an app-to-app RPC channel.
    /// Lazy so we don't construct it until the first playback attempt — Phase
    /// 2a users who never tap play on a Spotify track never pay the init cost.
    private lazy var appRemote: SPTAppRemote = {
        let config = SPTConfiguration(
            clientID: SpotifyAuth.clientID,
            redirectURL: URL(string: SpotifyAuth.redirectURI)!
        )
        let remote = SPTAppRemote(configuration: config, logLevel: .debug)
        remote.delegate = self
        return remote
    }()

    /// Continuation resumed by SPTAppRemoteDelegate when the in-flight
    /// `appRemote.connect()` completes. nil when no connection attempt is in
    /// flight.
    private var connectionContinuation: CheckedContinuation<Void, Error>?
#endif

    init(auth: SpotifyAuthCoordinator, api: SpotifyAPIClient) {
        self.auth = auth
        self.api = api
        super.init()
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
#if os(iOS)
        if appRemote.isConnected {
            appRemote.disconnect()
        }
#endif
    }

#if os(macOS)
    /// Receives `aidj://` redirects forwarded by `AIDJApp.onOpenURL` and
    /// hands them to the auth coordinator to resume the in-flight PKCE flow.
    /// macOS-only — iOS routes the redirect through `ASWebAuthenticationSession`
    /// directly, bypassing this path.
    func handleAuthCallback(_ url: URL) {
        auth.handleAuthCallback(url)
    }
#endif

    /// Probes the Spotify `/me` endpoint to confirm the stored access /
    /// refresh tokens are still valid. Called from `SettingsView.onAppear`
    /// so the UI can't claim "Connected" against tokens Spotify has already
    /// revoked (and tokens that survived across app reinstalls). Silent on
    /// network errors — only clears on a hard auth failure.
    func validateAuthorization() async {
        guard auth.tokens != nil else { return }
        do {
            _ = try await api.me()
        } catch SpotifyAPIError.needsReauth {
            Log.spotify.info("validateAuthorization: token rejected, signing out")
            await signOut()
        } catch {
            Log.spotify.info("validateAuthorization: \(String(describing: error), privacy: .public) — leaving tokens in place (likely transient)")
        }
    }

    // MARK: - Playback

    func start(track: Track) async throws {
#if os(iOS)
        try await iosStart(track: track)
#else
        throw SpotifyServiceError.notSupportedYet
#endif
    }

    func pause() async throws {
#if os(iOS)
        try await iosInvokePlayerAPI { api, cont in api.pause { _, error in SpotifyService.finish(cont, error: error) } }
#else
        throw SpotifyServiceError.notSupportedYet
#endif
    }

    func resume() async throws {
#if os(iOS)
        try await iosInvokePlayerAPI { api, cont in api.resume { _, error in SpotifyService.finish(cont, error: error) } }
#else
        throw SpotifyServiceError.notSupportedYet
#endif
    }

    func stop() async throws {
        // SPTAppRemote has no dedicated "stop" — pause is the closest match.
        // The coordinator uses stop() mostly at queue-replace time to
        // silence whatever was playing; pausing satisfies that contract.
        try await pause()
    }

    func seek(to time: TimeInterval) async throws {
#if os(iOS)
        // SPTAppRemote's seek takes milliseconds.
        let ms = Int(time * 1000)
        try await iosInvokePlayerAPI { api, cont in
            api.seek(toPosition: ms) { _, error in SpotifyService.finish(cont, error: error) }
        }
#else
        throw SpotifyServiceError.notSupportedYet
#endif
    }

    func skipToNext() async throws {
#if os(iOS)
        try await iosInvokePlayerAPI { api, cont in api.skip(toNext: { _, error in SpotifyService.finish(cont, error: error) }) }
#else
        throw SpotifyServiceError.notSupportedYet
#endif
    }

    func startStation(id: String) async throws {
        // Stations are an Apple Music concept; Spotify's equivalent is radio
        // URIs, wired in a later phase if demand surfaces.
        throw SpotifyServiceError.notSupportedYet
    }

    var currentPlaybackTime: TimeInterval { 0 }
    var currentTrackDuration: TimeInterval? { nil }
    var currentTrack: Track? { nil }
    var playbackStatus: MusicPlaybackStatus { .stopped }

    // MARK: - Library

    func playlists() async throws -> [PlaylistInfo] {
        guard auth.tokens != nil else { return [] }
        let page = try await api.myPlaylists()
        // Drop Spotify-owned algorithmic playlists (Discover Weekly,
        // Your Top Songs, Daily Mixes, Release Radar). Spotify's
        // Development Mode + Nov-2024 restrictions reject
        // /playlists/{id}/tracks for these with 403, so surfacing them
        // in the UI just produces an error when the user taps one.
        let userOwned = page.items.filter { $0.owner?.id != "spotify" }
        let dropped = page.items.count - userOwned.count
        if dropped > 0 {
            Log.spotify.info("playlists: filtered out \(dropped) Spotify-owned playlists (algorithmic, inaccessible under Dev Mode)")
        }
        return userOwned.map { item in
            let url = item.images?.first?.url
            if let url { artworkCache[item.id] = url }
            return PlaylistInfo(id: item.id, name: item.name, artworkURL: url)
        }
    }

    func songs(inPlaylistWith id: String) async throws -> [Track] {
        guard auth.tokens != nil else {
            Log.spotify.info("songs(inPlaylistWith: \(id, privacy: .public)): no tokens, returning []")
            return []
        }
        // Post Feb-2026 migration: /playlists/{id}/items is the canonical
        // paginated endpoint, and each row exposes the track under `item`
        // (was `track` pre-migration). SpotifyAPIClient.tracks(inPlaylist:)
        // hits the right endpoint; SpotifyPlaylistItem.item is the new key.
        Log.spotify.info("songs(inPlaylistWith: \(id, privacy: .public)): fetching /playlists/{id}/items")
        do {
            let page = try await api.tracks(inPlaylist: id)
            let tracks: [Track] = page.items.compactMap { row in
                guard let s = row.item else { return nil }
                return cacheAndMap(s)
            }
            Log.spotify.info("songs(inPlaylistWith:): page.items=\(page.items.count) total=\(page.total) mapped tracks=\(tracks.count)")
            return tracks
        } catch {
            // Diagnostic on failure: probe adjacent endpoints so we know
            // whether the 403 is specific to the playlists endpoint or a
            // broader access issue.
            await runAccessDiagnostics(failingPlaylistID: id)
            throw error
        }
    }

    /// Runs a sequence of low-cost API probes after a playlist-tracks
    /// failure so we can see in the log which endpoints work vs which
    /// are restricted. Result interpretation in the log:
    /// - /me OK + /me/tracks OK + /playlists/{id} OK + tracks 403 →
    ///   Spotify is restricting the tracks subresource specifically
    ///   (likely Extended Quota requirement beyond docs).
    /// - /me OK + /me/tracks 403 → broader Web API Dev Mode clamp-down.
    /// - /playlists/{id} 403 → we can't read the playlist at all.
    private func runAccessDiagnostics(failingPlaylistID id: String) async {
        Log.spotify.info("=== Spotify access diagnostic (after 403 on /playlists/\(id, privacy: .public)/tracks) ===")
        await probe("GET /me") { try await self.api.me() }
        await probe("GET /me/tracks") { try await self.api.savedTracks() }
        await probe("GET /playlists/\(id)") { try await self.api.playlistMetadata(id: id) }
        await probe("GET /search?q=ok") { try await self.api.searchTracks(query: "ok", limit: 1) }
        Log.spotify.info("=== end Spotify access diagnostic ===")
    }

    private func probe(_ label: String, _ body: @Sendable () async throws -> some Sendable) async {
        do {
            _ = try await body()
            Log.spotify.info("probe [\(label, privacy: .public)]: OK")
        } catch {
            Log.spotify.error("probe [\(label, privacy: .public)]: \(String(describing: error), privacy: .public)")
        }
    }

    func songs(inAlbumWith id: String) async throws -> [Track] {
        // Spotify exposes /albums/{id}/tracks — not wired yet because the
        // Library Spotify tab only surfaces playlists for the MVP. Revisit
        // once the library UX has an "Albums" row for Spotify.
        []
    }

    func searchCatalogSongs(query: String, limit: Int) async throws -> [Track] {
        guard !query.isEmpty, auth.tokens != nil else { return [] }
        let response = try await api.searchTracks(query: query, limit: limit)
        return response.tracks.items.compactMap { cacheAndMap($0) }
    }

    func recentlyPlayed() async throws -> [LibraryItem] { [] }
    func recommendations() async throws -> [LibraryItem] { [] }

    func isPlayable(trackId: String) async -> Bool {
        // 2b.2 ships playback methods; isPlayable real impl + Producer
        // integration are 2b.5. Keep returning false so the DJ flow doesn't
        // proactively queue Spotify tracks yet — user-initiated Spotify play
        // (via the Library picker) doesn't check isPlayable, so it still works.
        false
    }

    func artwork(for trackId: String) -> ProviderArtwork? {
        if let url = artworkCache[trackId] { return .url(url) }
        return nil
    }

    // MARK: - Helpers

    /// Converts a Spotify wire-format track into our provider-neutral Track.
    /// Returns nil when required fields are missing — local files, podcast
    /// episodes, and removed tracks can produce partially-populated shapes
    /// that we can't route through the playback pipeline.
    private func cacheAndMap(_ s: SpotifyTrack) -> Track? {
        guard let id = s.id, let name = s.name, let durationMs = s.durationMs else {
            return nil
        }
        let artworkURL = s.album?.images?.first?.url
        if let artworkURL { artworkCache[id] = artworkURL }
        return Track(
            id: id,
            title: name,
            artist: (s.artists ?? []).map(\.name).joined(separator: ", "),
            album: s.album?.name ?? "",
            artworkURL: artworkURL,
            duration: TimeInterval(durationMs) / 1000,
            providerID: .spotify
        )
    }
}

// MARK: - SPTAppRemote integration (iOS)

#if os(iOS)
extension SpotifyService: SPTAppRemoteDelegate {

    fileprivate func iosStart(track: Track) async throws {
        try await ensureAppRemoteConnected()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            guard let playerAPI = appRemote.playerAPI else {
                cont.resume(throwing: SpotifyServiceError.appRemoteUnavailable)
                return
            }
            Log.spotify.info("start(track: '\(track.title, privacy: .public)') via SPTAppRemote")
            playerAPI.play("spotify:track:\(track.id)") { _, error in
                SpotifyService.finish(cont, error: error)
            }
        }
    }

    fileprivate func iosInvokePlayerAPI(
        _ body: (SPTAppRemotePlayerAPI, CheckedContinuation<Void, Error>) -> Void
    ) async throws {
        try await ensureAppRemoteConnected()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            guard let playerAPI = appRemote.playerAPI else {
                cont.resume(throwing: SpotifyServiceError.appRemoteUnavailable)
                return
            }
            body(playerAPI, cont)
        }
    }

    fileprivate static func finish(_ cont: CheckedContinuation<Void, Error>, error: Error?) {
        if let error {
            cont.resume(throwing: SpotifyServiceError.playbackFailed(error.localizedDescription))
        } else {
            cont.resume()
        }
    }

    /// Ensures SPTAppRemote is connected to the Spotify app. Reads the current
    /// access token from `SpotifyAuthCoordinator` and kicks off a connect if
    /// needed, awaiting the delegate callback via a stored continuation.
    /// Concurrent callers queue on the same continuation pattern — only one
    /// connect can be in flight at a time.
    fileprivate func ensureAppRemoteConnected() async throws {
        guard let token = auth.tokens?.accessToken else {
            throw SpotifyServiceError.notAuthenticated
        }
        appRemote.connectionParameters.accessToken = token

        if appRemote.isConnected {
            return
        }

        if connectionContinuation != nil {
            // Another call is already connecting; fail fast rather than stack
            // continuations. Callers can retry.
            throw SpotifyServiceError.appRemoteUnavailable
        }

        Log.spotify.info("ensureAppRemoteConnected: calling appRemote.connect()")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connectionContinuation = cont
            appRemote.connect()
        }
    }

    // MARK: SPTAppRemoteDelegate

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            Log.spotify.info("SPTAppRemote connected")
            connectionContinuation?.resume()
            connectionContinuation = nil
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let message = error?.localizedDescription ?? "unknown error"
        Task { @MainActor in
            Log.spotify.error("SPTAppRemote connection attempt failed: \(message, privacy: .public)")
            // Connection refused on the local IPC socket (com.spotify.app-remote
            // transport error with POSIX 61) means the Spotify app isn't
            // running. Rewrite the opaque SDK error into a user-actionable
            // one so LibraryViewModel can surface a clear "open Spotify"
            // message instead of a cryptic "stream error."
            let underlying = error as NSError?
            let posix = (underlying?.userInfo[NSUnderlyingErrorKey] as? NSError)?
                .userInfo[NSUnderlyingErrorKey] as? NSError
            let isRefused = underlying?.domain == "com.spotify.app-remote.transport"
                || posix?.domain == NSPOSIXErrorDomain && posix?.code == 61
            let failure: Error = isRefused
                ? SpotifyServiceError.spotifyAppNotRunning
                : (error ?? SpotifyServiceError.appRemoteUnavailable)
            connectionContinuation?.resume(throwing: failure)
            connectionContinuation = nil
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let message = error?.localizedDescription ?? "(no error)"
        Task { @MainActor in
            Log.spotify.info("SPTAppRemote disconnected: \(message, privacy: .public)")
            // If a connect was in flight, fail it so the caller sees the
            // disconnection rather than hanging.
            connectionContinuation?.resume(throwing: SpotifyServiceError.appRemoteUnavailable)
            connectionContinuation = nil
        }
    }
}
#endif
