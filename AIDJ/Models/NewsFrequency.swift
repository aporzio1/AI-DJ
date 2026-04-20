import Foundation

/// How often a fetched news headline is injected into the DJ's context.
/// Separate from `newsEnabled` (on/off master) — when news is enabled this
/// rolls against each segment to decide whether a headline is actually
/// handed to the brain, and at what cadence.
enum NewsFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case rarely
    case balanced
    case often
    case always

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rarely:   "Rarely"
        case .balanced: "Balanced"
        case .often:    "Often"
        case .always:   "Always"
        }
    }

    /// Probability that a given segment will include a news headline.
    var probability: Double {
        switch self {
        case .rarely:   0.20
        case .balanced: 0.50
        case .often:    0.75
        case .always:   1.00
        }
    }

    static let `default`: NewsFrequency = .balanced
}
