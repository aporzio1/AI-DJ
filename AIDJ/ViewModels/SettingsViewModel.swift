import Foundation

@Observable
@MainActor
final class SettingsViewModel {

    var persona: DJPersona = .default
    var djEnabled: Bool = true
    var newsEnabled: Bool = true
    var feedURLStrings: [String] = []
    var listenerName: String = ""

    private static let feedsKey = "rssFeedURLs"
    private static let djEnabledKey = "djEnabled"
    private static let newsEnabledKey = "newsEnabled"
    private static let listenerNameKey = "listenerName"

    init() {
        loadFromUserDefaults()
    }

    // MARK: RSS Feed management

    func addFeed(urlString: String) {
        guard !urlString.isEmpty, URL(string: urlString) != nil else { return }
        guard !feedURLStrings.contains(urlString) else { return }
        feedURLStrings.append(urlString)
        saveToUserDefaults()
    }

    func removeFeed(at offsets: IndexSet) {
        feedURLStrings.remove(atOffsets: offsets)
        saveToUserDefaults()
    }

    func importOPML(data: Data) {
        let urls = OPMLParser.parse(data: data)
        for url in urls where !feedURLStrings.contains(url) {
            feedURLStrings.append(url)
        }
        saveToUserDefaults()
    }

    var feedURLs: [URL] {
        feedURLStrings.compactMap { URL(string: $0) }
    }

    // MARK: Persistence

    func save() {
        saveToUserDefaults()
    }

    private func saveToUserDefaults() {
        UserDefaults.standard.set(feedURLStrings, forKey: Self.feedsKey)
        UserDefaults.standard.set(djEnabled, forKey: Self.djEnabledKey)
        UserDefaults.standard.set(newsEnabled, forKey: Self.newsEnabledKey)
        UserDefaults.standard.set(listenerName, forKey: Self.listenerNameKey)
    }

    private func loadFromUserDefaults() {
        feedURLStrings = UserDefaults.standard.stringArray(forKey: Self.feedsKey) ?? []
        djEnabled = UserDefaults.standard.object(forKey: Self.djEnabledKey) as? Bool ?? true
        newsEnabled = UserDefaults.standard.object(forKey: Self.newsEnabledKey) as? Bool ?? true
        if let stored = UserDefaults.standard.string(forKey: Self.listenerNameKey), !stored.isEmpty {
            listenerName = stored
        } else {
            listenerName = defaultSystemName()
        }
    }

    private func defaultSystemName() -> String {
        let full = NSFullUserName()
        return full.components(separatedBy: .whitespaces).first ?? full
    }
}

// MARK: - OPML Parser

private struct OPMLParser {
    static func parse(data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var urls: [String] = []
        // Simple regex-free extraction: find xmlUrl attributes
        let lines = xml.components(separatedBy: .newlines)
        for line in lines {
            if let range = line.range(of: "xmlUrl=\"") {
                let after = line[range.upperBound...]
                if let endRange = after.range(of: "\"") {
                    urls.append(String(after[after.startIndex..<endRange.lowerBound]))
                }
            }
        }
        return urls
    }
}
