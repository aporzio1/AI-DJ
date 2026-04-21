import Foundation

/// Provider-neutral authorization status. MusicKit maps its own
/// `MusicAuthorization.Status` into these cases; Spotify's PKCE flow
/// surfaces the full set including `.needsReauth` when a token refresh
/// returns 400/401.
enum ProviderAuthStatus: Sendable, Equatable {
    case unknown
    case notAuthorized
    case authorized
    case needsReauth
}
