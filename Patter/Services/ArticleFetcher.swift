// Patter/Services/ArticleFetcher.swift
import Foundation

/// Heuristic full-article text extraction for the Detailed/Deep Dive news
/// verbosity levels. Plain-Swift tag stripping (no WebKit, no third-party
/// readability dep): drop script/style/nav/header/footer/aside blocks,
/// collect <p> runs, keep the result only if it looks like real prose.
struct ArticleFetcher: ArticleFetching {

    /// Injectable network layer so tests never touch the real network.
    private let dataLoader: @Sendable (URL) async throws -> (Data, URLResponse)

    init(dataLoader: (@Sendable (URL) async throws -> (Data, URLResponse))? = nil) {
        if let dataLoader {
            self.dataLoader = dataLoader
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 6
            let session = URLSession(configuration: config)
            self.dataLoader = { url in try await session.data(from: url) }
        }
    }

    func body(for url: URL, maxChars: Int) async -> String? {
        do {
            let (data, response) = try await dataLoader(url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                Log.producer.info("ArticleFetcher: HTTP \(http.statusCode) for \(url.host ?? "?", privacy: .public) — falling back to summary")
                return nil
            }
            guard let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else { return nil }
            let extracted = Self.extractBody(html: html, maxChars: maxChars)
            if extracted == nil {
                Log.producer.info("ArticleFetcher: extraction produced no usable text for \(url.host ?? "?", privacy: .public)")
            }
            return extracted
        } catch {
            Log.producer.info("ArticleFetcher: fetch failed (\(error, privacy: .public)) — falling back to summary")
            return nil
        }
    }

    /// Minimum extracted length before we trust the result — anything
    /// shorter is boilerplate/consent-wall junk, not an article.
    private static let minUsableChars = 200

    static func extractBody(html: String, maxChars: Int) -> String? {
        var work = html
        // Drop whole non-content blocks (case-insensitive, dot matches newlines).
        for tag in ["script", "style", "nav", "header", "footer", "aside", "noscript", "form", "svg"] {
            work = work.replacingOccurrences(
                of: "(?s)<\(tag)\\b[^>]*>.*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Collect <p>…</p> contents in document order.
        var paragraphs: [String] = []
        let pattern = "<p\\b[^>]*>(.*?)</p>"
        if let regex = try? NSRegularExpression(pattern: pattern,
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let ns = work as NSString
            for match in regex.matches(in: work, range: NSRange(location: 0, length: ns.length)) {
                let inner = ns.substring(with: match.range(at: 1))
                let text = stripTagsAndEntities(inner)
                // Skip obvious chrome: very short fragments rarely carry story text.
                if text.count >= 60 { paragraphs.append(text) }
            }
        }
        let joined = paragraphs.joined(separator: " ")
        guard joined.count >= minUsableChars else { return nil }
        return truncateAtWordBoundary(joined, maxChars: maxChars)
    }

    private static func stripTagsAndEntities(_ s: String) -> String {
        var result = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " "), ("&ndash;", "–"),
            ("&mdash;", "—"), ("&hellip;", "…"), ("&rsquo;", "'"), ("&lsquo;", "'"),
            ("&rdquo;", "\""), ("&ldquo;", "\""),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncateAtWordBoundary(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let prefix = String(text.prefix(maxChars))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        }
        return prefix
    }
}
