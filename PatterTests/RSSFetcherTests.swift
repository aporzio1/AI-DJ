import Testing
import Foundation
@testable import Patter

@Suite("RSSFetcher parser")
struct RSSFetcherTests {

    // MARK: RSS 2.0

    @Test func parsesRSS20ItemsCorrectly() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Test Feed</title>
            <item>
              <title>First headline</title>
              <link>https://example.com/1</link>
              <pubDate>Thu, 17 Apr 2026 09:00:00 +0000</pubDate>
              <description>Summary of first headline.</description>
            </item>
            <item>
              <title>Second headline</title>
              <link>https://example.com/2</link>
              <pubDate>Wed, 16 Apr 2026 12:00:00 +0000</pubDate>
              <description>Summary of second headline.</description>
            </item>
          </channel>
        </rss>
        """.data(using: .utf8)!

        let fetcher = RSSFetcher(feedURLs: [], session: .shared)
        let headlines = try fetcher.parseForTesting(data: xml, source: "example.com")

        #expect(headlines.count == 2)
        #expect(headlines[0].title == "First headline")
        #expect(headlines[0].url == URL(string: "https://example.com/1")!)
        #expect(headlines[0].summary == "Summary of first headline.")
        #expect(headlines[1].title == "Second headline")
    }

    @Test func parsesAtomFeedCorrectly() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Test</title>
          <entry>
            <title>Atom entry one</title>
            <link href="https://atom.example.com/1"/>
            <updated>2026-04-17T09:00:00Z</updated>
            <summary>Atom summary one.</summary>
          </entry>
          <entry>
            <title>Atom entry two</title>
            <link href="https://atom.example.com/2"/>
            <updated>2026-04-16T12:00:00Z</updated>
            <summary>Atom summary two.</summary>
          </entry>
        </feed>
        """.data(using: .utf8)!

        let fetcher = RSSFetcher(feedURLs: [], session: .shared)
        let headlines = try fetcher.parseForTesting(data: xml, source: "atom.example.com")

        #expect(headlines.count == 2)
        #expect(headlines[0].title == "Atom entry one")
        #expect(headlines[0].url == URL(string: "https://atom.example.com/1")!)
        #expect(headlines[0].summary == "Atom summary one.")
    }

    @Test func deduplicatesByURL() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>Duplicate</title>
              <link>https://example.com/dup</link>
              <pubDate>Thu, 17 Apr 2026 09:00:00 +0000</pubDate>
            </item>
            <item>
              <title>Duplicate again</title>
              <link>https://example.com/dup</link>
              <pubDate>Thu, 17 Apr 2026 08:00:00 +0000</pubDate>
            </item>
            <item>
              <title>Unique</title>
              <link>https://example.com/unique</link>
              <pubDate>Thu, 17 Apr 2026 07:00:00 +0000</pubDate>
            </item>
          </channel>
        </rss>
        """.data(using: .utf8)!

        let fetcher = RSSFetcher(feedURLs: [], session: .shared)
        let headlines = try fetcher.parseForTesting(data: xml, source: "example.com")
        // Both dup URLs hit the feed, but dedup should be done at the fetcher level
        // (parser itself returns both; fetchHeadlines() dedupes across feeds)
        #expect(headlines.count == 3) // parser returns all; fetchHeadlines() dedupes
    }

    @Test func skipsItemsWithMissingURL() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>No link item</title>
              <pubDate>Thu, 17 Apr 2026 09:00:00 +0000</pubDate>
            </item>
            <item>
              <title>Has link</title>
              <link>https://example.com/valid</link>
              <pubDate>Thu, 17 Apr 2026 08:00:00 +0000</pubDate>
            </item>
          </channel>
        </rss>
        """.data(using: .utf8)!

        let fetcher = RSSFetcher(feedURLs: [], session: .shared)
        let headlines = try fetcher.parseForTesting(data: xml, source: "example.com")
        #expect(headlines.count == 1)
        #expect(headlines[0].title == "Has link")
    }

    @Test func capsAtMaxPerFeed() throws {
        let items = (1...25).map { i in
            "<item><title>Item \(i)</title><link>https://example.com/\(i)</link><pubDate>Thu, 17 Apr 2026 09:00:00 +0000</pubDate></item>"
        }.joined()
        let xml = """
        <?xml version="1.0"?><rss version="2.0"><channel>\(items)</channel></rss>
        """.data(using: .utf8)!

        let fetcher = RSSFetcher(feedURLs: [], session: .shared)
        let headlines = try fetcher.parseForTesting(data: xml, source: "example.com")
        #expect(headlines.count == 20)
    }
}

// MARK: - RSSFetcher network (multi-feed merge, concurrency, HTTP status)

/// `.serialized` because `MockURLProtocol.responses` is shared mutable
/// state keyed by URL — parallel test execution across this suite would
/// let one test's response map leak into another's fetch.
@Suite("RSSFetcher network", .serialized)
struct RSSFetcherNetworkTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func rssXML(items: [(title: String, link: String, pubDate: String)]) -> Data {
        let itemsXML = items.map {
            "<item><title>\($0.title)</title><link>\($0.link)</link><pubDate>\($0.pubDate)</pubDate></item>"
        }.joined()
        return "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel>\(itemsXML)</channel></rss>".data(using: .utf8)!
    }

    @Test func mergesAndSortsAcrossFeeds() async throws {
        let feed1 = URL(string: "https://feed1.example.com/rss")!
        let feed2 = URL(string: "https://feed2.example.com/rss")!
        MockURLProtocol.responses = [
            feed1: .success(rssXML(items: [("Older", "https://a.example.com/1", "Thu, 17 Apr 2026 08:00:00 +0000")])),
            feed2: .success(rssXML(items: [("Newer", "https://b.example.com/1", "Thu, 17 Apr 2026 09:00:00 +0000")])),
        ]

        let fetcher = RSSFetcher(feedURLs: [feed1, feed2], session: makeSession())
        let headlines = try await fetcher.fetchHeadlines()

        #expect(headlines.count == 2)
        #expect(headlines.first?.title == "Newer")
        #expect(headlines.last?.title == "Older")
    }

    @Test func deduplicatesSameURLAcrossFeeds() async throws {
        let feed1 = URL(string: "https://feed1.example.com/rss")!
        let feed2 = URL(string: "https://feed2.example.com/rss")!
        let sharedLink = "https://shared.example.com/story"
        MockURLProtocol.responses = [
            feed1: .success(rssXML(items: [("Copy A", sharedLink, "Thu, 17 Apr 2026 08:00:00 +0000")])),
            feed2: .success(rssXML(items: [("Copy B", sharedLink, "Thu, 17 Apr 2026 09:00:00 +0000")])),
        ]

        let fetcher = RSSFetcher(feedURLs: [feed1, feed2], session: makeSession())
        let headlines = try await fetcher.fetchHeadlines()

        // Which copy wins is not deterministic under concurrent fetch — only
        // assert the shared URL collapsed to a single entry.
        #expect(headlines.count == 1)
    }

    @Test func nonSuccessStatusFailsSoftPerFeed() async throws {
        let badFeed = URL(string: "https://down.example.com/rss")!
        let goodFeed = URL(string: "https://up.example.com/rss")!
        MockURLProtocol.responses = [
            badFeed: .failure(statusCode: 500),
            goodFeed: .success(rssXML(items: [("Still works", "https://up.example.com/1", "Thu, 17 Apr 2026 09:00:00 +0000")])),
        ]

        let fetcher = RSSFetcher(feedURLs: [badFeed, goodFeed], session: makeSession())
        let headlines = try await fetcher.fetchHeadlines()

        #expect(headlines.count == 1)
        #expect(headlines.first?.title == "Still works")
    }

    @Test func allFeedsFailingReturnsEmptyNotThrow() async throws {
        let feed = URL(string: "https://down.example.com/rss")!
        MockURLProtocol.responses = [feed: .failure(statusCode: 503)]

        let fetcher = RSSFetcher(feedURLs: [feed], session: makeSession())
        let headlines = try await fetcher.fetchHeadlines()

        #expect(headlines.isEmpty)
    }
}

// MARK: - MockURLProtocol

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response {
        case success(Data)
        case failure(statusCode: Int)
    }

    nonisolated(unsafe) static var responses: [URL: Response] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let statusCode: Int
        let data: Data
        switch response {
        case .success(let responseData):
            statusCode = 200
            data = responseData
        case .failure(let code):
            statusCode = code
            data = Data()
        }
        let httpResponse = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
