# Implementation Plan — Spotify Support for AI DJ

**Date:** 2026-04-20
**Status:** Proposed
**Author:** Andrew P (with Claude Code)
**Supersedes:** "No Spotify" exclusion in `CLAUDE.md` and `docs/superpowers/specs/2026-04-17-ai-dj-design.md`

## 1. Summary

Add a second music provider (Spotify) alongside the existing Apple Music integration. Do it in small, independently shippable phases. Phase 1 is a pure refactor that keeps Apple Music behavior identical; later phases layer on Spotify read access, then Spotify playback, then a macOS story.

Key recommendation up front: **iOS-only Spotify playback for the first release. macOS stays Apple-Music-only until Phase 4.** The iOS SDK is the only reasonable path on iOS; there is no first-party Spotify SDK for macOS, and the Web Playback SDK inside a WKWebView is a real but separate project with its own risks (Premium required, Widevine DRM through WebKit, no background playback).

## 2. Spotify SDK Choice — Options and Recommendation

Three technically-real paths, per Spotify's 2026 developer docs:

### 2a. Spotify iOS SDK (SPTAppRemote + SPTSessionManager) — iOS only
- **What it is.** Native framework. Your app doesn't play Spotify audio — the Spotify app does, and SPTAppRemote is essentially an RPC channel that tells it what to play. Metadata (title, artist, artwork, position) is streamed back.
- **Distribution.** Available via Swift Package Manager *or* `SpotifyiOS.xcframework`. For this repo, add via SPM in `project.yml` → `packages:` — consistent with how FluidAudio is already wired.
- **Hard requirements.** Spotify app installed on-device, user signed in, **Spotify Premium**. Not optional; this is a user-visible onboarding gate.
- **Simulator.** Does not work — SPTAppRemote connects to the Spotify app, which isn't installable in the iOS simulator. Development requires a physical iPhone. (Matches the existing "Apple Intelligence needs a real device" constraint, so not a new burden.)
- **Auth.** Works via Spotify app's own token vending (user taps through a Spotify-app consent screen), or via SPTSessionManager's PKCE flow that falls back to the web when the Spotify app is missing. We'll use SPTSessionManager with PKCE.
- **Audio.** Spotify owns its audio session. We cannot receive raw audio buffers and cannot mix our DJ voice into their stream. See §5.

### 2b. Spotify Web API + Web Playback SDK in a WKWebView — macOS path
- **What it is.** Use Spotify's Web API (plain REST + JSON over URLSession) for library, search, and metadata. Use the **Web Playback SDK** (a JavaScript player that runs inside a browser) for actual playback, hosted in a `WKWebView`.
- **Hard requirements.** Premium account. Browser DRM (Widevine on non-Safari; FairPlay on Safari/WebKit). WebKit *does* support EME, but confirming it works under WKWebView on macOS 26 with our entitlements is a Phase 4 de-risking task, not a given.
- **Why not iOS too.** On iOS the Web Playback SDK is officially supported in mobile browsers, but WKWebView embedding has historically had audio/DRM quirks, and the native iOS SDK is strictly better where it works. Use the native SDK on iOS.
- **Alternative.** Web API-only, no Web Playback SDK — lets you browse Spotify and trigger playback on *another* Spotify Connect device, but can't play Spotify *on the Mac* without such a device. Not useful for this app.

### 2c. AppleScript bridge to the macOS Spotify.app
- **What it is.** Tell the Spotify desktop app what to play via NSAppleScript / ScriptingBridge.
- **Why we're not using it.** Spotify has deprecated their scripting dictionary and future Spotify desktop builds may drop it entirely; it also requires the user to have the full Spotify desktop app open and in-foreground-enough to respond. Too brittle to ship against.

### Recommendation
- **Phase 1–3:** iOS Spotify SDK (native, PKCE via SPTSessionManager).
- **Phase 4 (separate decision):** Web Playback SDK in WKWebView for macOS — or explicit "Spotify is iOS-only in this app" if the DRM/WebView spike fails.
- On macOS through Phase 3, the provider picker in onboarding shows Apple Music only; Spotify is hidden or shown disabled with a "Spotify is iOS-only for now" explanation.

## 3. Auth — OAuth 2.0 PKCE, Keychain, Redirect URIs

Spotify recommends Authorization Code with PKCE for native apps. The iOS SDK's `SPTSessionManager` implements it — we don't need to roll our own crypto.

### 3a. Spotify Developer app setup (one-time, manual)
- Create an app at developer.spotify.com. Register redirect URI `aidj://spotify-callback` (a custom URL scheme; matches the pattern the iOS SDK docs recommend).
- Capture the Client ID. **Client ID is not a secret** — it can live in the app binary (checked into the repo or loaded from an xcconfig). Client *secret* must not ship in the app; PKCE replaces the need for it.
- Add a second redirect URI for dev: `aidj-dev://spotify-callback` so TestFlight/dev builds don't collide with production.

### 3b. Info.plist and entitlements changes
- `AIDJ/Resources/Info.plist`:
  - Add `CFBundleURLTypes` with a `CFBundleURLSchemes` entry for `aidj`.
  - Add `LSApplicationQueriesSchemes` with `spotify` (required so the SDK can `canOpenURL` to detect the Spotify app).
- `AIDJ/Resources/AIDJ.entitlements`: no change required. We already have `com.apple.security.network.client`, which covers Web API calls.
- Optional later: Universal Links (`apple-app-site-association`) for a nicer flow. Custom URL scheme works and is simpler; ship with that.

### 3c. Token storage
- Mirror the existing OpenAI API key pattern. `AIDJ/Utilities/Keychain.swift` already has a generic-password wrapper. Add new `KeychainKey` constants:
  - `spotify.accessToken`
  - `spotify.refreshToken`
  - `spotify.expiresAt` (ISO8601 timestamp)
  - `spotify.clientID` — **do not store here**; it's bundled in the binary / an xcconfig.
- Refresh flow:
  - SDK-initiated auth yields `SPTSession` with `accessToken`, `refreshToken`, `expirationDate`. Persist all three.
  - Before each Web API call, check expiration; if within 60 s of expiry, call `SPTSessionManager.renewSession` or hit `POST https://accounts.spotify.com/api/token` directly with `grant_type=refresh_token`.
  - The iOS SDK's SPTAppRemote uses the access token we hand it; when we renew, push the new token into `appRemote.connectionParameters.accessToken`.
- Re-auth:
  - If refresh returns 400/401 (revoked), wipe all three keys, flip the provider's auth status to `.needsReauth`, surface a banner in Now Playing + the provider row in Settings.

### 3d. Scopes
Minimum set for our features:
- `user-read-private`, `user-read-email` — profile (for greetings / logging which account)
- `playlist-read-private`, `playlist-read-collaborative` — library browsing
- `user-library-read` — saved tracks
- `streaming` — Web Playback SDK if/when macOS Phase 4 happens
- `app-remote-control` — required by SPTAppRemote

## 4. Abstraction Changes — Provider-Neutral Protocol and Router

The existing `MusicKitServiceProtocol` is Apple-Music-shaped. Two names returned directly to callers (`MusicAuthorization.Status`, `MusicKit.Artwork`) leak MusicKit types through the protocol. Both need generalization.

### 4a. New `MusicProviderService` protocol
Rename `MusicKitServiceProtocol` → `MusicProviderService`. New shape:

- `var providerID: Track.MusicProviderID { get }`
- `var authStatus: ProviderAuthStatus { get }` (new enum: `.unknown | .notAuthorized | .authorized | .needsReauth`)
- `func requestAuthorization() async -> ProviderAuthStatus`
- `func signOut() async` (new, for the Settings "disconnect" button; MusicKit gets a no-op)
- All the existing playback, library, search methods stay — signatures identical, but the concrete `MusicAuthorization.Status` is replaced by `ProviderAuthStatus`.
- `func artwork(for trackId: String) -> ProviderArtwork?` — see 4c.

Keep the protocol `@MainActor` so ApplicationMusicPlayer's main-actor requirements continue to work.

### 4b. Track provider tagging
- `AIDJ/Models/Track.swift` — extend `MusicProviderID` enum: `case spotify`. Add `Track.init(spotifyTrack:)` in the Spotify service.
- `Track.id` is *not* globally unique across providers. Change `PlayableItem.id` in `AIDJ/Models/PlayableItem.swift` to include the providerID: `"track-\(t.providerID.rawValue)-\(t.id)"`.

### 4c. Provider-neutral artwork — the awkward ripple
MusicKit's `Artwork` is a MusicKit type exposed through `MusicKitServiceProtocol.artwork(for:)`. `NowPlayingViewModel.currentArtwork` is typed `MusicKit.Artwork?`. This is the messiest part of the refactor because MusicKit's `ArtworkImage` handles the `musicKit://` scheme that AsyncImage cannot.

Recommended approach:
- Define a `ProviderArtwork` enum:
  - `.musicKit(MusicKit.Artwork)` — for Apple Music
  - `.url(URL)` — for Spotify
- Build a `ProviderArtworkView` in SwiftUI that switches on the enum — uses `ArtworkImage` for the MusicKit case, `AsyncImage` for the URL case.
- Replace `ArtworkImage(vm.currentArtwork, ...)` in `NowPlayingView.swift` with `ProviderArtworkView(...)`.

### 4d. MusicProviderRouter (new file under `AIDJ/Services/`)
Mirrors `DJVoiceRouter`:
- Holds one instance of each concrete service.
- Exposes a combined `MusicProviderService` façade for read operations that are per-track (playback control, metadata, artwork) — dispatches based on `track.providerID`.
- Exposes per-provider accessors for things that are inherently per-provider (library listings, search, auth status).
- State for "which provider did the user pick to browse?" lives in `SettingsViewModel.browseProvider`, not in the router.

### 4e. Renames / protocol split
- Rename `MusicKitServiceProtocol.swift` → `MusicProviderService.swift`.
- `PlaylistInfo` and `MusicPlaybackStatus` move into the new protocol file; both are already provider-neutral.
- `MusicKitService` conforms to the renamed protocol; no behavioral changes.

## 5. Playback Mechanics — Ducking vs Crossfade

### 5a. Current MusicKit behavior
`AudioGraph.swift` sets `AVAudioSession.setCategory(.playback, options: [.duckOthers])`. `ApplicationMusicPlayer` plays to system output opaquely; when our TTS player node starts, the OS ducks MusicKit audio. `PlaybackCoordinator.playSegment` currently *pauses* MusicKit entirely before speaking, so on MusicKit today we get a hard pause + speak + resume.

### 5b. With Spotify iOS SDK — the same model works
Spotify iOS SDK manages its own audio session internally. We cannot access its audio buffers. But the OS-level ducking mechanism is agnostic:
- **Between-song model (MVP):** Producer primes a segment. Coordinator reaches end-of-track → calls `spotifyService.pause()` (hits `appRemote.playerAPI.pause()`) → `AudioGraph.play(url:)` speaks → on completion, calls `spotifyService.start(track:)` for the next track. Identical to MusicKit flow.
- **Ducked overlap (future):** can work best-effort — we start TTS while Spotify is still playing, rely on `.duckOthers`. But we cannot schedule DJ audio precisely, and we cannot crossfade because we don't own the music stream. Apple Music retains the same limitation, so this is no regression.

### 5c. Track-position polling for Spotify
MusicKit gives us `player.playbackTime` synchronously. SPTAppRemote gives us `playerStateDidChange` delegate callbacks (sparse) plus `playerAPI.getPlayerState(callback:)` (async).
- Add `var currentPlaybackTime: TimeInterval` to `SpotifyService` — backed by a cached value updated by delegate callbacks + periodic `getPlayerState` at the coordinator's existing 500 ms cadence.

### 5d. Audio session category — test
Spotify's SDK configures its own session. Starting our TTS player after Spotify is playing should be fine. Flag for testing: if TTS gets cut off when Spotify resumes, add `.mixWithOthers` in addition to `.duckOthers`.

### 5e. What we're giving up
- **No sample-accurate crossfade with Spotify, ever.** The iOS SDK doesn't expose PCM.
- **Spotify Premium required.** Free-tier accounts get `playback_error`; surface as onboarding gate.
- **Background playback.** When backgrounded, SPTAppRemote disconnects. Spotify keeps playing on its own, but our coordinator stops receiving events. Recommend: reconnect on `willEnterForeground`; document "DJ requires foreground app".

## 6. UI Changes

### 6a. Onboarding
`OnboardingViewModel` currently gates on Apple Intelligence + MusicKit. Restructure `Status`:
- `.checking`
- `.needsAppleIntelligence(reason)` — unchanged, hard block
- `.needsAnyProvider` — new: Apple Intelligence is OK but no music service connected
- `.ready` — at least one provider is connected

New UI: after the Apple Intelligence check passes, show "Connect your music" with two cards — Apple Music and Spotify. On macOS for Phases 1–3, Spotify card is hidden or shown as "Coming soon — iOS only."

### 6b. Settings
Add a "Music Services" section. Two rows:
- **Apple Music** — status chip, "Open Music Settings" button. No disconnect (OS-managed).
- **Spotify** — status chip (Connected as @username / Not Connected / Reconnect needed), buttons: Connect / Disconnect.

Extend `SettingsViewModel`:
- `spotifyAuthStatus: ProviderAuthStatus`
- `spotifyDisplayName: String?`
- `browseProvider: Track.MusicProviderID` — persisted.

### 6c. Library tab
Recommend **option A**: segmented control at the top ("Apple Music / Spotify"), switches which provider's playlists/search are shown. `LibraryViewModel` holds a router reference and an `activeProvider` field. Option B (merged view) can come later.

### 6d. Now Playing
Add a small provider chip (Apple Music logo / Spotify logo) next to the track title.

### 6e. Queue tab
No changes — already provider-agnostic via `PlayableItem.track(Track)`.

## 7. DJ Brain / Producer Changes

The DJ brain is provider-agnostic — no changes.

`Producer.swift`:
- `findNextPlayableTrack(from:)` calls `coordinator.isPlayable(trackId:)`, which currently routes to the single `musicService`. Change signature to `isPlayable(_ track: Track) async -> Bool` so the router can dispatch on providerID.

## 8. Testing and Fakes

`AIDJTests/Fakes.swift`:
- Rename `FakeMusicService` → `FakeAppleMusicService`.
- Add `FakeSpotifyService` with identical shape, provider ID `.spotify`.
- Add `FakeMusicProviderRouter`.

New tests:
- `MusicProviderRouterTests.swift` — routing to correct fake based on track's providerID.
- `PlaybackCoordinatorTests.swift` (extend) — mixed-provider queue.
- `ProducerTests.swift` (extend) — `findNextPlayableTrack` with mixed providers.

**Constraint flagged:** `AIDJTests` builds on `platform: macOS`. The real `SpotifyService` must link against `SpotifyiOS` which is iOS-only. Guard with `#if os(iOS)`. Tests use `FakeSpotifyService` which compiles everywhere.

## 9. Phased Rollout

### Phase 1: Provider abstraction refactor, Apple-only behavior
- Rename `MusicKitServiceProtocol` → `MusicProviderService`; extract `ProviderAuthStatus`, `ProviderArtwork`.
- Add `providerID` and `ProviderArtworkView`; update `NowPlayingView` / VM.
- Add `Track.MusicProviderID.spotify` case (unused).
- Introduce `MusicProviderRouter` with only `MusicKitService` registered.
- `PlaybackCoordinator.isPlayable` takes `Track`.
- `PlayableItem.id` includes provider tag.
- Update `Fakes.swift`.
- **Ship gate:** all tests pass; manual smoke on iPhone + Mac shows identical Apple Music behavior.

### Phase 2a: Spotify Web API, read-only (iOS + macOS)
- No new SPM dep (Web API is plain URLSession).
- `SpotifyAPIClient` actor: `/me`, `/me/playlists`, `/me/playlists/{id}/tracks`, `/search`, token refresh.
- `SpotifyAuthCoordinator`: PKCE via `ASWebAuthenticationSession` on both platforms. Uses `aidj://spotify-callback`. Persists to Keychain.
- `SpotifyService` conforming to `MusicProviderService`; playback methods throw `notSupportedYet`.
- Register `SpotifyService` in router; Library tab gets segmented control; Settings gets Spotify row.
- Info.plist: `CFBundleURLTypes` + `LSApplicationQueriesSchemes`.
- **Ship gate:** user can connect Spotify, browse playlists, search catalog. Playback throws a friendly "Not yet supported" error.

### Phase 2b: Spotify iOS SDK playback wiring (iOS only)
- `project.yml` — add Spotify iOS SDK via SPM. Guard with `#if os(iOS)`.
- Extend `SpotifyService` with `SPTSessionManager` + `SPTAppRemote`.
- Implement playback methods via `appRemote.playerAPI`.
- `currentPlaybackTime` / `currentTrackDuration` / `currentTrack` / `playbackStatus` from cached `SPTAppRemotePlayerState`.
- `AIDJApp.swift` — add `@UIApplicationDelegateAdaptor` to forward `application(_:open:options:)` to `SPTSessionManager`.
- `PlaybackCoordinator.playTrack` flow for Spotify is identical — the router dispatches.
- **Ship gate:** physical iPhone test. Play a Spotify playlist with DJ enabled.

### Phase 3: Polish the Spotify playback model
- Background reconnect on `sceneWillResignActive` / `sceneDidBecomeActive`.
- Error recovery for `account_error`, Spotify app killed, etc.
- Foreground position sync.
- Audio session testing — add `.mixWithOthers` if ducking fights.
- **Ship gate:** 30-minute listening session with no desync.

### Phase 4: macOS Spotify story (decision point)
Spike first: WKWebView + Web Playback SDK + valid access token. Budget: 1 day.
- If spike works: `SpotifyMacService` wraps hidden `WKWebView`, conforms to `MusicProviderService`. Register in router for macOS. Reuse `SpotifyAPIClient` from 2a.
- If spike fails: ship "Spotify is iOS-only" — macOS card disabled with explanation.

## 10. Key Files — Summary of Touches

**Refactor (Phase 1):**
- `AIDJ/Services/MusicKitServiceProtocol.swift` — rename, generalize
- `AIDJ/Services/MusicKitService.swift` — conform
- `AIDJ/Models/Track.swift` — add `.spotify` case
- `AIDJ/Models/PlayableItem.swift` — provider tag in `id`
- `AIDJ/Services/PlaybackCoordinator.swift` — route through router
- `AIDJ/Services/Producer.swift` — update `isPlayable` caller
- `AIDJ/ViewModels/LibraryViewModel.swift` — take router, `activeProvider`
- `AIDJ/ViewModels/NowPlayingViewModel.swift` — use `ProviderArtwork`
- `AIDJ/ViewModels/OnboardingViewModel.swift` — new Status cases
- `AIDJ/App/RootView.swift` — instantiate router
- `AIDJ/Views/NowPlayingView.swift` — `ProviderArtworkView` + chip
- `AIDJ/Views/LibraryView.swift` — segmented control
- `AIDJ/Views/SettingsView.swift` — Music Services section
- `AIDJTests/Fakes.swift` — rename, add Spotify fake, add router fake

**Spotify (Phases 2+):**
- **New** `AIDJ/Services/MusicProviderRouter.swift`
- **New** `AIDJ/Services/SpotifyService.swift` (iOS-guarded)
- **New** `AIDJ/Services/SpotifyAPIClient.swift` (cross-platform)
- **New** `AIDJ/Services/SpotifyAuthCoordinator.swift`
- `AIDJ/Utilities/Keychain.swift` — Spotify key constants
- `AIDJ/Resources/Info.plist` — URL types
- `AIDJ/App/AIDJApp.swift` — `UIApplicationDelegateAdaptor`
- `project.yml` — Spotify SDK package
- `CLAUDE.md` — drop "No Spotify" line; add Premium requirement note

## 11. Assumptions and Open Questions

**Assumptions:**
- Client ID can be hardcoded (personal/hobby app). If distributed, add token-swap server.
- Premium requirement is acceptable user-facing messaging.
- Background DJ can be dropped for Spotify (app must be foreground).
- 2026-era Spotify iOS SDK still distributes via SPM.

**Open questions:**
1. Merged library (Apple + Spotify in one list) or segmented picker? Plan assumes segmented.
2. Dev vs prod client IDs / redirect URIs — xcconfig wiring needed?
3. On-device only vs token-swap server.
4. macOS Spotify: do Phase 4 or defer with UI message?
5. Update CLAUDE.md Build section re: simulator unusability?
