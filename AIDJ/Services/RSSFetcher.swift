import Foundation

final class RSSFetcher: RSSFetcherProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _feedURLs: [URL]
    private let session: URLSession
    private let maxHeadlinesPerFeed = 20

    init(feedURLs: [URL], session: URLSession = .shared) {
        self._feedURLs = feedURLs
        self.session = session
    }

    func updateFeeds(_ urls: [URL]) {
        lock.lock()
        _feedURLs = urls
        lock.unlock()
        Log.producer.info("RSSFetcher: feed list updated (\(urls.count) feeds)")
    }

    private var currentFeeds: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _feedURLs
    }

    func fetchHeadlines() async throws -> [NewsHeadline] {
        var all: [NewsHeadline] = []
        for url in currentFeeds {
            do {
                let headlines = try await fetch(url)
                all.append(contentsOf: headlines)
            } catch {
                Log.producer.error("RSSFetcher: \(url.host ?? url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Dedupe by URL string, then sort newest-first
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.url.absoluteString).inserted }
        return unique.sorted { $0.publishedAt > $1.publishedAt }
    }

    private func fetch(_ url: URL) async throws -> [NewsHeadline] {
        let (data, _) = try await session.data(from: url)
        return try parse(data: data, source: url.host ?? url.absoluteString)
    }

    private func parse(data: Data, source: String) throws -> [NewsHeadline] {
        let parser = FeedParser(data: data, source: source, max: maxHeadlinesPerFeed)
        return try parser.parse()
    }

    /// Exposed for unit tests only — parses a raw feed without making network calls.
    func parseForTesting(data: Data, source: String) throws -> [NewsHeadline] {
        try parse(data: data, source: source)
    }
}

// MARK: - Feed parser (RSS 2.0 + Atom)

private final class FeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let source: String
    private let max: Int

    private var results: [NewsHeadline] = []
    private var currentElement = ""
    private var buffer = ""

    // RSS 2.0 item state
    private var inItem = false
    private var itemTitle = ""
    private var itemLink = ""
    private var itemPubDate = ""
    private var itemDescription = ""

    // Atom entry state
    private var inEntry = false
    private var entryTitle = ""
    private var entryLink = ""
    private var entryUpdated = ""
    private var entrySummary = ""

    private var parseError: Error?

    init(data: Data, source: String, max: Int) {
        self.data = data
        self.source = source
        self.max = max
    }

    func parse() throws -> [NewsHeadline] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        if let error = parseError { throw error }
        return Array(results.prefix(max))
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        buffer = ""
        switch elementName {
        case "item":
            inItem = true
            itemTitle = ""; itemLink = ""; itemPubDate = ""; itemDescription = ""
        case "entry":
            inEntry = true
            entryTitle = ""; entryLink = ""; entryUpdated = ""; entrySummary = ""
        case "link" where inEntry:
            if let href = attributeDict["href"], !href.isEmpty {
                entryLink = href
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch elementName {
            case "title":       itemTitle = text
            case "link":        if !text.isEmpty { itemLink = text }
            case "pubDate":     itemPubDate = text
            case "description": itemDescription = text
            case "item":
                if let headline = makeRSSHeadline() {
                    results.append(headline)
                }
                inItem = false
            default: break
            }
        } else if inEntry {
            switch elementName {
            case "title":   entryTitle = text
            case "updated": entryUpdated = text
            case "summary": entrySummary = text
            case "entry":
                if let headline = makeAtomHeadline() {
                    results.append(headline)
                }
                inEntry = false
            default: break
            }
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: Helpers

    private func makeRSSHeadline() -> NewsHeadline? {
        guard !itemTitle.isEmpty, let url = URL(string: itemLink) else { return nil }
        let date = parseDate(itemPubDate)
        return NewsHeadline(
            id: UUID(),
            title: itemTitle,
            source: source,
            url: url,
            publishedAt: date,
            summary: itemDescription
        )
    }

    private func makeAtomHeadline() -> NewsHeadline? {
        guard !entryTitle.isEmpty, let url = URL(string: entryLink) else { return nil }
        let date = parseDate(entryUpdated)
        return NewsHeadline(
            id: UUID(),
            title: entryTitle,
            source: source,
            url: url,
            publishedAt: date,
            summary: entrySummary
        )
    }

    private func parseDate(_ string: String) -> Date {
        // RFC 2822 (RSS pubDate)
        let rfc2822 = DateFormatter()
        rfc2822.locale = Locale(identifier: "en_US_POSIX")
        rfc2822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let d = rfc2822.date(from: string) { return d }

        // ISO 8601 (Atom updated)
        if let d = ISO8601DateFormatter().date(from: string) { return d }

        return Date()
    }
}
