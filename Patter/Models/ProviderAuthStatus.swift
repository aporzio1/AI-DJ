import Foundation

/// Provider-neutral authorization status. Apple Music maps its own
/// `MusicAuthorization.Status` into the first three cases; `.needsReauth`
/// is reserved for a future token-based provider whose credentials can
/// expire mid-session.
enum ProviderAuthStatus: Sendable, Equatable {
    case unknown
    case notAuthorized
    case authorized
    case needsReauth
}
