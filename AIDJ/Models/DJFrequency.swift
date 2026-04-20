import Foundation

/// How often the DJ drops a segment between songs.
/// Drives `Producer.shouldGenerate` via a (maxGap, randomChance) pair:
/// a segment is forced once `maxGap` tracks have elapsed without one, and
/// between those forced segments each track has `randomChance` odds of
/// triggering one for variety.
enum DJFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case rarely
    case balanced
    case often
    case everySong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rarely:    "Rarely"
        case .balanced:  "Balanced"
        case .often:     "Often"
        case .everySong: "Every Song"
        }
    }

    /// Force a segment once this many tracks have passed without one.
    var maxGap: Int {
        switch self {
        case .rarely:    6
        case .balanced:  3
        case .often:     2
        case .everySong: 1
        }
    }

    /// Probability that a track between forced segments also triggers one.
    /// 0.0 on `.rarely` means the DJ only appears on the guaranteed cadence.
    var randomChance: Double {
        switch self {
        case .rarely:    0.0
        case .balanced:  0.5
        case .often:     0.75
        case .everySong: 1.0
        }
    }

    static let `default`: DJFrequency = .balanced
}
