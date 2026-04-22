# Implementation Plan — Spotify Support for AI DJ

> **WITHDRAWN 2026-04-22 per K21.** No first-party iOS SDK path exists for a third-party App Store app to stream Spotify audio standalone. SPTAppRemote is IPC to the installed Spotify app (not a streaming SDK); Web Playback SDK is browser JS + EME DRM (unsupported in WKWebView on iOS); Spotify Connect Partner Program is hardware-OEM only; Spotify Developer Terms §III.2 prohibits streaming/proxying raw audio (djay lost Spotify in 2020 when the partnership was revoked). Spotify integration ripped out in commit `ca23170`. Document retained for historical context — the phased-refactor pattern (Phase 1a/1b/1c + `MusicProviderRouter`) shipped successfully and remains in the codebase; the rest is a cautionary record of ~2 working days spent before vendor-constraint research was run. See K21, K22 in `docs/project-tracker.md`.

**Date:** 2026-04-20
**Status:** **Withdrawn 2026-04-22** (was: Proposed)
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

## 12. Phase 2b Addendum — 2026-04-22 Reconciliation

Written after Phase 2a closed (`3c968fc`, 2026-04-21) and 7 in-smoke fix commits. The §9 Phase 2b paragraph was drafted before any implementation; reality has moved. This addendum supersedes §9 Phase 2b for the actual commit block.

### 12a. Revised Phase 2b commit split

Lead-with. Each slice is independently commit-able with its own ship gate, mirroring the 2a split discipline. Andrew vs Claude indicates who holds the blocking work on that slice.

| # | Title | Owner | Deps | Ship gate |
|---|-------|-------|------|-----------|
| 2b.1 | Spotify SDK package + Info.plist + LSApplicationQueriesSchemes (no wiring) | Andrew (dev portal) + Claude (project.yml, plist, `xcodegen generate`) | D6 resolved for macOS guard strategy | Green build both platforms; no behavior change; SDK symbols importable under `#if canImport(SpotifyiOS)` |
| 2b.2 | `SpotifyPlayback` iOS helper — SPTSessionManager + SPTAppRemote lifecycle, no integration | Claude | 2b.1, Andrew confirms Premium + Spotify app installed on test iPhone | Physical-device smoke: helper connects, receives `playerStateDidChange`, logs track URI. No routing into `SpotifyService` yet. |
| 2b.3 | Swap PKCE handshake to SPTSessionManager on iOS; macOS keeps NSWorkspace path | Claude | 2b.2 | iOS auth uses SDK; macOS unaffected; Keychain token shape unchanged; `SettingsView` Connect flow still works on both platforms |
| 2b.4 | `SpotifyService` playback methods wired to SPTAppRemote (iOS) + Premium gate | Claude | 2b.2, 2b.3, D6 | Physical iPhone: tap Spotify playlist track, playback starts, pause/resume/seek/skip all route; non-Premium returns typed `premiumRequired` surfaced as alert |
| 2b.5 | `AIDJApp` URL forwarding + foreground reconnect + position polling | Claude | 2b.4 | 30-second DJ-enabled listen on iPhone: DJ speaks between tracks, position advances, app backgrounded+foregrounded without stuck state |
| 2b.6 (optional) | Cleanup: K15 unit tests for playbackGeneration+state ordering on Spotify path; K17 cycle investigation if smoke surfaces any hangs | Claude | 2b.5 | `xcodebuild test` green; no new AttributeGraph warnings in smoke log |

Rationale for the split: 2b.1/2b.2 are pure plumbing with clean rollback; they land even if 2b.3+ slip. 2b.3 is the SPTSessionManager swap — isolates the "does SPTSessionManager avoid K16 on macOS" question from playback. 2b.4 is the first user-visible feature. 2b.5 handles the Phase 3 items the plan punted, but they're cheap once 2b.4 works and they catch the common failure modes (stuck state after app switch) that would otherwise block a clean smoke.

### 12b. Scope deltas since 2026-04-20 plan

These are the things that changed between plan-write and now. Read before starting 2b.1.

1. **`SPTSessionManager` ships in 2b, not 2a.** Plan §9 Phase 2a said "PKCE via SPTSessionManager"; actually 2a shipped manual PKCE via `ASWebAuthenticationSession` (iOS) and `NSWorkspace.open` + `.onOpenURL` (macOS, K16 workaround). Token shape on both paths is identical to what `SPTSessionManager` produces (`accessToken`/`refreshToken`/`expiresAt`), so 2b.3 is a service-level swap — **do not touch `KeychainKey.spotify*`, `SpotifyTokens`, or `SpotifyAPIClient`'s refresh path**.
2. **macOS auth is NSWorkspace + `.onOpenURL`, not ASWebAuthenticationSession.** `SPTSessionManager` is iOS-only per the SDK, so macOS can't use it at all. 2b.3 must not regress macOS — the existing path stays untouched, and the SPTSessionManager swap is `#if os(iOS)` only.
3. **`MusicProviderRouter` already exists and registers Spotify.** Plan §4d listed it as "new"; it landed in Phase 1c (`3d09898`) and Spotify was registered in 2a.3 (`ac8a5ed`). 2b extends `SpotifyService` in place; it does not introduce a new service or touch the router.
4. **`SpotifyService` playback methods throw `SpotifyServiceError.notSupportedYet`.** 2b.4 replaces these throws. **macOS must keep throwing** (plan D6 recommendation); use `#if os(iOS)` around the real implementations and keep a friendlier `macOSNotSupported` error branch for D4's sake.
5. **iCloud sync already persists `browseProvider`.** 2a.4 (`8a1eeee`) wired it through `CloudSyncService`. 2b does not touch curated keys or sync.
6. **K17 `AttributeGraph: cycle detected` is present.** Low severity but flagged: don't let 2b wire new bindings that write to `settings` from inside `.onOpenURL` handlers or `onChange` observers. Prefer routing through a coordinator method (e.g. `SpotifyService.handleAuthCallback(_:)` pattern from 2a).
7. **K15 playback invariants now codified.** Any new transport method on `SpotifyService` must respect: (a) bump `playbackGeneration` + stop `audioGraph` for methods that end the current segment (skip/stop); (b) set `state = .playing` before entering `monitorTrackUntilEnd` on resume. Add a comment block at the top of any Spotify transport method listing which invariant applies.
8. **`project.yml` already has `CFBundleURLTypes` for `aidj://`.** 2b.1 only needs to add `LSApplicationQueriesSchemes: [spotify]` and the SPM package entry — not the URL scheme again.
9. **`handleAuthCallback(_:)` is on `MusicProviderService`, not macOS-guarded.** The protocol has it with a no-op default; `AIDJApp.onOpenURL` forwards unconditionally. No changes required in 2b — SPTSessionManager's iOS URL handling is independent of this path.

### 12c. Andrew-owned prerequisites

Enumerated crisply so nothing stalls mid-commit.

| Prereq | Blocks | Notes |
|--------|--------|-------|
| Physical iPhone running iOS 26 with Spotify app installed + signed in | 2b.2, 2b.4, 2b.5 | Spotify SDK doesn't work in simulator (same posture as Apple Intelligence gate). Plan on one device-test session per slice after 2b.2. |
| **Spotify Premium** on the test account | 2b.4 (verification), 2b.5 (smoke) | Non-Premium returns `playback_error` from SPTAppRemote; 2b.4 needs to both gate the UX and verify the gate works. If Andrew's account is non-Premium, 2b.4 can still ship the gate path but needs a second account to verify the happy-path playback. |
| Spotify dev portal — confirm `aidj://spotify-callback` still registered on Client ID `6901b52a…` | 2b.1 | Already set for 2a.1; just eyeball that it's still there. |
| Spotify dev portal — add iOS Bundle ID `com.andrewporzio.aidj` under App iOS SDK section | 2b.1 | SPTAppRemote refuses to connect if the bundle ID isn't registered. Required once, not per-build. |
| LaunchServices URL handler decision — only if D6 resolves to "WKWebView spike now" | 2b.1 (macOS branch) | Not required if D6 defers macOS to Phase 4 (current recommendation). |
| Test account sanity check — tracks playable in the Spotify app itself | 2b.4 | Region/device-limit issues on the Spotify account show up here first; cheaper to rule out before blaming SPTAppRemote. |

### 12d. New open decisions (D6, D7) + re-surfaced

- **D6 (new)** — macOS Spotify in Phase 2b.
  - Options: (a) ship friendly "Spotify playback is iOS-only for now" alert — macOS `SpotifyService` playback methods continue to throw, Library picker still surfaces browse/search (2a capability); (b) attempt WKWebView + Web Playback SDK spike inside 2b. Plan has option (b) under Phase 4.
  - Recommendation: **(a).** Keeps 2b small and uniformly iOS-focused; option (b) is a day-plus DRM/WebKit spike with an independent risk profile. D4's "defer until iOS phases land" still applies — 2b isn't "iOS done," it's "iOS SDK wired" — so push the WKWebView spike to a separate Phase 4 commit block after 2b smoke closes. The `SpotifyServiceError` enum should gain a `macOSNotSupported` case (or reuse `notSupportedYet` with a better copy path at the UI). Closes D4 implicitly if resolved (a).
- **D7 (new)** — Polish commit scope.
  - Question: should 2b absorb the K17 AttributeGraph cycle warnings + the Library unauth empty-state alignment (Backlog) + any other smoke-adjacent polish? Plan had "Phase 3 polish" as a separate block; 2a smoke already surfaced a handful of small things.
  - Recommendation: **separate polish commit block after 2b.5** (call it 2c if macOS deferred, otherwise bundled into Phase 3). Don't pollute 2b's physical-device smoke with UI polish — keep 2b commits focused on SDK integration so regressions are attributable. Note: the original task brief mentioned `ITMediaItem` / MPMediaEntityProperty warnings "found in the Phase 1 smoke log"; grep finds no such identifiers in the repo, so either they're system-framework log noise (likely — those are MediaPlayer/iTunesLibrary log lines from inside Apple's frameworks, not ours) or they were in a log Andrew has locally. Flagged for Andrew to confirm; treating as "not our code" until evidence appears.
- **D4 (re-surfaced)** — resolved by D6 above; move D4 to Locked if D6 resolves (a).

### 12e. Watch-outs and risk flags

- **SDK distribution.** Spotify's iOS SDK lists SPM as supported since 2023. Confirm during 2b.1 that the SPM URL (`https://github.com/spotify/ios-sdk` or the current package repo — verify) still resolves; fall back to `SpotifyiOS.xcframework` drop-in if SPM doesn't work on macOS 26 / Xcode 26. Budget an hour.
- **`@preconcurrency import SpotifyiOS`** is almost certainly required. The SDK predates Swift 6 strict concurrency and its delegate protocols are Obj-C. Pattern matches FluidAudio (K2).
- **Delegate callbacks.** `SPTAppRemoteDelegate` / `SPTSessionManagerDelegate` fire on the main queue per SDK docs, but verify — if they fire off-main, wrap in `Task { @MainActor in ... }` inside `SpotifyService` so `currentPlaybackTime` / `playbackStatus` reads stay main-isolated. Any discrepancy from the docs is a Feedback Assistant report.
- **Entitlements.** No new entitlements expected (network client already there). `com.apple.security.network.client` covers both the Web API (2a) and SPTAppRemote's local socket (2b). If SPTAppRemote needs something extra, it'll surface in the 2b.2 smoke.
- **`Info.plist` additions.** Only `LSApplicationQueriesSchemes: [spotify]` is new. Declare in `project.yml` under `targets.AIDJ.info.properties` so `xcodegen generate` doesn't strip it (K10 lesson).
- **`project.yml` churn.** Adding the SPM package: mirror FluidAudio's entry shape. Re-run `xcodegen generate` after every package edit.
- **K15 crossover.** When wiring `SpotifyService.skipToNext` / `.pause` / `.stop`, `PlaybackCoordinator` still owns `playbackGeneration` and `audioGraph.stop()` — 2b.4 doesn't need to bump them inside `SpotifyService`, but it does need to ensure coordinator's generation-bump path is exercised for Spotify tracks too. The router already dispatches, so a test in 2b.6 that asserts skip-over-DJ works for Spotify tracks (matching `688bbf8`'s fix for Apple Music) is worth the extra hour.
- **K16 crossover.** SPTSessionManager wraps `ASWebAuthenticationSession` under the hood on iOS. iOS doesn't hit K16 (iOS was never crashing). Watching the smoke log on macOS during 2b.3 — if the NSWorkspace path regresses when `SpotifyService` gains SDK imports under `#if canImport(SpotifyiOS)`, that's a signal the conditional-compilation boundaries leaked.
- **`PlayableItem.id` namespacing.** Phase 1a prefixes with `providerID`; 2b.4 just forwards SPTAppRemote's track URI as the Spotify `Track.id` (strip `spotify:track:` prefix or leave as-is — pick one at the service boundary and document in 2b.4).

### 12f. Smoke test matrix

Every slice from 2b.2 onward needs a physical-device pass before the next merges. Matrix here so 2b doesn't repeat the 2a experience of finding 7 bugs post-commit.

| Scenario | 2b.2 | 2b.3 | 2b.4 | 2b.5 |
|----------|------|------|------|------|
| Clean sign-in from zero tokens | — | ✓ iPhone + Mac | — | — |
| Re-auth after `signOut()` | — | ✓ iPhone + Mac | — | — |
| Refresh token round-trip (expire, retry) | — | ✓ (mock clock) | — | — |
| SPTAppRemote connects + receives `playerStateDidChange` | ✓ iPhone | — | ✓ iPhone | ✓ iPhone |
| Play track from Spotify playlist with DJ disabled | — | — | ✓ iPhone | ✓ iPhone |
| Play track with DJ enabled, DJ speaks between tracks | — | — | ✓ iPhone | ✓ iPhone |
| Pause → resume (K15 rule #2) | — | — | ✓ iPhone | ✓ iPhone |
| Mid-DJ skip (K15 rule #1) | — | — | ✓ iPhone | ✓ iPhone |
| Non-Premium account → typed `premiumRequired` → alert | — | — | ✓ iPhone | — |
| Spotify app force-quit mid-playback → error surfaced, not crash | — | — | — | ✓ iPhone |
| App background → foreground → reconnect | — | — | — | ✓ iPhone |
| macOS Spotify track tap → "iOS-only" alert (D6a) | — | ✓ Mac | ✓ Mac | ✓ Mac |
| Apple Music playback unaffected (regression) | ✓ both | ✓ both | ✓ both | ✓ both |

Smoke lessons encoded: K15 invariants get explicit rows (2a missed these); regression row for Apple Music is mandatory every slice because Phase 2a had zero Apple-Music regressions only because the refactor was audited carefully — an SDK integration could break it subtly (shared audio session category, for instance); macOS regression row catches K16 leakage.

### 12g. Sequencing note

2b.1 is unblocked today. 2b.2 gates on Andrew confirming Premium + Spotify app on the test iPhone (five-minute check). 2b.3 gates on 2b.2 being green. 2b.4 is the first slice that requires a full 30-minute listening test.
