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

        fileprivate var baseKey: String {
            switch self {
            case .recentlyPlayed:  "library.recentlyPlayed.v2"
            case .recommendations: "library.recommendations.v2"
            }
        }

        /// v2 key namespaces the cache by provider. v1 keys (pre-provider
        /// abstraction) were shared; namespacing prevents bleed when a
        /// future second provider is added without re-migrating callers.
        fileprivate func defaultsKey(for providerID: Track.MusicProviderID) -> String {
            "\(baseKey).\(providerID.rawValue)"
        }
    }

    /// Default TTL per the PM's 30-minute call.
    static let ttl: TimeInterval = 30 * 60

    static func load(_ section: Section, provider: Track.MusicProviderID) -> Entry? {
        guard let data = UserDefaults.standard.data(forKey: section.defaultsKey(for: provider)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return entry
    }

    static func save(_ items: [LibraryItem], for section: Section, provider: Track.MusicProviderID) {
        let entry = Entry(fetchedAt: Date(), items: items)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: section.defaultsKey(for: provider))
    }

    static func clear(_ section: Section, provider: Track.MusicProviderID) {
        UserDefaults.standard.removeObject(forKey: section.defaultsKey(for: provider))
    }
}
