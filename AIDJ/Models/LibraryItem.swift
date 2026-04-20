import Foundation

/// Lightweight summary types for containers that aren't tracks.
/// Mirror `PlaylistInfo`'s shape so new card UIs can render any kind.

struct AlbumInfo: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
}

struct StationInfo: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let artworkURL: URL?
}

/// A single item in a Library surface (Recently Played, Recommendations, etc).
/// Kept provider-neutral so the same enum works for both Apple Music and
/// any future providers (Spotify, etc.).
///
/// Phase 1 (Recently Played) populates only `.track` and `.playlist` from
/// Apple Music; the other cases exist so Phase 2 (Recommendations) can add
/// them without touching the card view.
enum LibraryItem: Identifiable, Sendable, Hashable {
    case track(Track)
    case playlist(PlaylistInfo)
    case album(AlbumInfo)
    case station(StationInfo)

    var id: String {
        switch self {
        case .track(let t):    "track-\(t.id)"
        case .playlist(let p): "playlist-\(p.id)"
        case .album(let a):    "album-\(a.id)"
        case .station(let s):  "station-\(s.id)"
        }
    }

    var title: String {
        switch self {
        case .track(let t):    t.title
        case .playlist(let p): p.name
        case .album(let a):    a.title
        case .station(let s):  s.name
        }
    }

    var subtitle: String {
        switch self {
        case .track(let t):    t.artist
        case .playlist:        "Playlist"
        case .album(let a):    a.artist
        case .station:         "Station"
        }
    }

    var fallbackArtworkURL: URL? {
        switch self {
        case .track(let t):    t.artworkURL
        case .playlist(let p): p.artworkURL
        case .album(let a):    a.artworkURL
        case .station(let s):  s.artworkURL
        }
    }

    /// SF Symbol name used by the card when no artwork resolves.
    var placeholderSystemImage: String {
        switch self {
        case .track:    "music.note"
        case .playlist: "music.note.list"
        case .album:    "square.stack"
        case .station:  "dot.radiowaves.left.and.right"
        }
    }
}
