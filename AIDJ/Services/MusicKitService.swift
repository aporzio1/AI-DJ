import Foundation
@preconcurrency import MusicKit

@MainActor
final class MusicKitService: MusicKitServiceProtocol {

    private let player = ApplicationMusicPlayer.shared
    private var observationTask: Task<Void, Never>?

    var authorizationStatus: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }

    // MARK: Playback control

    func start(track: Track) async throws {
        print("[MusicKit] start(track: '\(track.title)')")
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.id, equalTo: MusicItemID(rawValue: track.id))
        let response = try await request.response()
        guard let song = response.items.first else {
            print("[MusicKit] start failed: track not found")
            throw MusicKitServiceError.trackNotFound(id: track.id)
        }
        player.queue = ApplicationMusicPlayer.Queue(for: [song])
        try await player.play()
        print("[MusicKit] player.play() returned, playbackTime=\(player.playbackTime) status=\(player.state.playbackStatus)")
    }

    func pause() async throws {
        player.pause()
    }

    func resume() async throws {
        try await player.play()
    }

    func stop() async throws {
        player.stop()
    }

    func seek(to time: TimeInterval) async throws {
        print("[MusicKit] seek: setting playbackTime to \(time) (was \(player.playbackTime))")
        player.playbackTime = time
        print("[MusicKit] seek: playbackTime is now \(player.playbackTime)")
    }

    // MARK: State

    var currentPlaybackTime: TimeInterval {
        player.playbackTime
    }

    var currentTrackDuration: TimeInterval? {
        guard case .song(let song) = player.queue.currentEntry?.item else { return nil }
        return song.duration.map { TimeInterval($0) }
    }

    var currentTrack: Track? {
        guard case .song(let song) = player.queue.currentEntry?.item else { return nil }
        return Track(song: song)
    }

    var playbackStatus: MusicPlaybackStatus {
        switch player.state.playbackStatus {
        case .playing:    .playing
        case .paused:     .paused
        default:          .stopped
        }
    }

    // MARK: Library

    func playlists() async throws -> [PlaylistInfo] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 100
        let response = try await request.response()
        return response.items.map {
            PlaylistInfo(
                id: $0.id.rawValue,
                name: $0.name,
                artworkURL: $0.artwork?.url(width: 200, height: 200)
            )
        }
    }

    func songs(inPlaylistWith id: String) async throws -> [Track] {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(rawValue: id))
        let response = try await request.response()
        guard let playlist = response.items.first else { return [] }
        let detailed = try await playlist.with([.tracks])
        return detailed.tracks?.compactMap(\.asTrack) ?? []
    }
}

enum MusicKitServiceError: Error {
    case trackNotFound(id: String)
}

private extension Track {
    init(song: Song) {
        self.init(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle ?? "",
            artworkURL: song.artwork?.url(width: 300, height: 300),
            duration: song.duration.map { TimeInterval($0) } ?? 0,
            providerID: .appleMusic
        )
    }
}

private extension MusicKit.Track {
    var asTrack: AIDJ.Track? {
        switch self {
        case .song(let song):
            return AIDJ.Track(song: song)
        default:
            return nil
        }
    }
}
