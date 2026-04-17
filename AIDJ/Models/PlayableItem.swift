import Foundation

enum PlayableItem: Sendable {
    case track(Track)
    case djSegment(DJSegment)
}

extension PlayableItem: Identifiable {
    var id: String {
        switch self {
        case .track(let t): "track-\(t.id)"
        case .djSegment(let s): "segment-\(s.id)"
        }
    }
}
