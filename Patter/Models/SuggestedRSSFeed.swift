import Foundation

/// A curated RSS feed surfaced in onboarding and Settings as a one-tap add.
/// Identity is derived from the URL so the same entry produces a stable id
/// across both screens and across launches (a regenerated UUID would break
/// SwiftUI diffing inside ForEach).
struct SuggestedRSSFeed: Identifiable, Hashable, Sendable {
    let name: String
    let url: String
    var id: String { url }
}

enum SuggestedRSSFeeds {
    static let all: [SuggestedRSSFeed] = [
        .init(name: "NPR Top Stories", url: "https://feeds.npr.org/1001/rss.xml"),
        .init(name: "Hacker News", url: "https://hnrss.org/newest"),
        .init(name: "BBC Top Stories", url: "https://feeds.bbci.co.uk/news/rss.xml"),
        .init(name: "BBC World News", url: "https://feeds.bbci.co.uk/news/world/rss.xml"),
        .init(name: "BBC Technology", url: "https://feeds.bbci.co.uk/news/technology/rss.xml"),
        .init(name: "BBC Business", url: "https://feeds.bbci.co.uk/news/business/rss.xml"),
        .init(name: "CBS Top Stories", url: "https://www.cbsnews.com/latest/rss/main"),
        .init(name: "CBS World", url: "https://www.cbsnews.com/latest/rss/world"),
        .init(name: "CBS Technology", url: "https://www.cbsnews.com/latest/rss/technology"),
        .init(name: "The Guardian", url: "https://www.theguardian.com/rss"),
        .init(name: "Guardian World", url: "https://www.theguardian.com/world/rss"),
        .init(name: "Guardian Technology", url: "https://www.theguardian.com/technology/rss"),
        .init(name: "WIRED Top Stories", url: "https://www.wired.com/feed/rss"),
        .init(name: "WIRED AI", url: "https://www.wired.com/feed/tag/ai/latest/rss"),
        .init(name: "WIRED Security", url: "https://www.wired.com/feed/category/security/latest/rss"),
        .init(name: "TechCrunch", url: "https://techcrunch.com/feed/"),
        .init(name: "BleepingComputer", url: "https://www.bleepingcomputer.com/feed/"),
        .init(name: "Le Monde World", url: "https://www.lemonde.fr/en/international/rss_full.xml")
    ]
}
