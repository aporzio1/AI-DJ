import Foundation

/// Per-track like/dislike recorded from the Now Playing view. Stored as a
/// rolling list keyed by `Track.id` so the DJ prompt can reference what the
/// listener's been enjoying or skipping.
struct TrackFeedback: Codable, Sendable, Equatable {
    let trackID: String
    let title: String
    let artist: String
    let rating: Rating
    let timestamp: Date

    enum Rating: String, Codable, Sendable {
        case up
        case down
    }
}

/// Producer-facing summary of recent likes/dislikes for DJ prompt injection.
struct FeedbackSummary: Sendable {
    let likes: [String]      // "Song Title by Artist"
    let dislikes: [String]

    var isEmpty: Bool { likes.isEmpty && dislikes.isEmpty }
}
