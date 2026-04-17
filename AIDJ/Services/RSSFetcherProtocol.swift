import Foundation

protocol RSSFetcherProtocol: AnyObject, Sendable {
    /// Fetches all configured feeds and returns deduplicated headlines, newest-first.
    func fetchHeadlines() async throws -> [NewsHeadline]
}
