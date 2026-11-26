import Foundation

struct Track: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let duration: TimeInterval
    let providerID: MusicProviderID
    /// Genre families from the provider ("Pop", "Hip-Hop/Rap", …). Empty for
    /// legacy payloads and anything the provider didn't tag; the flow reader
    /// degrades to shape heuristics when it's missing.
    let genreNames: [String]
    /// Release year when the provider exposed a release date.
    let releaseYear: Int?

    init(id: String, title: String, artist: String, album: String,
         artworkURL: URL?, duration: TimeInterval, providerID: MusicProviderID,
         genreNames: [String] = [], releaseYear: Int? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.providerID = providerID
        self.genreNames = genreNames
        self.releaseYear = releaseYear
    }

    enum MusicProviderID: String, Codable, Sendable {
        case appleMusic
    }
}
