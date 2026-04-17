import Foundation

@Observable
@MainActor
final class LibraryViewModel {

    private(set) var playlists: [PlaylistInfo] = []
    private(set) var songs: [AIDJ.Track] = []
    private(set) var selectedPlaylist: PlaylistInfo?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

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
        // Prime an opening DJ intro before the first track plays
        if let producer {
            await producer.primeOpeningIntro()
        }
        try? await coordinator.play()
    }
}
