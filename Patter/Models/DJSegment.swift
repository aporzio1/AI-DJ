import Foundation

struct DJSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: Kind
    let script: String
    let audioFileURL: URL
    let duration: TimeInterval
    // Reserved for future talk-over — always nil in MVP
    let overlapStart: TimeInterval?
    /// The source headline this segment was built around, when `kind == .news`.
    /// `nil` for announcement / banter segments. Surfaced in NowPlayingView so
    /// the listener can open the article being discussed.
    let sourceHeadline: NewsHeadline?

    enum Kind: String, Codable, Sendable {
        case announcement, banter, news
    }
}
