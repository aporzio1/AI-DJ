import Foundation
@preconcurrency import MusicKit

@MainActor
final class MusicKitService: MusicKitServiceProtocol {

    private let player = ApplicationMusicPlayer.shared
    private var observationTask: Task<Void, Never>?
    private var artworkCache: [String: Artwork] = [:]

    var authorizationStatus: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }

    // MARK: Playback control

    func start(track: Track) async throws {
        Log.musicKit.info("start(track: '\(track.title, privacy: .public)')")
        let song = try await resolveSong(id: track.id)
        player.queue = ApplicationMusicPlayer.Queue(for: [song])
        try await player.play()
        Log.musicKit.debug("player.play() returned, playbackTime=\(self.player.playbackTime) status=\(String(describing: self.player.state.playbackStatus), privacy: .public)")
    }

    /// Tries the user's library first, falls back to the Apple Music catalog.
    /// Needed because search returns catalog IDs, playlists return library IDs.
    private func resolveSong(id: String) async throws -> Song {
        var libRequest = MusicLibraryRequest<Song>()
        libRequest.filter(matching: \.id, equalTo: MusicItemID(rawValue: id))
        if let librarySong = (try? await libRequest.response())?.items.first {
            return librarySong
        }
        let catalogRequest = MusicCatalogResourceRequest<Song>(
            matching: \.id, equalTo: MusicItemID(rawValue: id)
        )
        let catalogResponse = try await catalogRequest.response()
        guard let catalogSong = catalogResponse.items.first else {
            Log.musicKit.error("start failed: track not found in library or catalog")
            throw MusicKitServiceError.trackNotFound(id: id)
        }
        return catalogSong
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
        Log.musicKit.debug("seek: setting playbackTime to \(time) (was \(self.player.playbackTime))")
        player.playbackTime = time
        Log.musicKit.debug("seek: playbackTime is now \(self.player.playbackTime)")
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
        cacheArtwork(for: song)
        return Track(song: song)
    }

    func artwork(for trackId: String) -> Artwork? {
        artworkCache[trackId]
    }

    private func cacheArtwork(for song: Song) {
        if let art = song.artwork {
            artworkCache[song.id.rawValue] = art
        }
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

    func searchCatalogSongs(query: String, limit: Int) async throws -> [Track] {
        guard !query.isEmpty else { return [] }
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = limit
        let response = try await request.response()
        let songs = Array(response.songs)
        for song in songs { cacheArtwork(for: song) }
        return songs.map(Track.init(song:))
    }

    func songs(inPlaylistWith id: String) async throws -> [Track] {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(rawValue: id))
        let response = try await request.response()
        guard let playlist = response.items.first else { return [] }
        let detailed = try await playlist.with([.tracks])
        let songs = detailed.tracks?.compactMap { track -> Song? in
            if case .song(let s) = track { return s }
            return nil
        } ?? []
        for song in songs { cacheArtwork(for: song) }
        return songs.map(Track.init(song:))
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
