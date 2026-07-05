import Testing
import Foundation
@testable import Patter

@Suite("TrackFeedbackStore")
struct TrackFeedbackStoreTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: makeSuiteName())!
    }

    /// Returns a fresh, empty suite name. Callers that need two `UserDefaults`
    /// instances backed by the same underlying storage (e.g. testing
    /// persistence across store instances) should construct
    /// `UserDefaults(suiteName:)` separately at each call site rather than
    /// reusing one `UserDefaults` value — passing the same value into two
    /// actor-isolated inits trips Swift 6's region-isolation "sending" check.
    private func makeSuiteName() -> String {
        let suiteName = "TrackFeedbackStoreTests.\(UUID().uuidString)"
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
        return suiteName
    }

    @Test func recordThenRatingReturnsLatest() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        await store.record(.up, trackID: "t1", title: "Song A", artist: "Artist A")
        #expect(await store.rating(for: "t1") == .up)

        await store.record(.down, trackID: "t1", title: "Song A", artist: "Artist A")
        #expect(await store.rating(for: "t1") == .down)
    }

    @Test func ratingForUnknownTrackIsNil() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        #expect(await store.rating(for: "missing") == nil)
    }

    @Test func capsAtMaxFiftyEntriesFIFO() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        for i in 0..<60 {
            await store.record(.up, trackID: "t\(i)", title: "Song \(i)", artist: "Artist")
        }
        // Oldest 10 (t0...t9) should have been trimmed; newest 50 (t10...t59) remain.
        #expect(await store.rating(for: "t0") == nil)
        #expect(await store.rating(for: "t9") == nil)
        #expect(await store.rating(for: "t10") == .up)
        #expect(await store.rating(for: "t59") == .up)
    }

    @Test func summaryDedupesByTrackIDNewestFirst() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        await store.record(.up, trackID: "t1", title: "Song A", artist: "Artist A")
        await store.record(.up, trackID: "t2", title: "Song B", artist: "Artist B")
        // Re-rate t1 — should move to the front of the summary, not appear twice.
        await store.record(.up, trackID: "t1", title: "Song A", artist: "Artist A")

        let summary = await store.summary()
        #expect(summary.likes == ["Song A by Artist A", "Song B by Artist B"])
        #expect(summary.dislikes.isEmpty)
    }

    @Test func summarySeparatesLikesAndDislikes() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        await store.record(.up, trackID: "t1", title: "Liked", artist: "Artist")
        await store.record(.down, trackID: "t2", title: "Disliked", artist: "Artist")

        let summary = await store.summary()
        #expect(summary.likes == ["Liked by Artist"])
        #expect(summary.dislikes == ["Disliked by Artist"])
    }

    @Test func summaryRespectsPerRatingLimit() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        for i in 0..<10 {
            await store.record(.up, trackID: "t\(i)", title: "Song \(i)", artist: "Artist")
        }
        let summary = await store.summary(likeLimit: 3, dislikeLimit: 3)
        #expect(summary.likes.count == 3)
        // Newest-first: last recorded (t9) should be first in the summary.
        #expect(summary.likes.first == "Song 9 by Artist")
    }

    @Test func clearRemovesRatingForTrack() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        await store.record(.up, trackID: "t1", title: "Song A", artist: "Artist A")
        await store.clear(trackID: "t1")
        #expect(await store.rating(for: "t1") == nil)
    }

    @Test func clearOnlyAffectsTargetTrack() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        await store.record(.up, trackID: "t1", title: "Song A", artist: "Artist A")
        await store.record(.down, trackID: "t2", title: "Song B", artist: "Artist B")
        await store.clear(trackID: "t1")
        #expect(await store.rating(for: "t1") == nil)
        #expect(await store.rating(for: "t2") == .down)
    }

    @Test func persistsAcrossInstancesOnSameDefaults() async {
        let suiteName = makeSuiteName()
        let first = TrackFeedbackStore(defaults: UserDefaults(suiteName: suiteName)!)
        await first.record(.up, trackID: "t1", title: "Song A", artist: "Artist A")

        let second = TrackFeedbackStore(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(await second.rating(for: "t1") == .up)
    }

    @Test func freshDefaultsStartEmpty() async {
        let store = TrackFeedbackStore(defaults: makeDefaults())
        let summary = await store.summary()
        #expect(summary.isEmpty)
    }
}
