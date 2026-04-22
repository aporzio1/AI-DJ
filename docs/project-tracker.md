# AI DJ — Project Tracker

**Owner:** Andrew P
**PM Agent:** `aidj-pm` (see `.claude/agents/aidj-pm.md`)
**Last updated:** 2026-04-21 — **Spotify API Feb-2026 migration identified as root cause of playlist-tracks 403 + decoder malformedResponse.** Andrew + Claude burned ~2 hrs on pattern-matching fixes (tolerant decoders, `/playlists/{id}` pivot, etc.); research against official Spotify migration guide (`https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide`) confirms Spotify renamed + restricted endpoints effective 2026-02-11 (new apps) and 2026-03-09 (existing Dev Mode apps). PM verdict: **hybrid path (new D8 recommendation)** — migrate DTOs to the renamed `/playlists/{id}/items` endpoint (keeps Web API playlist-tracks access for Andrew-owned playlists) and continue with SPTAppRemote URI playback as planned in 2b. Cheapest next step for Andrew: one-shot curl probe against `/playlists/{id}/items` to verify the hypothesis before code. Prior state: D6 + D7 locked; 2b.1 in flight; 2a smoke test had passed.

---

## 1. Current State

- **Platforms:** iOS 26 / macOS 26, Apple Silicon only
- **Stack:** Swift 6.0 strict concurrency, SwiftUI, MusicKit, AVFoundation, Foundation Models
- **Version:** 1.0 (CFBundleVersion 1)
- **Core capability:** Plays Apple Music content (playlists, albums, stations) with an AI DJ narrating between tracks; can pull RSS news headlines for commentary
- **TTS providers (pluggable via `DJVoiceRouter`):** Device Voices (AVSpeechSynthesizer), OpenAI cloud TTS, Kokoro on-device (FluidAudio CoreML) with launch-time warm-up
- **Music providers:** Apple Music (full playback) + Spotify (browse/search only — read-only API; playback arrives in Phase 2b). `MusicProviderRouter` dispatches per-track. `SettingsViewModel.browseProvider` persisted to `UserDefaults` and iCloud-synced.
- **UI tabs:** Library (default) / Queue / Settings, plus persistent MiniPlayerBar (2-row with progress slider, shuffle/repeat, thumbs feedback) and an expandable Now Playing sheet. Library has a segmented Apple Music / Spotify picker.
- **Library landing:** Recently Played + Made for You (playlists, albums, stations) with stale-while-revalidate disk cache + pull-to-refresh. Spotify side surfaces `/me/playlists` + catalog search; playback is gated with a friendly "coming in Phase 2b" message.
- **Onboarding:** 4-step first-launch wizard (Name → DJ + Voice → News → iCloud) with migration auto-completion for existing users
- **iCloud sync:** `CloudSyncService` mirrors curated Settings keys to NSUbiquitousKeyValueStore; opt-in toggle + hot-reload across devices
- **Personas:** Multiple personas with built-in presets + user-created custom personas; DJ frequency + News frequency pickers
- **Feedback:** Thumbs-up / thumbs-down per track injected into DJ prompt

---

## 2. Shipped

Reverse-chronological. Commit hashes are 7-char.

### 2026-04-21
- **2b.0 Plan reconciliation (docs-only, no commit yet)** — Spotify plan Phase 2b addendum written against the post-2a state. Appended as §12 of `docs/superpowers/plans/2026-04-20-spotify-support.md`. Supersedes §9 Phase 2b's single paragraph with a 6-slice commit split (2b.1 SDK package + plist, 2b.2 SPTAppRemote lifecycle helper, 2b.3 SPTSessionManager swap iOS-only, 2b.4 playback methods + Premium gate, 2b.5 URL forwarding + foreground reconnect, 2b.6 optional cleanup tests). Codifies: SPTSessionManager is 2b not 2a (Keychain shape unchanged); macOS keeps NSWorkspace path untouched (K16); `MusicProviderRouter` already exists so no router changes; K15 playback invariants must be respected in every new Spotify transport method; K17 AttributeGraph cycles must not be amplified. New decisions D6 (macOS in 2b: iOS-only alert vs WKWebView spike) + D7 (polish commit scope) raised. Smoke matrix encodes per-slice physical-device scenarios including K15 mid-DJ skip + pause/resume rows.
- `3c968fc` — Phase 2b playback gate now surfaces a dismissible alert when the user taps play on a Spotify track, instead of silently doing nothing. Previous behavior (2a.5) caught `ProviderError.notSupportedYet` in `LibraryViewModel` but no user-visible copy reached the screen — users experienced a dead tap. Alert uses standard SwiftUI `.alert(…, isPresented:)` with a clear "Spotify playback lands in Phase 2b" message + OK dismiss.
- `2854cd6` — `validateAuthorization()` probe on Settings appear: when the Music Services section renders, `SpotifyService` hits `/me` with the persisted token; on 401, tokens are cleared and status chip flips to Disconnected. Fixes "Stale Connected" UX bug where a revoked/expired-past-refresh token looked live in the UI until the user tried to browse. Surfaced during Phase 2a smoke test.
- `4b5e97b` — **macOS Spotify auth pivot.** Swapped `ASWebAuthenticationSession` for `NSWorkspace.open(_:)` + SwiftUI `.onOpenURL` handler on macOS. Triggered by a reproducible `libdispatch` assertion crash inside Apple's framework on macOS 26 (session `.start()` returned `true`, then crashed on an internal dispatch queue before the callback fired — see K16). iOS still uses `ASWebAuthenticationSession`. URL scheme (`aidj://spotify-callback`) and PKCE handshake are platform-agnostic, so the pivot only touched the presentation layer. No token-shape change.
- `564037f` — Diagnostic: log which window was captured as the ASWebAuthenticationSession presentation anchor. Retained as a debug log — useful for diagnosing future presentation-layer auth issues on macOS or iPad.
- `a2c1516` — Diagnostic: trace `beginAuthFlow()` + retain `ASWebAuthenticationSession` past the method return so ARC doesn't tear it down mid-handshake. Retention was the initial hypothesis for the macOS crash (it wasn't — see `4b5e97b`), but the retention fix is still correct on iOS and stays.
- `51b1080` — Capture presentation anchor on `MainActor` for PKCE sign-in. Pre-fix, the anchor was resolved off-main and could return `nil` on macOS, causing `ASWebAuthenticationSession` to fail-open silently. Correct on both platforms; kept even after the macOS pivot because iOS still uses the session.
- `8d926fd` — First attempt at fixing the `libdispatch` crash in Spotify PKCE sign-in. Did not land the fix (superseded by `4b5e97b`'s pivot), but tightened up the handshake retention path along the way.
- `688bbf8` — Smoke-test regression fixes (both predated session, exposed by Phase 1 physical-device smoke run). **Bug 1:** `PlaybackCoordinator.play()` resume branch never set `state = .playing` before entering `monitorTrackUntilEnd`; monitor's `state != .playing` guard tripped immediately, leaving coordinator stuck `.paused` while MusicKit was resuming audio. UI button never flipped back to "pause"; re-taps looped the same broken resume path. **Bug 2:** `skip()` and `previous()` didn't bump `playbackGeneration` or stop `audioGraph`, so a mid-sentence DJ segment kept speaking over the new track. Fix bumps generation + stops audioGraph at the top of both methods. Both bugs hidden during the 6-week test-suite outage (K1) — pause/resume/skip transitions were never exercised headlessly. Reinforces K13 (build-system + test-suite staleness masks logic regressions).
- `10fc7f3` — Spotify plan Phase 2a Commit 5 (2a.5): Library segmented provider picker. `LibraryView` gains a segmented control ("Apple Music / Spotify") bound to `SettingsViewModel.browseProvider`. `LibraryViewModel` now router-backed with `setProvider(_:)`; fetches Recently Played / Made for You / search from `router.provider(for: activeProvider)` instead of a single Apple Music service. Spotify side surfaces `/me/playlists` and catalog search; Recently Played shows "Not available yet" on Spotify per plan scope. Playback is gated when `activeProvider == .spotify` — tapping play surfaces a friendly "Spotify playback lands in Phase 2b" message (no crash, no `notSupportedYet` throw to the user). **Ship gate for plan §9 Phase 2a met:** user can connect Spotify, browse playlists, search catalog, tapping play yields a clear message. Builds green on macOS + iOS; 40 tests pass.
- `8a1eeee` — Spotify plan Phase 2a Commit 4 (2a.4): `SettingsViewModel.browseProvider: Track.MusicProviderID` persisted to `UserDefaults` and mirrored via `CloudSyncService` to iCloud (curated key). `MusicProviderService` gains `signOut()` so the router can wipe a provider's auth. `SettingsView` — new "Music Services" section: Apple Music row (status chip, "Open Music Settings"); Spotify row (Connect / Disconnect wired to `SpotifyService`, status reflects token presence). First commit where Spotify authZ is actually exercise-able from the UI.
- `ac8a5ed` — Spotify plan Phase 2a Commit 3 (2a.3): `AIDJ/Services/SpotifyService.swift` conforms to `MusicProviderService`. `providerID == .spotify`, `authStatus` reflects Keychain token presence, `requestAuthorization()` calls `SpotifyAuthCoordinator.beginAuthFlow()`, `signOut()` clears tokens. Library methods delegate to `SpotifyAPIClient`; provider-neutral artwork returns `.url(URL)`. **Playback methods throw `ProviderError.notSupportedYet`** per plan §9 — UI in 2a.5 intercepts this before it surfaces to the user. `MusicProviderRouter` registers the second provider and exposes `.spotify` accessor + `provider(for:)`. `FakeSpotifyService` added to `AIDJTests/Fakes.swift`.
- `c9b0583` — Spotify plan Phase 2a Commit 2b (2a.2b): real Spotify Client ID (`6901b52a…`) swapped into `SpotifyAuth.clientID`. One-line change; no code churn. Unblocks 2a.3+ so `requestAuthorization()` hits a real `/authorize` endpoint.
- `9dd5d39` — Spotify plan Phase 2a Commit 2a (2a.2a): new `AIDJ/Services/SpotifyAPIClient.swift` — `actor`, `URLSession`-backed. Methods: `me()`, `playlists()`, `tracks(playlistID:)`, `search(query:types:)`. Token refresh delegated to `SpotifyAuthCoordinator`; 401 → refresh once → retry. Codable DTOs for `/me`, paginated `PlaylistObject`, `TrackObject`. **8 new `URLProtocol`-mocked tests** exercising pagination, 401-retry, decoder error paths. No UI, no Client ID dependency.
- `d69eadc` — Spotify plan Phase 2a Commit 1 (2a.1): Spotify PKCE auth coordinator + Keychain keys, no UI. New `AIDJ/Services/SpotifyAuth.swift` containing `SpotifyAuth` namespace (placeholder `clientID`, `redirectURI = aidj://spotify-callback`, scopes, `/authorize` + `/api/token` endpoints), `SpotifyTokens` value type (`accessToken` / `refreshToken` / `expiresAt` + `isExpiring(leeway:now:)`), and `@MainActor` `SpotifyAuthCoordinator` with `beginAuthFlow()` (ASWebAuthenticationSession PKCE handshake, state check, code exchange, Keychain persist), `refreshIfNeeded()` (60s leeway), `signOut()`. PKCE helpers + form-encoding + query-parsing exposed static for tests. `KeychainKey` adds `spotifyAccessToken` / `spotifyRefreshToken` / `spotifyExpiresAt` (ISO-8601). `project.yml` gains `CFBundleURLTypes` with scheme `aidj`; regenerated. `AIDJTests/SpotifyAuthCoordinatorTests.swift` — 10 new tests covering token expiry boundaries, RFC 7636 Appendix B reference vector (guards SHA256 + base64url pipeline), PKCE shape/entropy, authorize URL assembly, form-encoding determinism + percent-encoding, callback parsing. **32 tests pass** on macOS + iOS. **Deviation from plan §9 noted:** plan said "SPTSessionManager PKCE in 2a"; SPTSessionManager ships with the SDK in 2b. 2a rolls manual PKCE via `ASWebAuthenticationSession`. Token shape is identical so 2b swaps cleanly. Per D3 this was already the intended path.
- `c325b56` — K1 closed: `xcodebuild test -scheme AIDJ -destination 'platform=macOS'` green, 22 tests across 4 suites. Two stacked blockers and two stale assertions. **Blocker 1:** `project.yml` didn't set `GENERATE_INFOPLIST_FILE: YES` on `AIDJTests`, so codesign failed before Swift even compiled — this was hiding the real error. **Blocker 2:** once Info.plist auto-gen was on, the actual concurrency error surfaced — `FakeAudioGraph` was `@MainActor` but `AudioGraphProtocol.stop()` is nonisolated (production `AudioGraph` is an `actor` with `nonisolated func stop()`). Dropped `@MainActor` from the fake, added `@unchecked Sendable` (fake is exercised sequentially from one `@MainActor` test context, safe). **Stale assertions:** tests hadn't run in 6+ weeks. `ModelsTests.playableItemTrackIdentity` expected `"track-xyz"` — now `"track-appleMusic-xyz"` after Phase 1a `providerID` namespacing. `PlaybackCoordinatorTests.pauseCallsMusicServiceStop` expected `stopCallCount == 1` — `replaceQueue` already calls `router.stop()` once, so 2 is correct. **Lesson worth keeping:** cause-chain was Info.plist → main-actor → stale assertions; each layer hid the next. When a test target hasn't been green in weeks, assume multiple stacked failures, not one. Closes K1 and K13 (see below).
- `3d09898` — Spotify plan Phase 1c: introduced `AIDJ/Services/MusicProviderRouter.swift` (`@MainActor final`, mirrors `DJVoiceRouter` shape — concrete, not protocol-backed). Router owns one `MusicKitService`, exposes `.appleMusic` per-provider accessor, dispatches `start`/`isPlayable` per-track on `track.providerID`, and delegates current-playback (pause/resume/stop/seek/skipToNext + current Track/Time/Duration/Status + artwork) to a private `currentProvider` that's always `appleMusic` for now. Added `providerID: Track.MusicProviderID { get }` to `MusicProviderService`; `MusicKitService` returns `.appleMusic`, `FakeMusicService` mirrors. `PlaybackCoordinator.init(router:audioGraph:)` replaces the `musicService:` signature; `isPlayable(trackId:)` → `isPlayable(_ track: Track)` per plan §7 (`Producer.findNextPlayableTrack` updated). `NowPlayingViewModel.init(coordinator:router:…)` now takes the router directly for the playback façade. `RootView` composes one router wrapping `MusicKitService`; `OnboardingViewModel` + `LibraryViewModel` keep their `MusicProviderService` contract and are wired to `musicProvider.appleMusic` (they pivot to `browseProvider` dispatch in Phase 2a). Tests use the real router wrapping `FakeMusicService` — no `FakeMusicProviderRouter` needed, router is plain composition. Builds green on macOS + iOS. `SettingsViewModel.browseProvider` deliberately deferred to Phase 2a per scope tweak.
- `8bb13d3` — Spotify plan Phase 1b: collapsed the two artwork methods on `MusicProviderService` into one provider-neutral `artwork(for:) -> ProviderArtwork?`; deleted `providerArtwork(for:)`. `MusicKitService` wraps cached `Artwork` in `.musicKit(...)` at the boundary. `NowPlayingViewModel.currentArtwork` retyped to `ProviderArtwork?` and gained `currentArtworkFallbackURL: URL?`. `NowPlayingView` + `MiniPlayerBar` swapped `ArtworkImage` → `ProviderArtworkView`; in-view placeholder paths folded into the wrapper. `import MusicKit` dropped from three files. `FakeMusicService.artwork(for:)` returns `ProviderArtwork?` (nil). Builds green on macOS + iOS. Zero behavior change on Apple Music. Closes K12.
- `79df4af` — Spotify plan Phase 1a (pure refactor): renamed `MusicKitServiceProtocol` → `MusicProviderService`; new `ProviderAuthStatus` enum replacing `MusicAuthorization.Status` in protocol; `PlayableItem.id` namespaced by `providerID`; all call sites updated (`MusicKitService`, `PlaybackCoordinator`, `NowPlayingViewModel`, `LibraryViewModel`, `OnboardingViewModel`, `FakeMusicService`). Builds green on macOS + iOS. Left `artwork(for:) -> Artwork?` on the protocol deliberately — Phase 1b.
- `686a818` — Tracker sweep: reconciled 39 shipped commits into tracker; added K10/K11; refreshed Current State.
- `11ca3ca` — Station playback now shows track info + transport works.
- `48b31bf` — Warm up Kokoro at launch; MiniPlayerBar indicator distinguishes "Loading" from "Downloading".
- `b8a0f95` — `replaceQueue` now stops in-flight playback so station switches don't overlap.
- `3eb85b0` — Wire station playback so Made for You cards are all tappable (playlists, albums, stations).
- `5c09db9` — Don't let empty cache poison Made for You for 30 min (skip save on empty result).
- `7bb16a2` — Made for You surfaces albums + stations, not just playlists.
- `1c5dfed` — Cache Recently Played + Made for You with stale-while-revalidate (UserDefaults disk cache, 30 min TTL, pull-to-refresh, silent-stale on failure, device-local).
- `a432220` — Spell out initialisms (GPT, NPR, BBC, etc.) so TTS doesn't say "gept".
- `5eb5828` — Download indicator condition fix — was gated on empty queue.
- `125b685` — Download indicator now actually appears + tone down AI-flowery DJ.
- `efa3934` — MiniPlayerBar Kokoro download indicator (icon + indeterminate spinner).
- `846252f` — Merge wizard DJ + Voice steps into a single page.
- `80b2f9f` — Reset Onboarding now actually shows the wizard next launch.
- `262566f` — Onboarding wizard now includes voice provider + voice.
- `d08228b` — Reset Onboarding now confirms + tells you it worked.
- `dfa6691` — Onboarding Commit B: first-launch 4-step preferences wizard (Name → DJ → News → iCloud) with migration auto-complete for existing users.
- `dd6ff07` — Onboarding Commit A: iCloud sync for Settings + RSS feeds. Adds `com.apple.developer.ubiquity-kvstore-identifier` entitlement, `CloudSyncService` singleton wrapping `NSUbiquitousKeyValueStore`, `iCloudSyncEnabled` Settings toggle, curated key mirroring, two-way reconcile via `didChangeExternallyNotification`.
- `b154f0b` — Stop hiding persona name from VoiceOver on Settings row.
- `664046b` — iOS tab bar was obscured by MiniPlayerBar — move inset per-tab.
- `05303a9` — iOS full-screen launch + orientations + Kokoro sending warning fix.
- `5804abd` — Stop DJ hallucinating stations + looping one headline.
- `9e38a5c` — Stop double-gating news — DJBrain was silently dropping headlines.
- `fb70f38` — Pause then play resumes in place instead of restarting track.
- `fe0cc65` — Thumbs-up / thumbs-down on the MiniPlayerBar (Phase 3 of MiniPlayerBar work).
- `ee48a67` — News frequency slider (Rarely / Balanced / Often / Always).
- `a7afe2a` — News pipeline diagnostics — propagation, logging, prompt (News Commit A).
- `c652952` — Persist DEVELOPMENT_TEAM in project.yml.
- `2fdaaf4` — HIG P2 — normalize off-grid spacing to multiples of 4 (HIG Commit 2).
- `bfad5e5` — HIG P1 — tap targets, a11y labels, destructive confirmation (HIG Commit 1).
- `2134b41` — Thumbs-up / thumbs-down track feedback (MiniPlayerBar Phase 3).
- `a63e513` — MiniPlayerBar shuffle + repeat controls (Phase 2).
- `66ad02e` — MiniPlayerBar progress slider + 2-row layout (Phase 1).
- `68a67d7` — DJ frequency setting (Rarely / Balanced / Often / Every Song).
- `eb808d6` — Multiple DJ personas with built-in presets (Persona Phase 2).
- `8705b17` — Editable DJ persona — name + instructions (Persona Phase 1).
- `72246a0` — Register AppIcon for macOS (was iOS-only).
- `2b00f39` — Cmd+, opens Settings in a separate window on macOS.
- `d0e29a7` — Skip `playerNode.stop` on same-format segments (AudioGraph:39).
- `844dfac` — Library landing page — Recommendations section (Phase 2).

### 2026-04-20
- `290263b` — Library landing page — Recently Played section (Phase 1).
- `00041d3` — Grounded PM agent in PMI Talent Triangle + HBR project-management principles.
- `600ffae` — Added AI DJ project-manager agent and tracker.
- `c42dc1d` — Playlist detail view + shuffle button + OpenAI voice descriptors.
- `946181a` — Spotify support implementation plan committed (docs only).
- `9fd34cf` — Kokoro voice preview in Settings; trash-can delete on RSS rows; URL-auto-linkification fix.
- `423b27a` — Redesigned Add Feed row.
- `760e17e` — Manual Download and Remove Model buttons for Kokoro TTS.
- `0ad3c8a` — Phase 2: Kokoro on-device TTS via FluidAudio.

### 2026-04-17
- `0f4422c` — `willAdvance` lead time widened to 20 s; softened news-hook prompt.
- `3c4df88` — Decode audio into a PCM buffer for reliable MP3 playback from OpenAI.
- `2c7a795` — Phase 1: pluggable TTS provider layer; added OpenAI TTS.
- `01022cf` — Deferred `playerNode.stop` to eliminate priority inversion.
- `5193ca1` — DJ no longer announces an unplayable track.
- `6a3a3bb` — Three QoL fixes from user logs.

### 2026-04-16 and earlier
- `84cf31c` — Step-by-step voice-download instructions in Settings footer (macOS).
- `15f9908` — macOS button that opens System Settings → Spoken Content directly.
- `c2d5a72` — Eliminated priority inversion in AudioGraph stop path.
- `da5ffdc` — Voice picker in Settings.
- `1b726b6` — Progress line across top of MiniPlayerBar.
- `7ff8942` — Persistent MiniPlayerBar at bottom; Library default tab.
- `a790a18` — Library search: filter playlists and play catalog songs.
- `95dc898` — Removed "e.g. Andrew" placeholder.
- `0cec98d` — HIG pass on SettingsView.

---

## 3. In Progress

- **2b.1 Spotify iOS SDK SPM package + `LSApplicationQueriesSchemes` + xcodegen regen** — executing. Pure packaging commit: no SPTAppRemote/SPTSessionManager wiring, no Swift behavior change. Ship gate: green build on macOS + iOS destinations. Does not require Andrew's dev-portal check or physical iPhone — those gate 2b.2.
- 2b.2+ **blocked** on Andrew prereqs: dev-portal check (redirect URI still registered + iOS Bundle ID added under iOS SDK section) + physical iPhone (iOS 26) with Spotify app. Premium **confirmed 2026-04-21**.

---

## 4. Backlog

| Item | Summary | Plan |
|------|---------|------|
| Album & station detail views | Station playback works via tap-to-play; album playback not yet verified end-to-end. Consider dedicated album-detail (track list, shuffle) and station-detail (now-playing only) views once Spotify abstraction lands so they route through the provider-neutral protocol. | Do after Spotify abstraction (Phase 2a of Spotify plan) |
| Spotify music provider | Add Spotify alongside Apple Music. Phased rollout: abstraction refactor → read-only API → iOS SDK playback → macOS decision. | `docs/superpowers/plans/2026-04-20-spotify-support.md` |
| Onboarding + iCloud sync — Commit C: Keychain iCloud sync (optional) | Flip `kSecAttrSynchronizable = true` on the OpenAI API key Keychain item in `Keychain.swift`. One-line change. Risk: a bad or revoked key silently propagates to all devices. Only ship if user explicitly asks; surface as a separate Settings toggle ("Sync API key via iCloud Keychain") if shipped. | Deferred — gauge demand now that Commits A+B have landed |
| Kokoro download indicator — Phase 2: real % progress | Replace the indeterminate spinner with a deterministic `ProgressView(value:)`. Blocked on EITHER: (a) FluidAudio upstream adds a download-progress callback, or (b) we swap FluidAudio's internal HF downloader. Out of scope for MVP. | Backlog — revisit quarterly; file FluidAudio issue if one doesn't exist |
| Rotate RSS headlines across segments | `RSSFetcher.fetchHeadlines().first` always picks top headline. Across several segments from the same feed, the DJ hears the same headline repeatedly. Options: (a) rotate through top N, (b) remember last-used headline URLs and skip recently-used ones. | Deferred — see K7 |
| Merged vs segmented library | UX decision for how playlists from multiple providers are shown. | Bundled into Spotify plan §6c |
| macOS Spotify playback | WKWebView + Web Playback SDK — requires DRM spike. | Bundled into Spotify plan §9 |
| UI polish: Library "No Playlists" empty state alignment (Spotify, unauth) _(low)_ | When `browseProvider == .spotify` and the user isn't signed in, the `ContentUnavailableView` ("No Playlists") renders top-left of the content area instead of centered — doesn't match Apple Music's centered presentation. Repro: Library → flip segmented picker to Spotify while not signed in. Likely one-line fix in `AIDJ/Views/LibraryView.swift` — add `.frame(maxWidth: .infinity, maxHeight: .infinity)` to the ContentUnavailableView wrapper or revisit Section sizing semantics. Est. <30 min. Non-blocking. | — |

---

## 5. Open Decisions

| # | Decision | Options | Current recommendation |
|---|----------|---------|------------------------|
| D1 | Merged library view or segmented provider picker? | (a) segmented per-provider tabs, (b) unified list with provider badges | Segmented for MVP; merge later |
| D5 | Update `CLAUDE.md` re: simulator unusability | (a) add a note, (b) leave current wording | Add note after Spotify Phase 2b lands |
| D8 | Spotify playlist-tracks 403 + decoder malformedResponse response | (a) **Hybrid — migrate DTOs to `/playlists/{id}/items` (Feb-2026 Spotify API rename) and keep SPTAppRemote per-track URI playback.** 30-60 min of code. Keeps DJ-between-tracks UX because Producer still gets track list in advance; (b) SPTAppRemote-only — hand Spotify a playlist URI, no Web API track reads. Cheap to build but **likely breaks DJ prep** — `Producer.findNextPlayableTrack` needs the upcoming track before `playerStateDidChange` fires, and react-after isn't prep-before; (c) submit for Extended Quota Mode — requires public-facing URL + privacy policy + dev agreement, overkill for a one-user hobby app; (d) scope Spotify to "search + play individual tracks" — ships fast, drops playlist browse. | **(a) Hybrid.** Evidence: official Spotify Feb-2026 migration guide documents (1) `GET /playlists/{id}/tracks` deprecated, replaced by `GET /playlists/{id}/items`; (2) playlist JSON shape: `tracks` → `items`, `tracks.items` → `items.items`, `tracks.items.track` → `items.items.item`; (3) `items` only returned for user-owned/collaborator playlists (fine for "AIDJ Test" since Andrew owns it); (4) existing Dev Mode apps migrated 2026-03-09 — we're past cutoff. Current DTOs (`SpotifyPlaylistDetail.tracks`, `SpotifyPlaylistItem.track`) decode against keys that no longer exist — **that's the real cause of `malformedResponse`**; the three tolerance layers we added never had a chance because the parent keys moved. **Decoder tolerance is the wrong tool for a field rename.** Action: before writing code, run one-shot curl `GET /playlists/3qODTVI1u4G5igH9zmdBh7/items?market=from_token` with Andrew's existing token — 200 + non-empty `items[].item` confirms the path. If it also 403s we're in Extended Quota territory and this decision flips to (c) or (d). |

### Locked Decisions

| # | Decision | Locked | Outcome | Rationale |
|---|----------|--------|---------|-----------|
| D2 | Dev vs prod Spotify Client IDs | 2026-04-21 | **One Client ID.** Single registration in Spotify's dev portal, single redirect URI `aidj://spotify-callback`, no xcconfig. | Hobby-scale app — rate limits a non-issue, xcconfig is ceremony for a one-person app. Revisit only if the app ships on the App Store (then split dev/prod via xcconfig and add `aidj-dev://spotify-callback`). |
| D3 | On-device PKCE only vs token-swap server | 2026-04-21 | **On-device PKCE only.** `SPTSessionManager` does the PKCE handshake; access/refresh tokens persist to Keychain. No token-swap server. | PKCE obviates the need for a Client Secret, so a token-swap server adds infrastructure without adding security for this flow. Token-swap is for non-PKCE Authorization Code, which we're not using. Phase 2a uses `ASWebAuthenticationSession` for PKCE since `SPTSessionManager` is Phase 2b (iOS SDK); they share the same persisted token shape. |
| D4 | macOS Spotify path | 2026-04-21 | **Ship "iOS-only" alert.** macOS Spotify playback surfaces a friendly "Spotify playback is iOS-only" alert via the existing `notSupportedYet`-style catch path; no WKWebView in 2b. | Resolved transitively by D6a. WKWebView + Web Playback SDK spike is a day-plus DRM/WebKit unknown; deferred to Phase 4 where it can get its own plan doc. Keeps 2b iOS-focused and smoke-attributable. **Cross-ref K21** — the WKWebView path is the *only* remaining way for AIDJ to stream Spotify audio in-process on any Apple platform (iOS has no such path; SPTAppRemote requires the Spotify app); locking this context so Phase 4 starts from the right premise. |
| D6 | macOS Spotify behavior in Phase 2b | 2026-04-21 | **(a) Friendly "iOS-only" alert on macOS Spotify playback.** `SpotifyService.play(_:)` on macOS throws a typed error; `LibraryViewModel`/`NowPlayingViewModel` catch path surfaces a dismissible alert identical in shape to the 2a Phase-2b-gate alert. No WKWebView spike in 2b. | Option (b) is a day-plus DRM/WebKit spike with independent risk; does not belong inside a physical-iPhone smoke window. Resolving (a) also closes D4. Unblocks 2b.1 scope (no macOS SDK link concerns) and 2b.4 alert copy. |
| D7 | Scope of Phase 2b polish commit | 2026-04-21 | **(a) Separate polish block after 2b.5 smoke closes** (labeled 2c-polish when it opens). Excluded from 2b: K17 AttributeGraph cycle investigation, Library unauth empty-state alignment, K5 dead `voicePreset` cleanup. | Don't pollute physical-iPhone smoke with UI polish — keeps SDK-integration regressions attributable. Note: brief referenced `ITMediaItem` / `MPMediaEntityProperty` warnings "in the Phase 1 smoke log"; grep turns up zero matches in the repo, so treating as system-framework log noise unless Andrew produces the exact log line. Not tracking as an issue. |

---

## 6. Known Issues / Tech Debt

| # | Title | Severity | Note |
|---|-------|----------|------|
| K1 | `FakeAudioGraph` main-actor conformance | resolved | Closed in `c325b56`. Cause-chain was three stacked: (1) `AIDJTests` target missing `GENERATE_INFOPLIST_FILE: YES` in `project.yml` — codesign failed before Swift compiled, masking everything under it; (2) `FakeAudioGraph` was `@MainActor` while `AudioGraphProtocol.stop()` is nonisolated — dropped `@MainActor`, added `@unchecked Sendable`; (3) two stale assertions from Phase 1a/earlier refactors (`track-appleMusic-xyz` provider-namespaced IDs; `stopCallCount == 2` because `replaceQueue` already stops). Lesson: when a test target has been red for weeks, assume stacked failures — don't declare "fixed" after fixing one layer. |
| K2 | `@preconcurrency import FluidAudio` | low | FluidAudio isn't Swift 6 strict-concurrency-clean. Per-file relaxation acceptable; revisit if FluidAudio updates |
| K3 | No per-voice mood descriptors for Kokoro | low | Upstream doesn't publish them |
| K4 | App-bundle Spotify Client ID would leak | low | Not relevant until Spotify ships. Documented in Spotify plan §3c |
| K5 | `DJPersona.voicePreset` is dead weight | low | Persona carries a `voicePreset` but `SettingsViewModel.effectiveVoiceIdentifier` ignores it when the user has picked a voice. Kept as seed-default for built-ins only. |
| K6 | `.help(...)` used as iOS accessibility hint | low | Historical recurrence caught in HIG Commit 1 (`bfad5e5`). `.help` is macOS-only; iOS VoiceOver needs `.accessibilityLabel`. Grep `.help(` periodically. |
| K7 | `RSSFetcher.fetchHeadlines().first` always picks top | low | After News Commits A+B shipped, repetition can still occur across segments from the same feed. See Backlog entry for rotation options. |
| K8 | `voiceIdentifier` is device-local, but iCloud-synced | low | AVSpeech voice identifiers are per-device-install. When synced to a device that lacks the voice, `effectiveVoiceIdentifier` silently falls back to persona preset. Log a `Log.settings.info` for diagnosability. |
| K9 | FluidAudio exposes no download-progress callback | low | `KokoroTtsManager.initialize()` is opaque. Keep indeterminate spinner until FluidAudio publishes a progress API. |
| K10 | `xcodegen generate` was stripping entitlements + Info.plist keys | resolved | Fixed in `dd6ff07` by pinning both files' properties in `project.yml`. Keep an eye if new entitlements are added — they must be declared in project.yml to survive regen. |
| K11 | Empty-cache poison pattern | resolved | Fixed in `5c09db9` — empty fetch results no longer save to cache. Pattern worth remembering for any future cache-backed feature. |
| K12 | `MusicProviderService` still leaks `MusicKit.Artwork` | resolved | Fixed in `8bb13d3` — protocol surface unified on `ProviderArtwork?`; `MusicKit` import removed from `NowPlayingViewModel`, `NowPlayingView`, `MiniPlayerBar`. |
| K13 | Build-system errors mask logic errors | low | Surfaced during K1: codesign / Info.plist failure happens before Swift compiles, so any compile error (even in the same target) is hidden until the build-system error clears. Any time a test target goes red after a long quiet period, check `project.yml` target settings against working targets before debugging the Swift error. Applies to `GENERATE_INFOPLIST_FILE`, `PRODUCT_BUNDLE_IDENTIFIER`, signing, deployment target. |
| K14 | Test suite staleness after refactor waves | low | Two assertions drifted silently over the 6-week window when `xcodebuild test` was red. Anytime a protocol-level contract shifts (naming, ID shape, call-count semantics), sweep `AIDJTests/` in the same commit even if the suite isn't runnable — the delta gets harder to reconstruct later. Could be automated with a pre-commit grep, but not worth it yet. |
| K15 | Transport transitions must bump `playbackGeneration` + stop `audioGraph` | med | Surfaced by `688bbf8`. Two separate invariants live in `PlaybackCoordinator` that every transport method must respect: (1) any state change that ends the current segment (skip, previous, replaceQueue, stop) must call `audioGraph.stop()` and bump `playbackGeneration` at the top — otherwise an in-flight DJ segment keeps playing over the new track; (2) any method that transitions into `.playing` (play from idle, resume from pause, start-next) must set `state = .playing` **before** entering `monitorTrackUntilEnd`, since the monitor exits immediately on `state != .playing`. Both were silently wrong because the test suite was red (K1) and manual smoke didn't exercise pause→resume or mid-segment skip. Any future transport work (Spotify playback in 2b, macOS in 2c/2d) must explicitly check both invariants — add a comment block at the top of `PlaybackCoordinator` listing the two rules. Consider a unit test per transport method asserting generation bump + state transition ordering once 2b lands. |
| K16 | macOS 26 `ASWebAuthenticationSession` libdispatch crash | med | Surfaced during Phase 2a smoke. On macOS 26 (Apple Silicon), `ASWebAuthenticationSession.start()` returns `true`, then crashes inside Apple's framework with a `libdispatch` assertion before the completion handler fires. Reproducible across retention tweaks and main-actor anchor resolution; the crash is inside framework code, not our code. **Workaround landed `4b5e97b`:** on macOS only, Spotify auth uses `NSWorkspace.open(_:)` + SwiftUI `.onOpenURL` instead of the session. iOS still uses `ASWebAuthenticationSession` and works. **Lesson for Phase 2b:** `SPTSessionManager` (Spotify iOS SDK) uses the session under the hood on iOS — we don't hit the bug there — but anything that shares the presentation-layer route on macOS should route through `NSWorkspace.open` instead. Worth filing a Feedback Assistant report against macOS 26 with the diagnostic logs from `a2c1516` + `564037f`. |
| K17 | `AttributeGraph: cycle detected` console warnings | low | New in `4b5e97b` / `2854cd6`. Likely from the `.onOpenURL` + `.onChange(of: settings.browseProvider)` binding combo on Settings / Library views — SwiftUI's attribute graph detects a cycle between the URL handler writing to `settings` and the `.onChange` observer reading it. Warnings only, no user-visible UI hang or wrong state observed in smoke. Not blocking. If UI hangs or infinite layout passes start appearing, first suspect: split the callback into a detached Task or mediate through a coordinator method rather than writing settings directly from `.onOpenURL`. |
| K18 | Spotify Web API Feb-2026 Dev Mode migration broke our DTOs | high | **Effective 2026-02-11 for new apps, 2026-03-09 for existing Dev Mode apps** (we're past cutoff). Official migration guide: `https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide`. Confirmed changes that affect us: (1) `GET /playlists/{id}/tracks` deprecated → `GET /playlists/{id}/items`; returns 403 on the old path, which is what Andrew observed. (2) Playlist JSON shape: top-level `tracks` field renamed to `items`; nested `tracks.items` → `items.items`; per-item `track` renamed to `item`. (3) `items` only returned for playlists the user owns or collaborates on — other playlists return metadata only. (4) Also impacted (not currently on us but will be soon): `GET /tracks`, `GET /albums`, `GET /artists`, `GET /episodes`, `GET /shows`, `GET /audiobooks`, `GET /chapters` batch endpoints removed — must fetch individually; `GET /search` limit capped at 10 (was 50); batch save/remove/follow endpoints replaced by `PUT/DELETE /me/library`; `available_markets`, `popularity`, `external_ids`, `label`, plus `/me` fields (`email`, `country`, `product`, etc.) removed. **Files to update when D8(a) is approved:** `AIDJ/Services/SpotifyAPIClient.swift` — rename `SpotifyPlaylistDetail.tracks` → `items`; rename `SpotifyPlaylistItem.track` → `item`; update `CodingKeys` accordingly; change path from `playlists/\(id)/tracks` to `playlists/\(id)/items`; delete or gate the workaround in `playlistDetail(...)` once the direct endpoint returns 200; add handling for "absent items" on non-owned playlists. The three tolerance layers (`try?`-decode, `SpotifyPageSkip`, all-optional `SpotifyTrack` fields) can stay — they're still useful for podcast episodes / local files — but they're not the fix. |
| K19 | Decoder tolerance is the wrong tool for a field rename | med | Lesson from K18. When a 200 response produces `malformedResponse`, **dump the raw body first**, before iterating on tolerance layers. Andrew added raw-body logging at `b81a5ba` after three layers of tolerance patches had already failed — it should have been the first diagnostic. Corollary: if a `try?`-decode fallback turns a populated response into nils, the next commit's logs will look like "endpoint works, no tracks decoded" and mask the shape mismatch. When decode fails on valid JSON, suspect a renamed parent key before a malformed leaf. |
| K20 | Vendor APIs churn; annotate endpoints with last-verified date | low | Three Spotify Web API churn events have hit this project in <18 months: Nov 2024 (algorithmic playlist restrictions), Feb 2026 (endpoint renames + Dev Mode app limits), March 2026 (migration deadline + field reverts). Proposal: annotate each Spotify endpoint call site with `// Verified against Spotify Web API docs YYYY-MM-DD`. When a 4xx appears, the annotation is the first place to look — check the vendor changelog between that date and today. Cost: one line per endpoint. Benefit: next breakage gets diagnosed in minutes, not hours. Applies also to any future Spotify endpoint additions. Also consider a quarterly "check Spotify changelog" calendar nudge while the provider remains in Dev Mode. |
| K21 | Spotify iOS has no standalone-playback path for third-party apps | **locked (high)** | **Verdict locked 2026-04-21.** No first-party or sanctioned SDK allows a third-party iOS app on the App Store to stream Spotify audio in-process (without the Spotify app installed and running). Four pillars, stable 2017–2026: (1) **SPTAppRemote is IPC**, not a streaming SDK — it forwards commands to the Spotify app and streams player state back; no audio buffers cross the boundary. Documented as such since the iOS SDK's 2017 release. (2) **Web Playback SDK is browser JavaScript** requiring EME (Widevine on Chromium, FairPlay on WebKit). Running it in `WKWebView` on iOS has long-known issues: autoplay gating, DRM cert chain, audio-session handoff, no background playback. Spotify does not officially support WKWebView embedding. (3) **Spotify Connect Partner Program** is a hardware-OEM licensing arrangement (Sonos, receivers, smart speakers, TVs) — not a public SDK, not available to App Store app developers. No Swift/iOS API surface exists. (4) **Spotify Developer Terms §III.2** (and successor clauses) prohibit streaming, re-streaming, proxying, or accessing raw audio. Violating gets the Client ID revoked — **djay (Algoriddim) lost its special-access Spotify integration July 2020** when Spotify revoked the partnership; djay, Serato DJ, and Traktor DJ have all shipped without Spotify since. No DJ or media app has regained it. **Direction of travel: tighter, not looser.** Nov 2024 removed audio-features/recommendations/related-artists for new apps; Feb 2026 renamed endpoints + capped Dev Mode apps (see K18). A "standalone Spotify playback" reversal in 2025–2026 would be a public reversal with public signal — none has appeared. **The librespot trap** (reverse-engineered open-source client): exists, gets accounts banned periodically, won't survive App Store review (uses private Spotify protocol, no entitled use), LGPL/GPL license is incompatible with closed-source distribution, and is a ToS violation. Not a path. **What remains possible for AIDJ:** (A) SPTAppRemote (Spotify app required) — current Phase 2b path; (B) Apple Music only on macOS (Phase 2b scope per D6); (C) WKWebView + Web Playback SDK on macOS only — day-plus DRM spike, pushed to Phase 4 (see D4). **What the tracker owes future readers:** before re-researching this, require Andrew to produce a named App Store app that plays Spotify without the Spotify app installed. Unnamed rumor doesn't reopen this. 80%+ probability any named candidate is using SPTAppRemote under the hood; the remaining 20% is checkable in minutes by running the candidate without the Spotify app on the device. Cross-ref: D4 (macOS Spotify path), `docs/superpowers/plans/2026-04-20-spotify-support.md` §2 (SDK choice rationale). |

---

## 7. Plans & Specs

| Doc | Summary |
|-----|---------|
| `docs/superpowers/specs/2026-04-17-ai-dj-design.md` | Original architecture spec for the AI DJ MVP |
| `docs/superpowers/plans/2026-04-20-spotify-support.md` | Phased implementation plan for adding Spotify as a second music provider |

---

## 8. Phase 2a Commit Block — Spotify Read-Only (COMPLETE)

Split of plan §9 Phase 2a into independently commit-able slices. **All 5 commits shipped 2026-04-21, green build on macOS + iOS, 40 tests pass.** Ship gate met.

| # | Commit title | Status |
|---|--------------|--------|
| 2a.1 | Spotify PKCE auth coordinator + Keychain keys | **Shipped `d69eadc`** |
| 2a.2a | `SpotifyAPIClient` actor + URLProtocol-mocked tests | **Shipped `9dd5d39`** |
| 2a.2b | Wire real Spotify Client ID | **Shipped `c9b0583`** |
| 2a.3 | `SpotifyService` conforming to `MusicProviderService` | **Shipped `ac8a5ed`** |
| 2a.4 | `browseProvider` persistence + Settings Music Services row | **Shipped `8a1eeee`** |
| 2a.5 | Library segmented provider picker + playback gate | **Shipped `10fc7f3`** |

**Ship gate met (plan §9 Phase 2a):** user can connect Spotify, browse playlists, search catalog; playback surfaces a friendly "coming in Phase 2b" alert.

**Smoke gate closed 2026-04-21** — PKCE round-trip on macOS (via NSWorkspace pivot), Library picker flip, Spotify playlist population, Apple Music untouched, Phase 2b alert dismissible. Seven fix commits during smoke: `8d926fd` → `51b1080` → `a2c1516` → `564037f` → `4b5e97b` → `2854cd6` → `3c968fc`.

**Lessons logged for the next phase block:**

1. **`SPTSessionManager` isn't Phase 2a.** It's part of the iOS SDK, which lands in 2b. 2a used `ASWebAuthenticationSession` + manual PKCE. Token storage shape is identical, so 2b swaps the handshake without touching Keychain. Plan text still says otherwise — don't re-read the plan literally when starting 2b.
2. **Split Andrew-blocked commits aggressively.** Original 2a.2 lumped the API client with the Client ID swap and blocked the whole slice on Andrew. Splitting into 2a.2a (code+tests, placeholder ID) + 2a.2b (one-line swap) kept forward motion for hours. Apply this pattern whenever a single external dep is the only blocker.
3. **Router shape held up.** `MusicProviderRouter` shipped in Phase 1c (`3d09898`) for one provider; registering the second in 2a.3 was a clean extension with no shape changes. Worth imitating for Spotify playback (2b) and macOS (2c/2d) — if a shape change is needed at 2b, treat it as a yellow flag.
4. **`notSupportedYet` interception happens at the UI, not the service.** 2a.3 throws at the service boundary; 2a.5 catches it in `LibraryViewModel` and shows the friendly message — but 2a.5 initially failed to surface the copy, yielding a dead tap until `3c968fc`. **Corollary:** when a service throws a typed error meant for UI interception, the interception code path needs its own smoke check in the same commit.
5. **macOS 26 auth presentation is load-bearing-bespoke.** `ASWebAuthenticationSession` crashes inside the framework on macOS 26 (K16). Any cross-platform auth flow now needs a macOS-specific route through `NSWorkspace.open` + `.onOpenURL`. Budget the split upfront for 2b/2c rather than discovering it in smoke.
6. **"Connected" chips must be probed, not inferred.** Keychain presence alone isn't a live-session signal (K17 predecessor, fixed in `2854cd6`). Any status indicator tied to an external auth should do a cheap `/me` probe on appear — same pattern will apply to Apple Music if we ever show a status chip there.

---

## 9. Phase 2b Commit Block — Spotify iOS SDK Playback (IN PROGRESS)

Mirrors §8's format. Full reasoning in `docs/superpowers/plans/2026-04-20-spotify-support.md` §12 addendum. Supersedes that doc's §9 Phase 2b paragraph.

| # | Commit title | Owner | Status | Deps |
|---|--------------|-------|--------|------|
| 2b.0 | Plan reconciliation — §12 addendum | Claude (PM) | **Done 2026-04-21** | — |
| 2b.1 | Spotify SDK SPM package + `LSApplicationQueriesSchemes` + xcodegen regen | Claude | **In flight** | D6 locked (a) |
| 2b.2 | `SpotifyPlayback` iOS helper — SPTSessionManager + SPTAppRemote lifecycle, no service integration | Claude | Blocked | 2b.1 + Andrew: dev-portal check + Spotify app installed on test iPhone |
| 2b.3 | Swap iOS PKCE handshake to SPTSessionManager; macOS keeps NSWorkspace path | Claude | Blocked | 2b.2 |
| 2b.4 | `SpotifyService` playback methods wired to SPTAppRemote (iOS) + Premium gate alert | Claude | Blocked | 2b.2, 2b.3 |
| 2b.5 | `AIDJApp` URL forwarding refinements + foreground reconnect + SPTAppRemote position polling | Claude | Blocked | 2b.4 |
| 2b.6 (optional) | Regression tests: K15 playbackGeneration + state-ordering for Spotify path | Claude | Blocked | 2b.5 |

**Ship gate for plan §9 Phase 2b:** physical iPhone smoke passes — Spotify playlist tap starts audio, pause/resume/skip work, DJ speaks between tracks, Apple Music untouched. Non-Premium account surfaces a friendly typed error. macOS Spotify tap surfaces "iOS-only" alert (D6a).

**Andrew-owned prereqs** (see §12c):
- Spotify Premium account — **Confirmed 2026-04-21.**
- Physical iPhone (iOS 26) with Spotify app — blocks 2b.2, 2b.4, 2b.5. **Not yet confirmed.**
- Spotify dev portal: confirm `aidj://spotify-callback` still registered + add iOS Bundle ID `com.andrewporzio.aidj` under App iOS SDK — blocks 2b.2 (not 2b.1 — packaging commit doesn't hit the portal at runtime). **Not yet confirmed.**
- Second Spotify account (non-Premium) optional for 2b.4 negative-path verification.

**Non-goals for 2b** (per D6, D7):
- macOS Spotify playback — throws continue under `#if !os(iOS)`; WKWebView spike pushed to Phase 4.
- UI polish / K17 AttributeGraph cycle investigation / Library unauth empty-state alignment — separate polish block after 2b.5 smoke closes.

### 9a. Unplanned slice inserted 2026-04-21: Spotify Feb-2026 API Migration

Discovered during 2a/2b smoke — Spotify's Feb-2026 Dev Mode migration renamed endpoints + fields, breaking our playlist-tracks read (403 on old endpoint, decoder `malformedResponse` on `/playlists/{id}` fallback because parent JSON keys were renamed). See K18, K19, K20 and D8.

Proposed slice name: **2b.0b — Spotify Feb-2026 DTO + endpoint migration.** Blocks **all** Spotify playlist-content features (browse, playback prep, DJ-between-tracks), so it jumps the 2b queue — 2b.1 can continue in parallel since it's purely packaging, but 2b.2+ can't do a useful smoke without the correct track data.

Gate before writing code: Andrew runs `curl -H "Authorization: Bearer $TOKEN" 'https://api.spotify.com/v1/playlists/3qODTVI1u4G5igH9zmdBh7/items?market=from_token'` against his existing `aporzio1` token. 200 + non-empty `items[].item` → implement D8(a). 403 or empty → decision flips to D8(c) or (d), which is a materially different scope and deserves its own PM review.
