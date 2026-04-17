import Foundation

@Observable
@MainActor
final class LibraryViewModel {

    private(set) var playlists: [PlaylistInfo] = []
    private(set) var songs: [AIDJ.Track] = []
    private(set) var selectedPlaylist: PlaylistInfo?
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
