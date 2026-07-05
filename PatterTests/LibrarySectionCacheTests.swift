import Testing
import Foundation
@testable import Patter

@Suite("LibrarySectionCache")
struct LibrarySectionCacheTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "LibrarySectionCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTrack(id: String = "t1") -> LibraryItem {
        .track(Track(id: id, title: "Song", artist: "Artist", album: "Album", artworkURL: nil, duration: 180, providerID: .appleMusic))
    }

    @Test func loadReturnsNilWhenNothingSaved() {
        let defaults = makeDefaults()
        #expect(LibrarySectionCache.load(.recentlyPlayed, provider: .appleMusic, defaults: defaults) == nil)
    }

    @Test func saveThenLoadRoundtrips() {
        let defaults = makeDefaults()
        let items = [makeTrack(id: "t1"), makeTrack(id: "t2")]
        LibrarySectionCache.save(items, for: .recentlyPlayed, provider: .appleMusic, defaults: defaults)

        let loaded = LibrarySectionCache.load(.recentlyPlayed, provider: .appleMusic, defaults: defaults)
        #expect(loaded?.items.map(\.id) == items.map(\.id))
    }

    @Test func clearRemovesEntry() {
        let defaults = makeDefaults()
        LibrarySectionCache.save([makeTrack()], for: .recentlyPlayed, provider: .appleMusic, defaults: defaults)
        LibrarySectionCache.clear(.recentlyPlayed, provider: .appleMusic, defaults: defaults)

        #expect(LibrarySectionCache.load(.recentlyPlayed, provider: .appleMusic, defaults: defaults) == nil)
    }

    @Test func sectionsDoNotCollide() {
        let defaults = makeDefaults()
        LibrarySectionCache.save([makeTrack(id: "recent")], for: .recentlyPlayed, provider: .appleMusic, defaults: defaults)
        LibrarySectionCache.save([makeTrack(id: "rec")], for: .recommendations, provider: .appleMusic, defaults: defaults)

        #expect(LibrarySectionCache.load(.recentlyPlayed, provider: .appleMusic, defaults: defaults)?.items.first?.id == "track-recent")
        #expect(LibrarySectionCache.load(.recommendations, provider: .appleMusic, defaults: defaults)?.items.first?.id == "track-rec")
    }

    @Test func clearingOneSectionLeavesTheOtherIntact() {
        let defaults = makeDefaults()
        LibrarySectionCache.save([makeTrack()], for: .recentlyPlayed, provider: .appleMusic, defaults: defaults)
        LibrarySectionCache.save([makeTrack()], for: .recommendations, provider: .appleMusic, defaults: defaults)

        LibrarySectionCache.clear(.recentlyPlayed, provider: .appleMusic, defaults: defaults)

        #expect(LibrarySectionCache.load(.recentlyPlayed, provider: .appleMusic, defaults: defaults) == nil)
        #expect(LibrarySectionCache.load(.recommendations, provider: .appleMusic, defaults: defaults) != nil)
    }

    // MARK: - Entry.isFresh TTL

    @Test func entryIsFreshWithinTTL() {
        let entry = LibrarySectionCache.Entry(fetchedAt: Date(), items: [])
        #expect(entry.isFresh(ttl: 30 * 60))
    }

    @Test func entryIsStaleBeyondTTL() {
        let old = Date().addingTimeInterval(-(31 * 60))
        let entry = LibrarySectionCache.Entry(fetchedAt: old, items: [])
        #expect(!entry.isFresh(ttl: 30 * 60))
    }

    @Test func entryFreshnessBoundaryIsExclusive() {
        // Exactly `ttl` ago should already read as stale (`<` not `<=`).
        let boundary = Date().addingTimeInterval(-(30 * 60 + 1))
        let entry = LibrarySectionCache.Entry(fetchedAt: boundary, items: [])
        #expect(!entry.isFresh(ttl: 30 * 60))
    }
}
