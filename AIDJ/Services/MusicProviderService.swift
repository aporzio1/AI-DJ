import Foundation

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
protocol MusicProviderService: AnyObject, Sendable {
    /// Identifies which music provider this service wraps. `MusicProviderRouter`
    /// dispatches track-bearing methods (e.g. `start(track:)`) to the service
    /// whose `providerID` matches `track.providerID`.
    var providerID: Track.MusicProviderID { get }

    var authorizationStatus: ProviderAuthStatus { get }

    func requestAuthorization() async -> ProviderAuthStatus

    /// Clear persisted credentials for providers that vend their own tokens.
    /// MusicKit is a no-op — Apple Music authorization is OS-managed and can
    /// only be revoked through system Settings. Kept on the protocol so a
    /// future non-OS-managed provider can implement it without reshaping the
    /// call sites.
    func signOut() async

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

    /// Returns true if the provider thinks this track can actually be played right now.
    /// Library or catalog items with nil playParameters are unavailable (region,
    /// rights, removal, or stale cloud reference).
    func isPlayable(trackId: String) async -> Bool

    /// Provider-neutral artwork for a previously-fetched track or item, or nil
    /// if not cached. `.musicKit` routes through MusicKit's `ArtworkImage` (which
    /// handles `musicKit://` URLs that `AsyncImage` can't); `.url` routes through
    /// `AsyncImage`. Callers pair this with an optional fallback URL for items
    /// that are known but not yet cached.
    func artwork(for trackId: String) -> ProviderArtwork?
}

