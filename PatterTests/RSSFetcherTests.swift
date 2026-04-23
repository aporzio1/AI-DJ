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
