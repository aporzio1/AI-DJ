import Foundation

/// Disk cache for the Library tab's Recently Played + Made for You sections.
/// Stale-while-revalidate: on appearance the UI renders cached content
/// instantly while a background refresh runs if the cache is older than
/// `ttl`. Deliberately DEVICE-LOCAL (NOT synced via CloudSyncService) —
/// recently-played is inherently per-device, recommendations are re-derived
/// server-side per fetch. Syncing would add conflict surface for zero UX
/// gain.
///
/// Keys are versioned (`library.recentlyPlayed.v1`) so if `LibraryItem`
/// gains a new case in a future release we can bump the version and
/// silently ignore old payloads without a migration.
enum LibrarySectionCache {

    /// Newest-first items + the timestamp of the fetch.
    struct Entry: Codable, Sendable {
        let fetchedAt: Date
        let items: [LibraryItem]

        func isFresh(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(fetchedAt) < ttl
        }
    }

    enum Section: String {
        case recentlyPlayed
        case recommendations

        fileprivate var defaultsKey: String {
            switch self {
            case .recentlyPlayed:  "library.recentlyPlayed.v1"
            case .recommendations: "library.recommendations.v1"
            }
        }
    }

    /// Default TTL per the PM's 30-minute call.
    static let ttl: TimeInterval = 30 * 60

    static func load(_ section: Section) -> Entry? {
        guard let data = UserDefaults.standard.data(forKey: section.defaultsKey),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return entry
    }

    static func save(_ items: [LibraryItem], for section: Section) {
        let entry = Entry(fetchedAt: Date(), items: items)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: section.defaultsKey)
    }

    static func clear(_ section: Section) {
        UserDefaults.standard.removeObject(forKey: section.defaultsKey)
    }
}
