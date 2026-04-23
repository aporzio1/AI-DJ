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

    /// SF Symbol name for the current mode.
    var systemImage: String {
        switch self {
        case .off: "repeat"
        case .all: "repeat"
        case .one: "repeat.1"
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
