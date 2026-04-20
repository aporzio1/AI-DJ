import Foundation

protocol RSSFetcherProtocol: AnyObject, Sendable {
    /// Fetches all configured feeds and returns deduplicated headlines, newest-first.
    func fetchHeadlines() async throws -> [NewsHeadline]

    /// Hot-swap the feed list. Lets Settings edits propagate to a running
    /// Producer without tearing down the fetcher.
    func updateFeeds(_ urls: [URL])
}
