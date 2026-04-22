import Foundation
@preconcurrency import MusicKit

/// Provider-neutral artwork reference. MusicKit gives us a rich `Artwork`
/// value that resolves custom `musicKit://` URLs; a future URL-based
/// provider would give us a plain HTTPS URL. This enum lets a single
/// SwiftUI view render either without leaking MusicKit types into call
/// sites.
enum ProviderArtwork: Sendable {
    case musicKit(Artwork)
    case url(URL)
}
