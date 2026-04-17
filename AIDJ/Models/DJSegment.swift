import Foundation

struct DJSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: Kind
    let script: String
    let audioFileURL: URL
    let duration: TimeInterval
    // Reserved for future talk-over — always nil in MVP
    let overlapStart: TimeInterval?

    enum Kind: String, Codable, Sendable {
        case announcement, banter, news
    }
}
