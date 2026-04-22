import Foundation

@Observable
@MainActor
final class LibraryViewModel {

    private(set) var playlists: [PlaylistInfo] = []
    private(set) var songs: [AIDJ.Track] = []
    private(set) var selectedPlaylist: PlaylistInfo?
    private(set) var recentlyPlayed: [LibraryItem] = []
    private(set) var recommendations: [LibraryItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // Search state
    private(set) var searchResults: [AIDJ.Track] = []
    private(set) var isSearching = false

    private let router: MusicProviderRouter
    private let coordinator: PlaybackCoordinator
    private let producer: Producer?

    /// Which provider the Library tab is currently browsing. Driven from
    /// `SettingsViewModel.browseProvider` via `setProvider(_:)`. Changes
    /// dump the previous provider's cached state (playlists, songs,
    /// recently-played, recommendations) so the UI never shows mixed-origin
    /// rows.
    private(set) var activeProvider: Track.MusicProviderID

    private var musicService: any MusicProviderService {
        switch activeProvider {
        case .appleMusic: return router.appleMusic
        case .spotify:    return router.spotify
        }
    }

    init(router: MusicProviderRouter,
         coordinator: PlaybackCoordinator,
         producer: Producer? = nil,
         initialProvider: Track.MusicProviderID = .appleMusic) {
        self.router = router
        self.coordinator = coordinator
        self.producer = producer
        self.activeProvider = initialProvider
    }

    /// Swap the active provider, clear per-provider state, and reload all
    /// sections for the new provider. No-op if already active.
    func setProvider(_ provider: Track.MusicProviderID) async {
        guard provider != activeProvider else { return }
        activeProvider = provider
        playlists = []
        songs = []
        selectedPlaylist = nil
        recentlyPlayed = []
        recommendations = []
        searchResults = []
        errorMessage = nil
        await loadPlaylists()
        await loadRecentlyPlayed()
        await loadRecommendations()
    }

    /// Surfaced by LibraryView as a dismissible alert so the user sees
    /// playback-gate messages even when the library has content to render.
    /// Separate from `errorMessage` (which is reserved for fetch errors
    /// displayed as a ContentUnavailableView when the list is empty).
    private(set) var playbackAlertMessage: String?

    func clearPlaybackAlert() { playbackAlertMessage = nil }

    /// Gates play attempts when the active provider can't actually play on
    /// the current platform. Phase 2b.2 wires iOS SPTAppRemote playback, so
    /// iOS builds pass through and the coordinator handles the rest. macOS
    /// keeps the D6-locked "Spotify is iOS-only for now" message until the
    /// WKWebView spike lands (Phase 4 or D4 resolution).
    private func guardPlaybackSupported() -> Bool {
#if os(iOS)
        return true
#else
        if activeProvider == .spotify {
            playbackAlertMessage = "Spotify playback is iOS-only for now. This build can browse Spotify but can't play it — open the app on your iPhone to listen."
            return false
        }
        return true
#endif
    }

    func loadPlaylists() async {
        isLoading = true
        errorMessage = nil
        do {
            playlists = try await musicService.playlists()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Stale-while-revalidate: render the cached Recently Played list
    /// immediately, then refresh from MusicKit in the background if the
    /// cache is missing, empty, or older than the TTL. Pass
    /// `forceRefresh: true` to bypass the TTL (pull-to-refresh).
    ///
    /// An empty cache payload is always treated as stale — an earlier
    /// fetch may have failed or returned zero items, and locking the
    /// section to "empty for 30 min" is worse than just retrying.
    /// Empty results are also never SAVED to the cache, so a one-off
    /// failure doesn't poison future launches.
    func loadRecentlyPlayed(forceRefresh: Bool = false) async {
        let provider = activeProvider
        let cached = LibrarySectionCache.load(.recentlyPlayed, provider: provider)
        if let cached {
            recentlyPlayed = cached.items
        }
        let isStale = cached.map { !$0.isFresh(ttl: LibrarySectionCache.ttl) } ?? true
        let isEmpty = cached?.items.isEmpty ?? true
        guard forceRefresh || isStale || isEmpty else { return }

        if let items = try? await musicService.recentlyPlayed() {
            recentlyPlayed = items
            if !items.isEmpty {
                LibrarySectionCache.save(items, for: .recentlyPlayed, provider: provider)
            }
        }
    }

    func loadRecommendations(forceRefresh: Bool = false) async {
        let provider = activeProvider
        let cached = LibrarySectionCache.load(.recommendations, provider: provider)
        if let cached {
            recommendations = cached.items
        }
        let isStale = cached.map { !$0.isFresh(ttl: LibrarySectionCache.ttl) } ?? true
        let isEmpty = cached?.items.isEmpty ?? true
        guard forceRefresh || isStale || isEmpty else { return }

        if let items = try? await musicService.recommendations() {
            recommendations = items
            if !items.isEmpty {
                LibrarySectionCache.save(items, for: .recommendations, provider: provider)
            }
        }
    }

    /// Pull-to-refresh / manual refresh hook — bypasses TTL on both sections.
    func refreshLibrarySections() async {
        async let rp: Void = loadRecentlyPlayed(forceRefresh: true)
        async let rec: Void = loadRecommendations(forceRefresh: true)
        _ = await (rp, rec)
    }

    /// Handles a tap on a Library card. Tracks play directly; playlists get
    /// played end-to-end; albums get resolved to their track list and played;
    /// stations aren't wired yet (would need ApplicationMusicPlayer.Queue
    /// station support).
    func playLibraryItem(_ item: LibraryItem) async {
        Log.app.info("playLibraryItem: tap received for \(String(describing: item), privacy: .public)")
        switch item {
        case .track(let t):
            await playSong(t)
        case .playlist(let p):
            await playPlaylist(p)
        case .album(let a):
            await playAlbum(a)
        case .station(let s):
            await playStation(s)
        }
    }

    /// Starts a radio station. Routes through the Coordinator so it can
    /// flip into externalPlayback mode — that way the VM falls back to
    /// MusicKit's currentTrack for display and transport still works via
    /// pause/resume/skip. DJ voice doesn't fire over station content
    /// (stations are open-ended; we can't insert intros between tracks
    /// the way we do for queued playlists).
    func playStation(_ station: StationInfo) async {
        guard guardPlaybackSupported() else { return }
        errorMessage = nil
        do {
            try await coordinator.startStation(id: station.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playAlbum(_ album: AlbumInfo) async {
        guard guardPlaybackSupported() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let tracks = try await musicService.songs(inAlbumWith: album.id)
            guard !tracks.isEmpty else { return }
            let items = tracks.map { PlayableItem.track($0) }
            await coordinator.replaceQueue(items)
            if let producer {
                await producer.primeOpeningIntro()
            }
            try? await coordinator.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPlaylist(_ playlist: PlaylistInfo) async {
        selectedPlaylist = playlist
        isLoading = true
        errorMessage = nil
        do {
            Log.app.info("selectPlaylist: fetching songs for '\(playlist.name, privacy: .public)' id=\(playlist.id, privacy: .public) on \(String(describing: self.activeProvider), privacy: .public)")
            songs = try await musicService.songs(inPlaylistWith: playlist.id)
            Log.app.info("selectPlaylist: fetched \(self.songs.count) songs")
        } catch {
            Log.app.error("selectPlaylist: fetch failed: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
            songs = []
        }
        isLoading = false
    }

    func addToQueue(_ track: AIDJ.Track) async {
        await coordinator.enqueue(.track(track))
    }

    func playPlaylist(_ playlist: PlaylistInfo) async {
        guard guardPlaybackSupported() else { return }
        Log.app.info("playPlaylist '\(playlist.name, privacy: .public)' on \(String(describing: self.activeProvider), privacy: .public)")
        await selectPlaylist(playlist)
        Log.app.info("playPlaylist: selectPlaylist returned \(self.songs.count) songs, errorMessage=\(self.errorMessage ?? "nil", privacy: .public)")
        let items = songs.map { PlayableItem.track($0) }
        guard !items.isEmpty else {
            let msg = errorMessage ?? "Playlist returned no tracks. If this is Spotify, try a different playlist or reconnect."
            playbackAlertMessage = msg
            Log.app.error("playPlaylist: empty queue — aborting. \(msg, privacy: .public)")
            return
        }
        await coordinator.replaceQueue(items)
        if let producer {
            await producer.primeOpeningIntro()
        }
        await invokePlay()
    }

    func shufflePlaylist(_ playlist: PlaylistInfo) async {
        guard guardPlaybackSupported() else { return }
        Log.app.info("shufflePlaylist '\(playlist.name, privacy: .public)' on \(String(describing: self.activeProvider), privacy: .public)")
        await selectPlaylist(playlist)
        Log.app.info("shufflePlaylist: selectPlaylist returned \(self.songs.count) songs")
        let items = songs.shuffled().map { PlayableItem.track($0) }
        guard !items.isEmpty else {
            playbackAlertMessage = errorMessage ?? "Playlist returned no tracks."
            return
        }
        await coordinator.replaceQueue(items)
        if let producer {
            await producer.primeOpeningIntro()
        }
        await invokePlay()
    }

    func playSong(_ track: AIDJ.Track) async {
        guard guardPlaybackSupported() else { return }
        Log.app.info("playSong '\(track.title, privacy: .public)' provider=\(String(describing: track.providerID), privacy: .public)")
        await coordinator.replaceQueue([.track(track)])
        if let producer {
            await producer.primeOpeningIntro()
        }
        await invokePlay()
    }

    /// Central play-kickoff that logs the attempt and surfaces errors to the
    /// UI via playbackAlertMessage instead of silently swallowing them. The
    /// Phase 1 try? pattern masked real failures during Phase 2b smoke —
    /// tapping play just did nothing with no user feedback.
    private func invokePlay() async {
        do {
            try await coordinator.play()
            Log.app.info("invokePlay: coordinator.play() returned")
        } catch {
            Log.app.error("invokePlay: coordinator.play() threw \(String(describing: error), privacy: .public)")
            playbackAlertMessage = "Couldn't start playback: \(error.localizedDescription)"
        }
    }

    // MARK: Search

    func filteredPlaylists(matching query: String) -> [PlaylistInfo] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        return playlists.filter { $0.name.lowercased().contains(needle) }
    }

    func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await musicService.searchCatalogSongs(query: trimmed, limit: 15)) ?? []
    }

    func clearSearch() {
        searchResults = []
        isSearching = false
    }
}
