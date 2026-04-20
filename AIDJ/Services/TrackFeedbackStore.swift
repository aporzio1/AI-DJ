import Foundation

/// Actor-backed store for listener feedback (thumbs up/down) on tracks.
/// Persists a bounded rolling list to UserDefaults so the Producer can
/// summarize recent likes/dislikes into the DJ prompt without any main-actor
/// contention.
actor TrackFeedbackStore {

    /// Cap the list so UserDefaults payload stays small and the rolling
    /// summary stays meaningful — older entries wouldn't be referenced anyway.
    private static let maxEntries = 50
    private static let storageKey = "trackFeedbackEntries"

    private var entries: [TrackFeedback] = []

    init() {
        // Inline the load so nonisolated init doesn't have to hop to the
        // actor for a helper method call.
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([TrackFeedback].self, from: data) {
            entries = decoded
        }
    }

    // MARK: - Read

    /// Most recent rating for a given track, or nil if never rated.
    func rating(for trackID: String) -> TrackFeedback.Rating? {
        entries.last(where: { $0.trackID == trackID })?.rating
    }

    /// Short string summary, newest-first, for the DJ prompt.
    func summary(likeLimit: Int = 5, dislikeLimit: Int = 5) -> FeedbackSummary {
        let likes = lastRated(.up, limit: likeLimit)
        let dislikes = lastRated(.down, limit: dislikeLimit)
        return FeedbackSummary(
            likes: likes.map { "\($0.title) by \($0.artist)" },
            dislikes: dislikes.map { "\($0.title) by \($0.artist)" }
        )
    }

    private func lastRated(_ rating: TrackFeedback.Rating, limit: Int) -> [TrackFeedback] {
        // Reverse-chronological, deduped on trackID so repeated ratings of
        // the same track don't crowd the summary.
        var seen = Set<String>()
        var result: [TrackFeedback] = []
        for entry in entries.reversed() where entry.rating == rating {
            if seen.insert(entry.trackID).inserted {
                result.append(entry)
                if result.count >= limit { break }
            }
        }
        return result
    }

    // MARK: - Write

    /// Record a rating. Overrides any prior rating for the same track.
    func record(_ rating: TrackFeedback.Rating, trackID: String, title: String, artist: String) {
        let entry = TrackFeedback(
            trackID: trackID,
            title: title,
            artist: artist,
            rating: rating,
            timestamp: Date()
        )
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        save()
    }

    /// Remove any recorded rating for this track (neutral state).
    func clear(trackID: String) {
        entries.removeAll { $0.trackID == trackID }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
