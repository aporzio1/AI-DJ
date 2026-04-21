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

    /// Phase 2a ships Spotify read-only — playback lands in 2b. When the
    /// active provider is Spotify, any play attempt sets a user-visible
    /// message explaining the gate instead of silently hitting the
    /// coordinator's `notSupportedYet` throw.
    private func guardPlaybackSupported() -> Bool {
        if activeProvider == .spotify {
            errorMessage = "Spotify playback is coming in Phase 2b. Browsing works now."
            return false
        }
        return true
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
        let cached = LibrarySectionCache.load(.recentlyPlayed)
        if let cached {
            recentlyPlayed = cached.items
        }
        let isStale = cached.map { !$0.isFresh(ttl: LibrarySectionCache.ttl) } ?? true
        let isEmpty = cached?.items.isEmpty ?? true
        guard forceRefresh || isStale || isEmpty else { return }

        if let items = try? await musicService.recentlyPlayed() {
            recentlyPlayed = items
            if !items.isEmpty {
                LibrarySectionCache.save(items, for: .recentlyPlayed)
            }
        }
        // Silent-stale on failure: leave cached items in place, log nothing
        // user-visible. ContentUnavailableView path only triggers when BOTH
        // cache is empty AND the fetch failed.
    }

    func loadRecommendations(forceRefresh: Bool = false) async {
        let cached = LibrarySectionCache.load(.recommendations)
        if let cached {
            recommendations = cached.items
        }
        let isStale = cached.map { !$0.isFresh(ttl: LibrarySectionCache.ttl) } ?? true
        let isEmpty = cached?.items.isEmpty ?? true
        guard forceRefresh || isStale || isEmpty else { return }

        if let items = try? await musicService.recommendations() {
            recommendations = items
            if !items.isEmpty {
                LibrarySectionCache.save(items, for: .recommendations)
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
        do {
            songs = try await musicService.songs(inPlaylistWith: playlist.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addToQueue(_ track: AIDJ.Track) async {
        await coordinator.enqueue(.track(track))
    }

    func playPlaylist(_ playlist: PlaylistInfo) async {
        guard guardPlaybackSupported() else { return }
        await selectPlaylist(playlist)
        let items = songs.map { PlayableItem.track($0) }
        await coordinator.replaceQueue(items)
        if let producer {
            await producer.primeOpeningIntro()
        }
        try? await coordinator.play()
    }

    func shufflePlaylist(_ playlist: PlaylistInfo) async {
        guard guardPlaybackSupported() else { return }
        await selectPlaylist(playlist)
        let items = songs.shuffled().map { PlayableItem.track($0) }
        await coordinator.replaceQueue(items)
        if let producer {
            await producer.primeOpeningIntro()
        }
        try? await coordinator.play()
    }

    func playSong(_ track: AIDJ.Track) async {
        guard guardPlaybackSupported() else { return }
        await coordinator.replaceQueue([.track(track)])
        if let producer {
            await producer.primeOpeningIntro()
        }
        try? await coordinator.play()
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
