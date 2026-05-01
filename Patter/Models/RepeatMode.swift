import Foundation

/// Three-way repeat state for the playback queue.
enum RepeatMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    /// Cycle through modes: off → all → one → off.
    func next() -> RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    /// SF Symbol name for the current mode. Active modes use the filled-circle
    /// variant so .off vs .all is distinguishable by shape, not color alone —
    /// otherwise low-vision and color-blind users see only an accent tint flip.
    var systemImage: String {
        switch self {
        case .off: "repeat"
        case .all: "repeat.circle.fill"
        case .one: "repeat.1.circle.fill"
        }
    }

    var isActive: Bool { self != .off }

    var accessibilityLabel: String {
        switch self {
        case .off: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }
}
