import Foundation
import MusicKit

/// Playback state mirroring ApplicationMusicPlayer states relevant to our queue logic.
enum MusicPlaybackStatus: Sendable, Equatable {
    case stopped, playing, paused
}

/// Lightweight struct representing a playlist entry for library browsing.
struct PlaylistInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let artworkURL: URL?
}

@MainActor
protocol MusicKitServiceProtocol: AnyObject, Sendable {
    var authorizationStatus: MusicAuthorization.Status { get }

    func requestAuthorization() async -> MusicAuthorization.Status
    func start(track: Track) async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
    func seek(to time: TimeInterval) async throws

    /// Returns elapsed playback time for the current track.
    var currentPlaybackTime: TimeInterval { get }
    /// Duration of the current track, or nil if unknown.
    var currentTrackDuration: TimeInterval? { get }
    var currentTrack: Track? { get }
    var playbackStatus: MusicPlaybackStatus { get }

    func playlists() async throws -> [PlaylistInfo]
    func songs(inPlaylistWith id: String) async throws -> [Track]
    func searchCatalogSongs(query: String, limit: Int) async throws -> [Track]

    /// Returns cached MusicKit Artwork for a previously-fetched track, or nil if not cached.
    /// Used to drive ArtworkImage which handles the `musicKit://` URLs that AsyncImage can't.
    func artwork(for trackId: String) -> Artwork?
}
