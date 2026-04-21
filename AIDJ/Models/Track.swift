import Foundation

struct Track: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let duration: TimeInterval
    let providerID: MusicProviderID

    enum MusicProviderID: String, Codable, Sendable {
        case appleMusic
        case spotify
    }
}
