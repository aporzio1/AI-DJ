import Foundation
import MusicKit

/// Playback state mirroring ApplicationMusicPlayer states relevant to our queue logic.
enum MusicPlaybackStatus: Sendable, Equatable {
    case stopped, playing, paused
}

/// Lightweight struct representing a playlist entry for library browsing.
struct PlaylistInfo: Identifiable, Codable, Sendable, Hashable {
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
    func songs(inAlbumWith id: String) async throws -> [Track]
    func searchCatalogSongs(query: String, limit: Int) async throws -> [Track]

    /// Resolve a station by id and start it on ApplicationMusicPlayer.
    /// Stations are open-ended radio, not a finite track queue — they
    /// bypass the Producer/Coordinator pipeline and the DJ won't talk
    /// over them. Playback continues until the user skips or stops.
    func startStation(id: String) async throws

    /// Advance to the next track in ApplicationMusicPlayer's internal
    /// queue. Used while a station is playing so the mini-player skip
    /// button still works even though we have no track queue of our own.
    func skipToNext() async throws

    /// Recently-played items (tracks, playlists, albums, stations). Kept
    /// provider-neutral so Spotify can provide the same shape later.
    func recentlyPlayed() async throws -> [LibraryItem]

    /// Personal recommendations flattened into a simple list. Phase 2
    /// implementation filters to `.playlist` cases only so every card has
    /// a consistent tap-to-detail behavior.
    func recommendations() async throws -> [LibraryItem]

    /// Provider-neutral artwork for a previously-fetched item, or nil if not cached.
    /// Phase 1 only wires this up for cached tracks; containers fall back to
    /// `LibraryItem.fallbackArtworkURL` via the `.url` case.
    func providerArtwork(for itemId: String) -> ProviderArtwork?

    /// Returns true if MusicKit thinks this track can actually be played right now.
    /// Library or catalog items with nil playParameters are unavailable (region,
    /// rights, removal, or stale cloud reference).
    func isPlayable(trackId: String) async -> Bool

    /// Returns cached MusicKit Artwork for a previously-fetched track, or nil if not cached.
    /// Used to drive ArtworkImage which handles the `musicKit://` URLs that AsyncImage can't.
    func artwork(for trackId: String) -> Artwork?
}
