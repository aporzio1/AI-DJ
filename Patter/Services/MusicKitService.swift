import Foundation
@preconcurrency import MusicKit

@MainActor
final class MusicKitService: MusicProviderService {

    private let player = ApplicationMusicPlayer.shared
    private var observationTask: Task<Void, Never>?
    private var artworkCache: [String: Artwork] = [:]

    let providerID: Patter.Track.MusicProviderID = .appleMusic

    var authorizationStatus: ProviderAuthStatus {
        ProviderAuthStatus(MusicAuthorization.currentStatus)
    }

    func requestAuthorization() async -> ProviderAuthStatus {
        ProviderAuthStatus(await MusicAuthorization.request())
    }

    /// Apple Music authorization is OS-managed — the user revokes access from
    /// system Settings, not in-app. No-op.
    func signOut() async {}

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

    func skipToNext() async throws {
        try await player.skipToNextEntry()
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

    func artwork(for trackId: String) -> ProviderArtwork? {
        if let art = artworkCache[trackId] { return .musicKit(art) }
        return nil
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
        let allSongs = detailed.tracks?.compactMap { track -> Song? in
            if case .song(let s) = track { return s }
            return nil
        } ?? []
        let playable = allSongs.filter { $0.playParameters != nil }
        let skipped = allSongs.count - playable.count
        if skipped > 0 {
            Log.musicKit.info("songs(inPlaylist): skipped \(skipped) unplayable tracks of \(allSongs.count)")
        }
        for song in playable { cacheArtwork(for: song) }
        return playable.map(Track.init(song:))
    }

    func isPlayable(trackId: String) async -> Bool {
        do {
            let song = try await resolveSong(id: trackId)
            return song.playParameters != nil
        } catch {
            return false
        }
    }

    // MARK: Recently Played

    /// Queries MusicKit for recently-played songs. Phase 1 is tracks-only;
    /// the LibraryItem enum has cases for playlist/album/station so Phase 2
    /// (Recommendations) can populate those without touching the card UI.
    func recentlyPlayed() async throws -> [LibraryItem] {
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = 20
        let response = try await request.response()
        let songs = Array(response.items)
        for song in songs { cacheArtwork(for: song) }
        return songs.map { LibraryItem.track(Track(song: $0)) }
    }

    /// Flattens Apple's personal recommendations into a provider-neutral list.
    /// Includes playlists, albums, AND stations — previously playlists-only,
    /// but user-facing accounts can have a playlist-sparse recommendation set
    /// and the row rendered empty. Albums and stations surface as cards; tap
    /// wiring is handled per-type in `LibraryView.cardWrapper`.
    func recommendations() async throws -> [LibraryItem] {
        let request = MusicPersonalRecommendationsRequest()
        let response = try await request.response()
        var seen = Set<String>()
        var items: [LibraryItem] = []
        var playlistCount = 0
        var albumCount = 0
        var stationCount = 0

        for rec in response.recommendations {
            for playlist in rec.playlists {
                let id = playlist.id.rawValue
                guard seen.insert(id).inserted else { continue }
                items.append(LibraryItem.playlist(PlaylistInfo(
                    id: id,
                    name: playlist.name,
                    artworkURL: playlist.artwork?.url(width: 200, height: 200)
                )))
                playlistCount += 1
                if items.count >= 24 { break }
            }
            for album in rec.albums {
                let id = album.id.rawValue
                guard seen.insert(id).inserted else { continue }
                items.append(LibraryItem.album(AlbumInfo(
                    id: id,
                    title: album.title,
                    artist: album.artistName,
                    artworkURL: album.artwork?.url(width: 200, height: 200)
                )))
                albumCount += 1
                if items.count >= 24 { break }
            }
            for station in rec.stations {
                let id = station.id.rawValue
                guard seen.insert(id).inserted else { continue }
                items.append(LibraryItem.station(StationInfo(
                    id: id,
                    name: station.name,
                    artworkURL: station.artwork?.url(width: 200, height: 200)
                )))
                stationCount += 1
                if items.count >= 24 { break }
            }
            if items.count >= 24 { break }
        }
        Log.musicKit.info("recommendations: \(response.recommendations.count) buckets → \(playlistCount) playlists, \(albumCount) albums, \(stationCount) stations (\(items.count) total after dedupe)")
        return items
    }

    /// Resolves a station by id in the catalog and starts it on
    /// ApplicationMusicPlayer directly. Does NOT go through the
    /// coordinator / Producer pipeline — stations are open-ended radio
    /// and have a different queue shape than our `[Track]` model. The
    /// DJ voice doesn't fire while a station is playing.
    func startStation(id: String) async throws {
        let request = MusicCatalogResourceRequest<Station>(
            matching: \.id, equalTo: MusicItemID(rawValue: id)
        )
        let response = try await request.response()
        guard let station = response.items.first else {
            Log.musicKit.error("startStation: station id \(id, privacy: .public) not found in catalog")
            throw MusicKitServiceError.trackNotFound(id: id)
        }
        Log.musicKit.info("startStation '\(station.name, privacy: .public)'")
        player.queue = ApplicationMusicPlayer.Queue(for: [station])
        try await player.play()
    }

    /// Resolves a catalog or library album to its songs for queue-based
    /// playback. Used by the Library card tap when a recommendation is an
    /// album rather than a playlist.
    func songs(inAlbumWith id: String) async throws -> [Track] {
        // Try the user's library first, fall back to the catalog — same
        // pattern as resolveSong / songs(inPlaylistWith:).
        var libRequest = MusicLibraryRequest<Album>()
        libRequest.filter(matching: \.id, equalTo: MusicItemID(rawValue: id))
        if let libraryAlbum = (try? await libRequest.response())?.items.first {
            let detailed = try await libraryAlbum.with([.tracks])
            let songs = (detailed.tracks ?? []).compactMap { track -> Song? in
                if case .song(let s) = track { return s }
                return nil
            }
            for song in songs { cacheArtwork(for: song) }
            return songs.map(Track.init(song:))
        }
        let catalogRequest = MusicCatalogResourceRequest<Album>(
            matching: \.id, equalTo: MusicItemID(rawValue: id)
        )
        let catalogResponse = try await catalogRequest.response()
        guard let catalogAlbum = catalogResponse.items.first else { return [] }
        let detailed = try await catalogAlbum.with([.tracks])
        let songs = (detailed.tracks ?? []).compactMap { track -> Song? in
            if case .song(let s) = track { return s }
            return nil
        }
        for song in songs { cacheArtwork(for: song) }
        return songs.map(Track.init(song:))
    }

}

enum MusicKitServiceError: Error {
    case trackNotFound(id: String)
}

private extension ProviderAuthStatus {
    init(_ status: MusicAuthorization.Status) {
        switch status {
        case .authorized:          self = .authorized
        case .denied, .restricted: self = .notAuthorized
        case .notDetermined:       self = .unknown
        @unknown default:          self = .unknown
        }
    }
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
    var asTrack: Patter.Track? {
        switch self {
        case .song(let song):
            return Patter.Track(song: song)
        default:
            return nil
        }
    }
}
