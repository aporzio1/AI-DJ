// PatterTests/ArticleFetcherTests.swift
import Testing
import Foundation
@testable import Patter

@Suite("ArticleFetcher")
struct ArticleFetcherTests {

    private let cleanArticle = """
    <html><head><title>T</title><style>p{color:red}</style></head><body>
    <nav><p>Home News Sports Weather Subscribe Login</p></nav>
    <article>
    <p>The first paragraph of the story explains what happened in enough detail to be useful.</p>
    <p>The second paragraph adds who was involved and quotes an official on why it matters going forward.</p>
    <p>The third paragraph gives background context about prior events leading up to this development.</p>
    </article>
    <footer><p>Copyright 2026. All rights reserved. Privacy. Terms.</p></footer>
    <script>var x = "<p>not content</p>";</script>
    </body></html>
    """

    @Test func extractsParagraphsAndDropsChrome() {
        let body = ArticleFetcher.extractBody(html: cleanArticle, maxChars: 4000)
        #expect(body != nil)
        let text = body ?? ""
        #expect(text.contains("first paragraph of the story"))
        #expect(text.contains("prior events"))
        #expect(!text.contains("Subscribe"))
        #expect(!text.contains("var x"))
        #expect(!text.contains("<p>"))
    }

    /// Chrome blocks whose opening tag, content, and closing tag each sit on
    /// their own line — regression for the dot-matches-newline bug where
    /// `.replacingOccurrences(options: .regularExpression)` never enabled
    /// `(?s)`, so multi-line <nav>/<footer>/<script> blocks passed through
    /// untouched and leaked boilerplate into the extracted body.
    private let multiLineChromeArticle = """
    <html>
    <head>
    <title>T</title>
    </head>
    <body>
    <nav>
    <ul>
    <li>Home</li>
    <li>News</li>
    </ul>
    <p>Subscribe Login</p>
    </nav>
    <article>
    <p>The first paragraph of the story explains what happened in enough detail to be useful.</p>
    <p>The second paragraph adds who was involved and quotes an official on why it matters going forward.</p>
    <p>The third paragraph gives background context about prior events leading up to this development.</p>
    </article>
    <footer>
    <p>Copyright 2026.</p>
    <p>All rights reserved.</p>
    </footer>
    <script>
    var x = "<p>not content</p>";
    console.log(x);
    </script>
    </body>
    </html>
    """

    @Test func stripsMultiLineChromeBlocks() {
        let body = ArticleFetcher.extractBody(html: multiLineChromeArticle, maxChars: 4000)
        #expect(body != nil)
        let text = body ?? ""
        #expect(text.contains("first paragraph of the story"))
        #expect(text.contains("prior events"))
        #expect(!text.contains("Subscribe"))
        #expect(!text.contains("Home"))
        #expect(!text.contains("Copyright"))
        #expect(!text.contains("console.log"))
        #expect(!text.contains("var x"))
    }

    @Test func truncatesAtWordBoundaryToMaxChars() {
        let body = ArticleFetcher.extractBody(html: cleanArticle, maxChars: 120)
        let text = body ?? ""
        #expect(text.count <= 120)
        #expect(!text.hasSuffix(" "))       // clean word boundary
        #expect(text.contains("first paragraph"))
    }

    @Test func junkPageReturnsNil() {
        let junk = "<html><body><div>OK</div><p>Loading…</p></body></html>"
        #expect(ArticleFetcher.extractBody(html: junk, maxChars: 4000) == nil)
    }

    @Test func fetchFailureReturnsNil() async {
        let fetcher = ArticleFetcher(dataLoader: { _ in
            throw URLError(.timedOut)
        })
        let body = await fetcher.body(for: URL(string: "https://example.com/a")!, maxChars: 1500)
        #expect(body == nil)
    }

    @Test func non200ReturnsNil() async {
        let fetcher = ArticleFetcher(dataLoader: { url in
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (Data("<html><p>Not found page body text that is fairly long anyway</p></html>".utf8), resp)
        })
        let body = await fetcher.body(for: URL(string: "https://example.com/a")!, maxChars: 1500)
        #expect(body == nil)
    }

    @Test func successfulFetchExtracts() async {
        let html = cleanArticle
        let fetcher = ArticleFetcher(dataLoader: { url in
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            return (Data(html.utf8), resp)
        })
        let body = await fetcher.body(for: URL(string: "https://example.com/a")!, maxChars: 1500)
        #expect(body?.contains("first paragraph of the story") == true)
    }
}
