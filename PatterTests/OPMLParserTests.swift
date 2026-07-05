import Testing
import Foundation
@testable import Patter

@Suite("OPMLParser")
struct OPMLParserTests {

    @Test func parseExtractsSingleOutlineURL() {
        let xml = """
        <?xml version="1.0"?>
        <opml version="1.0"><body>
        <outline xmlUrl="https://example.com/feed.xml" />
        </body></opml>
        """.data(using: .utf8)!
        #expect(OPMLParser.parse(data: xml) == ["https://example.com/feed.xml"])
    }

    /// The line-scan implementation this replaced only checked one
    /// `xmlUrl="..."` per line — a real OPML export can put several
    /// `<outline>` elements on a single line.
    @Test func parseHandlesMultipleOutlinesOnOneLine() {
        let xml = """
        <?xml version="1.0"?>
        <opml version="1.0"><body><outline xmlUrl="https://a.example.com/feed.xml" /><outline xmlUrl="https://b.example.com/feed.xml" /></body></opml>
        """.data(using: .utf8)!
        #expect(OPMLParser.parse(data: xml) == ["https://a.example.com/feed.xml", "https://b.example.com/feed.xml"])
    }

    /// The line-scan looked for a literal `"` delimiter, so single-quoted
    /// XML attributes (valid XML, some exporters use them) were missed entirely.
    @Test func parseHandlesSingleQuotedAttributes() {
        let xml = """
        <?xml version="1.0"?>
        <opml version="1.0"><body><outline xmlUrl='https://example.com/feed.xml' /></body></opml>
        """.data(using: .utf8)!
        #expect(OPMLParser.parse(data: xml) == ["https://example.com/feed.xml"])
    }

    @Test func parseIgnoresOutlinesWithoutXmlUrl() {
        let xml = """
        <?xml version="1.0"?>
        <opml version="1.0"><body><outline title="folder"><outline xmlUrl="https://example.com/feed.xml" /></outline></body></opml>
        """.data(using: .utf8)!
        #expect(OPMLParser.parse(data: xml) == ["https://example.com/feed.xml"])
    }

    @Test func parseOfMalformedDataReturnsEmpty() {
        let garbage = Data("not xml at all".utf8)
        #expect(OPMLParser.parse(data: garbage) == [])
    }

    // MARK: - isValidFeedURL

    @Test func isValidFeedURLAcceptsSchemeAndHost() {
        #expect(OPMLParser.isValidFeedURL("https://example.com/feed.xml"))
    }

    @Test func isValidFeedURLRejectsEmptyString() {
        #expect(!OPMLParser.isValidFeedURL(""))
    }

    @Test func isValidFeedURLRejectsMissingScheme() {
        #expect(!OPMLParser.isValidFeedURL("example.com/feed.xml"))
    }
}
