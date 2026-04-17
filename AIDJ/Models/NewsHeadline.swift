import Foundation

struct NewsHeadline: Identifiable, Codable, Sendable {
    let id: UUID
    let title: String
    let source: String
    let url: URL
    let publishedAt: Date
    let summary: String
}
