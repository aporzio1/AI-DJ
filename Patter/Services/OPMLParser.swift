import Foundation

/// Parses OPML feed-subscription lists and validates feed URL strings. Feed
/// URL validation lives here (not just in the view/view-model that use it)
/// because both need the *same* rule, and OPML import is the other place
/// a URL string enters the app.
enum OPMLParser {
    /// Extracts every `xmlUrl` attribute from `<outline>` elements. A real
    /// XML parser (vs. the line-scan this replaced) correctly handles
    /// multiple outlines on one line and single-quoted attributes.
    static func parse(data: Data) -> [String] {
        let delegate = OutlineURLCollector()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.urls
    }

    /// Shared feed-URL validity check. Requires a non-empty string that
    /// parses as a URL *with* a scheme — a bare host/path like "example.com"
    /// isn't accepted, since `RSSFetcher` needs an absolute URL to fetch.
    static func isValidFeedURL(_ string: String) -> Bool {
        guard !string.isEmpty, let url = URL(string: string), url.scheme != nil else { return false }
        return true
    }
}

private final class OutlineURLCollector: NSObject, XMLParserDelegate {
    private(set) var urls: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "outline",
              let xmlUrl = attributeDict["xmlUrl"],
              !xmlUrl.isEmpty else { return }
        urls.append(xmlUrl)
    }
}
