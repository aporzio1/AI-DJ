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

    private let musicService: any MusicKitServiceProtocol
    private let coordinator: PlaybackCoordinator
    private let producer: Producer?

    init(musicService: any MusicKitServiceProtocol, coordinator: PlaybackCoordinator, producer: Producer? = nil) {
        self.musicService = musicService
        self.coordinator = coordinator
        self.producer = producer
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
    /// cache is missing or older than the TTL. Pass `forceRefresh: true`
    /// to bypass the TTL (pull-to-refresh / manual refresh button).
    func loadRecentlyPlayed(forceRefresh: Bool = false) async {
        let cached = LibrarySectionCache.load(.recentlyPlayed)
        if let cached {
            recentlyPlayed = cached.items
        }
        let shouldRefresh = forceRefresh
            || cached == nil
            || !(cached?.isFresh(ttl: LibrarySectionCache.ttl) ?? false)
        guard shouldRefresh else { return }

        if let items = try? await musicService.recentlyPlayed() {
            recentlyPlayed = items
            LibrarySectionCache.save(items, for: .recentlyPlayed)
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
        let shouldRefresh = forceRefresh
            || cached == nil
            || !(cached?.isFresh(ttl: LibrarySectionCache.ttl) ?? false)
        guard shouldRefresh else { return }

        if let items = try? await musicService.recommendations() {
            recommendations = items
            LibrarySectionCache.save(items, for: .recommendations)
        }
    }

    /// Pull-to-refresh / manual refresh hook — bypasses TTL on both sections.
    func refreshLibrarySections() async {
        async let rp: Void = loadRecentlyPlayed(forceRefresh: true)
        async let rec: Void = loadRecommendations(forceRefresh: true)
        _ = await (rp, rec)
    }

    /// Handles a tap on a Library card. Tracks play directly; containers
    /// are either navigated to (playlist has a detail view) or played as a
    /// whole — but container playback for albums/stations isn't wired yet
    /// and these cases are not populated in Phase 1.
    func playLibraryItem(_ item: LibraryItem) async {
        switch item {
        case .track(let t):
            await playSong(t)
        case .playlist(let p):
            await playPlaylist(p)
        case .album, .station:
            break  // Phase 2 territory; cards render but don't act yet.
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
        await selectPlaylist(playlist)
        let items = songs.map { PlayableItem.track($0) }
        await coordinator.replaceQueue(items)
        if let producer {
            await producer.primeOpeningIntro()
        }
        try? await coordinator.play()
    }

    func shufflePlaylist(_ playlist: PlaylistInfo) async {
        await selectPlaylist(playlist)
        let items = songs.shuffled().map { PlayableItem.track($0) }
        await coordinator.replaceQueue(items)
        if let producer {
            await producer.primeOpeningIntro()
        }
        try? await coordinator.play()
    }

    func playSong(_ track: AIDJ.Track) async {
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
