# Patter — Project Tracker

**Owner:** Andrew P
**PM Agent:** `patter-pm` (see `.claude/agents/patter-pm.md`)
**Last updated:** 2026-04-23 — **App renamed from "AI DJ" → "Patter".** Bundle ID `com.andrewporzio.aidj` → `com.andrewporzio.patter`, module `AIDJ` → `Patter`, scheme + folders + display name + Info.plist + log subsystem + Keychain fallback all updated; old `AI DJ.xcodeproj` deleted, regenerated as `Patter.xcodeproj`. PM agent file renamed to `patter-pm.md`. 25 tests still pass on macOS; iOS Simulator build green. **Note:** N1.3 (article-link button) is still paused mid-implementation — see §3, the rename did not progress that task. Yesterday's context: N1.1 + N1.2 shipped; Spotify integration withdrawn per K21 with `ca23170`.

---

## 1. Current State

- **Platforms:** iOS 26 / macOS 26, Apple Silicon only
- **Stack:** Swift 6.0 strict concurrency, SwiftUI, MusicKit, AVFoundation, Foundation Models
- **Version:** 1.0 (CFBundleVersion 1)
- **App name:** Patter (renamed from "AI DJ" on 2026-04-23). Bundle ID `com.andrewporzio.patter`. Module name `Patter`. Source folders `Patter/` + `PatterTests/`. **App Store Connect listing name: "Patter: Your DJ"** — bare "Patter" was reserved by another developer in Apple's broader name pool (not visible in App Store search, common for pre-launch reservations). Home-screen `CFBundleDisplayName` stays as just "Patter" — listing name only shows in App Store search/store page. Top-level CloudDocs working dir is still `AI DJ/` (not yet renamed — leave for a clean session to avoid disrupting active Claude Code state and the auto-memory path). Spec doc filenames retain the original `ai-dj` codename (historical record).
- **Core capability:** Plays Apple Music content (playlists, albums, stations) with an AI DJ narrating between tracks; can pull RSS news headlines for commentary
- **TTS providers (pluggable via `DJVoiceRouter`):** Device Voices (AVSpeechSynthesizer), OpenAI cloud TTS, Kokoro on-device (FluidAudio CoreML) with launch-time warm-up
- **Music providers:** Apple Music only. `Track.MusicProviderID` is a single-case enum (`.appleMusic`). `MusicProviderRouter` remains as a single-provider wrapper (`init(appleMusic:)`) so a future provider with an actual streaming SDK can slot in without re-threading the coordinator + VM call sites. `MusicProviderService` protocol, `ProviderAuthStatus`, `ProviderArtwork`, `PlayableItem` provider-namespaced IDs, and `LibrarySectionCache` provider-scoped keys all retained intentionally.
- **UI tabs:** Library (default) / Queue / Settings, plus persistent MiniPlayerBar (2-row with progress slider, shuffle/repeat, thumbs feedback) and an expandable Now Playing sheet. Library has no segmented provider picker (single provider).
- **Library landing:** Recently Played + Made for You (playlists, albums, stations) with stale-while-revalidate disk cache + pull-to-refresh. All tiles tap-to-play.
- **Settings → Music Services:** reduced to a single "Apple Music: Authorized" status line.
- **Onboarding:** 4-step first-launch wizard (Name → DJ + Voice → News → iCloud) with migration auto-completion for existing users
- **iCloud sync:** `CloudSyncService` mirrors curated Settings keys to NSUbiquitousKeyValueStore; opt-in toggle + hot-reload across devices
- **Personas:** Multiple personas with built-in presets + user-created custom personas; DJ frequency + News frequency pickers
- **Feedback:** Thumbs-up / thumbs-down per track injected into DJ prompt

---

## 2. Shipped

Reverse-chronological. Commit hashes are 7-char.

### 2026-04-23
- **App rename: "AI DJ" → "Patter".** Researched 6 candidate names against App Store collisions, trademark exposure, domain availability; "Patter" won on concept fit (it's the radio-DJ term for between-song chatter — the app's signature feature) and clean availability (zero music apps in the App Store, no `.app`/`.fm` squatters, no obvious TM heat in software/music). Folder rename: `AIDJ/` → `Patter/`, `AIDJTests/` → `PatterTests/`, `AIDJ.entitlements` → `Patter.entitlements`, `AIDJApp.swift` → `PatterApp.swift`, `aidj-pm.md` → `patter-pm.md`. Code edits: module qualifier `AIDJ.Track` → `Patter.Track` across 11 files; `@testable import AIDJ` → `@testable import Patter` across 5 test files; `@main struct AIDJApp` → `PatterApp`; comment refs to `AIDJApp` updated. Identifier edits: bundle ID `com.andrewporzio.aidj` → `com.andrewporzio.patter`; Log subsystem + Keychain service-id fallback aligned. UI strings: `CFBundleDisplayName`, `NSAppleMusicUsageDescription`, `NavigationStack` title, onboarding gate copy, settings reset-confirmation copy. project.yml fully rewritten (target name, scheme name, sources path, entitlements path, info path, TEST_HOST). `xcodegen generate` produced `Patter.xcodeproj`; old `AI DJ.xcodeproj` removed. `OpenAIDJVoice` deliberately preserved (it's "OpenAI" + "DJVoice", not "AIDJ"). 25 tests pass on macOS, iOS Simulator builds green. Process: GitHub repo rename + Apple Developer Portal + App Store Connect setup are user actions (see §3).

### 2026-04-22
- `ca23170` — **Spotify integration dropped; Apple Music only (Option B).** 2,141 lines deleted, 61 added. Removed `SpotifyAuth.swift`, `SpotifyAPIClient.swift`, `SpotifyService.swift`, `SpotifyAPIClientTests.swift`, `SpotifyAuthCoordinatorTests.swift`; removed SpotifyiOS SPM package, `aidj://` URL scheme, `LSApplicationQueriesSchemes` from `project.yml`. `Track.MusicProviderID` now single-case (`.appleMusic`); `MusicProviderRouter` is `init(appleMusic:)`-only; `MusicProviderService` protocol dropped `handleAuthCallback(_:)` and `validateAuthorization()`. Settings "Music Services" reduced to status line; Library lost segmented picker. Router abstraction + provider-neutral types retained as future scaffolding. 25 tests pass, green on macOS + iOS. Rationale locked in K21.

### 2026-04-21
- `3c968fc` — Phase 2b playback gate surfaces a dismissible alert on Spotify track tap. *(Withdrawn with `ca23170` — see §8.)*
- `2854cd6` — `validateAuthorization()` probe on Settings appear to clear stale "Connected" state. *(Withdrawn.)*
- `4b5e97b` — **macOS Spotify auth pivot** — swapped `ASWebAuthenticationSession` for `NSWorkspace.open(_:)` + `.onOpenURL` on macOS (K16 workaround). *(Withdrawn.)*
- `564037f` — Diagnostic: log ASWebAuthenticationSession presentation anchor. *(Withdrawn.)*
- `a2c1516` — Diagnostic: trace `beginAuthFlow()` + retain session past method return. *(Withdrawn.)*
- `51b1080` — Capture presentation anchor on MainActor for PKCE. *(Withdrawn.)*
- `8d926fd` — First (unsuccessful) attempt at libdispatch crash fix. *(Withdrawn.)*
- `688bbf8` — Phase 1 smoke-test regression fixes. **Kept** — two real `PlaybackCoordinator` bugs unrelated to Spotify (K15 invariants).
- `10fc7f3` — Phase 2a.5: Library segmented provider picker. *(Withdrawn.)*
- `8a1eeee` — Phase 2a.4: `browseProvider` persistence + Settings Music Services row. *(Withdrawn.)*
- `ac8a5ed` — Phase 2a.3: `SpotifyService` conforming to `MusicProviderService`. *(Withdrawn.)*
- `c9b0583` — Phase 2a.2b: real Spotify Client ID. *(Withdrawn.)*
- `9dd5d39` — Phase 2a.2a: `SpotifyAPIClient` actor + URLProtocol tests. *(Withdrawn.)*
- `d69eadc` — Phase 2a.1: Spotify PKCE auth coordinator + Keychain keys. *(Withdrawn.)*
- `c325b56` — K1 closed: test suite green after Info.plist + main-actor + stale-assertion fixes. **Kept — unrelated to Spotify.**
- `3d09898` — Phase 1c: introduced `MusicProviderRouter` (`@MainActor final`). **Kept — retained post-rip as future-provider scaffolding.**
- `8bb13d3` — Phase 1b: provider-neutral `ProviderArtwork`. **Kept.**
- `79df4af` — Phase 1a: renamed `MusicKitServiceProtocol` → `MusicProviderService`; `PlayableItem.id` namespaced by `providerID`. **Kept.**
- `686a818` — Tracker sweep.
- `11ca3ca` — Station playback now shows track info + transport works.
- `48b31bf` — Warm up Kokoro at launch; MiniPlayerBar indicator distinguishes "Loading" from "Downloading".
- `b8a0f95` — `replaceQueue` now stops in-flight playback so station switches don't overlap.
- `3eb85b0` — Wire station playback so Made for You cards are all tappable (playlists, albums, stations).
- `5c09db9` — Don't let empty cache poison Made for You for 30 min.
- `7bb16a2` — Made for You surfaces albums + stations, not just playlists.
- `1c5dfed` — Cache Recently Played + Made for You with stale-while-revalidate.
- `a432220` — Spell out initialisms (GPT, NPR, BBC, etc.) so TTS doesn't say "gept".
- `5eb5828` — Download indicator condition fix.
- `125b685` — Download indicator now actually appears + tone down AI-flowery DJ.
- `efa3934` — MiniPlayerBar Kokoro download indicator.
- `846252f` — Merge wizard DJ + Voice steps into a single page.
- `80b2f9f` — Reset Onboarding now actually shows the wizard next launch.
- `262566f` — Onboarding wizard now includes voice provider + voice.
- `d08228b` — Reset Onboarding now confirms + tells you it worked.
- `dfa6691` — Onboarding Commit B: first-launch 4-step wizard.
- `dd6ff07` — Onboarding Commit A: iCloud sync for Settings + RSS feeds.
- `b154f0b` — Stop hiding persona name from VoiceOver on Settings row.
- `664046b` — iOS tab bar was obscured by MiniPlayerBar — move inset per-tab.
- `05303a9` — iOS full-screen launch + orientations + Kokoro sending warning fix.
- `5804abd` — Stop DJ hallucinating stations + looping one headline.
- `9e38a5c` — Stop double-gating news.
- `fb70f38` — Pause then play resumes in place instead of restarting track.
- `fe0cc65` — Thumbs on MiniPlayerBar (Phase 3 of MiniPlayerBar work).
- `ee48a67` — News frequency slider.
- `a7afe2a` — News pipeline diagnostics.
- `c652952` — Persist DEVELOPMENT_TEAM in project.yml.
- `2fdaaf4` — HIG P2 — normalize off-grid spacing.
- `bfad5e5` — HIG P1 — tap targets, a11y labels, destructive confirmation.
- `2134b41` — Thumbs-up / thumbs-down track feedback.
- `a63e513` — MiniPlayerBar shuffle + repeat controls.
- `66ad02e` — MiniPlayerBar progress slider + 2-row layout.
- `68a67d7` — DJ frequency setting.
- `eb808d6` — Multiple DJ personas with built-in presets.
- `8705b17` — Editable DJ persona — name + instructions.
- `72246a0` — Register AppIcon for macOS.
- `2b00f39` — Cmd+, opens Settings in a separate window on macOS.
- `d0e29a7` — Skip `playerNode.stop` on same-format segments.
- `844dfac` — Library landing page — Recommendations section (Phase 2).

### 2026-04-20
- `290263b` — Library landing page — Recently Played section (Phase 1).
- `00041d3` — Grounded PM agent in PMI Talent Triangle + HBR project-management principles.
- `600ffae` — Added AI DJ project-manager agent and tracker.
- `c42dc1d` — Playlist detail view + shuffle button + OpenAI voice descriptors.
- `946181a` — Spotify support implementation plan committed (docs only). *(Plan withdrawn 2026-04-22 — see §7.)*
- `9fd34cf` — Kokoro voice preview in Settings; trash-can delete on RSS rows.
- `423b27a` — Redesigned Add Feed row.
- `760e17e` — Manual Download and Remove Model buttons for Kokoro TTS.
- `0ad3c8a` — Phase 2: Kokoro on-device TTS via FluidAudio.

### 2026-04-17
- `0f4422c` — `willAdvance` lead time widened; softened news-hook prompt.
- `3c4df88` — Decode audio into PCM buffer for reliable MP3 playback from OpenAI.
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

### Andrew-side actions to push Patter to TestFlight (2026-04-23)

The code-side rename is complete and committed. Andrew has these manual/portal steps remaining:

1. **Apple Developer Portal** — register the new App ID `com.andrewporzio.patter` with the iCloud capability enabled (the local build used `-allowProvisioningUpdates` to fetch a profile, but the iCloud container may need to be created/named for the new bundle ID). https://developer.apple.com/account/resources/identifiers/list
2. **App Store Connect** — create a new app record for `com.andrewporzio.patter`, name "Patter", primary language English. The old "AI DJ" record (if one exists) becomes orphaned and can be deleted later. https://appstoreconnect.apple.com/
3. **Archive + upload** — in Xcode, Product → Archive (iOS device destination), then Window → Organizer → Distribute App → App Store Connect. First archive will trigger any remaining provisioning prompts.
4. **Domain registration (optional but cheap)** — `patter.app` and `patter.fm` were both unconfigured during research; grab `patter.app` for ~$15/yr to lock the brand before someone else notices.
5. **USPTO TESS check (optional, before any TM filing)** — manual search at `tmsearch.uspto.gov` for "Patter" in Class 9 (software) and Class 41 (entertainment). Patter LLC exists in lifestyle (rewards/dog-walking) — different class, low conflict risk, but worth eyeballing.
6. **Top-level dir rename (later)** — current working dir is still `~/Library/Mobile Documents/com~apple~CloudDocs/Xcode/AI DJ/`. Renaming to `…/Xcode/Patter/` is a separate mini-task — best done in a clean session because it disrupts Claude Code's active project path and the auto-memory directory path.
7. **GitHub repo rename** — `aporzio1/ai-dj` → `aporzio1/patter`. One click via `gh repo rename patter` (Claude can run this with Andrew's confirmation; not done in the rename commit because rename = destructive on shared state).

### N1.3 — Surface news article link in NowPlayingView *(paused 2026-04-22, mid-implementation, nothing edited yet)*

**Status:** Scoped by PM, context gathered, zero files changed. Paused by user request before any edits.

**Prior commits in the N1 arc (already shipped):**
- N1.1 ✅ Persist RSS headline dedup across launches (task #19).
- N1.2 ✅ Richer news briefing — pass RSS `summary` into the DJ prompt + widen word budget to 60–100 for news segments (task #20, see `DJBrain.swift` `stripHTML` + extended news-branch system instructions).

**What N1.3 needs to do:** When a DJ news segment is currently playing, show a "Read article" button on the Now Playing card that opens the headline URL. No MiniPlayerBar affordance (per D11).

**Exact change list (≈30 LOC across 4 files):**

1. `AIDJ/Models/DJSegment.swift` — add `let sourceHeadline: NewsHeadline?` field. `NewsHeadline` is already `Codable & Sendable` so the `DJSegment: Codable, Sendable` conformance still synthesizes.
2. `AIDJ/Services/Producer.swift:316-323` — inside `generateSegment`'s `return DJSegment(...)`, add `sourceHeadline: headline` (the `headline` local is already in scope from line 283).
3. `AIDJ/Views/NowPlayingView.swift` — add a "Read article" `Button` (SF Symbol `safari` or `link`, `.buttonStyle(.bordered)`) rendered below `djBanner` (or as a sibling within `body`) when:
   ```swift
   if case .djSegment(let s) = vm.currentItem,
      s.kind == .news,
      let headline = s.sourceHeadline {
       // Button opens headline.url via Environment(\.openURL)
   }
   ```
   Use `@Environment(\.openURL) private var openURL` at the top of the view. Accessibility label: "Read article in browser". Min 44×44 tap target per HIG.
4. Test constructor updates — three DJSegment construction sites need `sourceHeadline: nil` added:
   - `AIDJTests/Fakes.swift:129`
   - `AIDJTests/ModelsTests.swift:24` (djSegmentCodableRoundTrip)
   - `AIDJTests/ModelsTests.swift:81` (playableItemSegmentIdentity)
   - `AIDJTests/PlaybackCoordinatorTests.swift:83` (djSegmentPlaysViaAudioGraph)

**Validation after edits:**
- `xcodegen generate` not needed — no `project.yml` changes.
- `xcodebuild test -scheme AIDJ -destination 'platform=macOS'` — current baseline is 25 tests passing; new code path is additive.
- Manual smoke on macOS: wait for a news segment, confirm "Read article" button appears during `.news` DJ playback and disappears when the segment ends.

**Then:** commit + push to `aporzio1/ai-dj` (on `main`, per user preference), mark task #21 completed, move N1 to §2 Shipped with today's date.

**Resume prompt to drop in:** "Continue N1.3 — finish the edits listed under §3 of the tracker."

---

## 4. Backlog

Rough priority, top-down.

| # | Item | Summary | Plan |
|---|------|---------|------|
| 1 | **iPhone Phase 1 smoke** | Confirm pure Apple Music playback works cleanly on physical iPhone (iOS 26) — user never smoked Phase 1 on iPhone in isolation before Spotify work began. Covers: onboarding, tab bar, MiniPlayerBar transport, Library landing sections, playlist / album / station tap-to-play, DJ segments between tracks, news commentary, persona switching. Est. small. | — |
| 2 | **Album & station detail views** | Station playback works via tap-to-play; album playback not yet verified end-to-end. Dedicated album-detail (track list, shuffle) and station-detail (now-playing only) views. No longer gated on multi-provider work — router abstraction is already in place. Est. medium. | — |
| 3 | **N1 — Richer DJ news feature (rotation + briefing + link)** | Supersedes K7. Three asks rolled into one scoped item: (a) cross-session dedup of headlines (persist last-N used URLs so DJ never repeats a story across app restarts), (b) richer 2–3-sentence briefing using the RSS `summary` field instead of a one-line mention, (c) surface the article URL in the Now Playing card + MiniPlayerBar while a news segment plays (tap opens in browser). Plumbing: `DJSegment` gains an optional `sourceHeadline: NewsHeadline?`; view layer reads it via the existing `NowPlayingViewModel.currentItem`. No coordinator changes. Split into 3 commits. Est. medium. | docs/superpowers/plans/ (TBD if Andrew wants a plan doc) |
| 4 | **K5 — remove dead `DJPersona.voicePreset`** | Persona carries a `voicePreset` but `SettingsViewModel.effectiveVoiceIdentifier` ignores it when the user has picked a voice. Kept as seed-default for built-ins only. Either fully integrate or fully remove. Est. small. | — |
| 5 | **K17 — investigate `AttributeGraph: cycle detected`** | Console warnings first seen during Spotify work. With `.onOpenURL` + Spotify `.onChange` observers gone, re-run a clean log pass on iPhone and macOS. May be resolved incidentally by `ca23170`; verify before filing further. Est. small. | — |
| 6 | **Kokoro iOS 26 CoreML compile hang** | Unresolved from earlier. CoreML model compile on iOS 26 hangs. Matters only if user enables DJ with Kokoro voice on iPhone. Investigation paths: (a) file FluidAudio upstream issue with exact trace, (b) try different Kokoro model variant, (c) default iOS new installs to System Voice or OpenAI rather than Kokoro, (d) gate Kokoro behind a "Download model" button on iOS only. Est. medium–large depending on path. | — |
| 7 | **Macro tidy-up after Spotify rip** | Sweep for cruft the `ca23170` rip left behind: unused imports, dead helpers, stale comments mentioning Spotify, doc references in `CLAUDE.md` / spec, any `MusicProviderID` usages that silently reduce to `.appleMusic`. Est. small. Low priority but satisfying to clear. | — |
| 8 | Kokoro download indicator — real % progress | Replace indeterminate spinner with `ProgressView(value:)`. Blocked on FluidAudio upstream exposing a progress callback. Revisit quarterly. | — |
| 9 | Onboarding + iCloud sync — Commit C: Keychain iCloud sync (optional) | Flip `kSecAttrSynchronizable = true` on the OpenAI API key. One-line change. Only ship if user explicitly asks; revoked keys silently propagate. Deferred — gauge demand. | — |

---

## 5. Open Decisions

| # | Decision | Options | Current recommendation |
|---|----------|---------|------------------------|
| D9 | N1 seen-headline persistence scope | (a) device-local `UserDefaults` only, (b) `CloudSyncService` iCloud-synced across devices | **(a) device-local.** Listening history is per-device behavior; syncing it means a story the DJ talked about on iPhone gets silently skipped on Mac, which the user would experience as "the news never mentions thing X." Re-hearing a story on a second device is the less-surprising default. Revisit if the user asks. |
| D10 | N1 seen-window retention | (a) permanent (once said, never re-said), (b) time-windowed (e.g. 14 days), (c) capped list (e.g. last 200 URLs) | **(c) capped list of 200 URLs, FIFO.** Permanent grows without bound; time-windowed requires per-URL timestamp storage and still lets a story resurface if the user takes a week off. A 200-URL FIFO naturally rolls old stories out as feed content churns, is one `[String]` in UserDefaults, and at ~100 chars/URL is ~20 KB — trivial. |
| D11 | N1 link surfacing location | (a) Now Playing card only (article button visible when DJ news segment is current), (b) Now Playing + MiniPlayerBar compact affordance, (c) persistent "Recent headlines" list in a new tab/sheet | **(a) for commit 3, keep (c) out of scope.** The DJ segment only plays for ~20–30 s — a prominent "Read article" button on the Now Playing card during that window is enough. A persistent history list is a separate feature and should be its own backlog item if the user wants it. MiniPlayerBar is already dense; avoid adding another control. |
| D12 | N1 briefing length impact on TTS budget | (a) keep segment length flat by shortening non-news banter, (b) let news segments run longer (~30 s vs current ~20 s), (c) add a new `DJFrequency`-like knob | **(b) let news segments run longer.** Current prompt caps 30–70 words; a news brief with context wants ~60–100 words. That's a `DJScriptResponse` guide tweak + a second prompt instruction for news, not a new knob. Kokoro renders ~130 wpm so the delta is 5–10 seconds — acceptable for a news beat. Do NOT add a knob; one more frequency slider bloats Settings. |

### Locked Decisions

| # | Decision | Locked | Outcome | Rationale |
|---|----------|--------|---------|-----------|
| D1 | Merged library view or segmented provider picker? | 2026-04-22 | **Moot.** Withdrew Spotify; single provider, no picker needed. | Resolved by `ca23170`. |
| D2 | Dev vs prod Spotify Client IDs | 2026-04-22 | **Moot** (Spotify withdrawn). Original: one Client ID. | — |
| D3 | On-device PKCE only vs token-swap server | 2026-04-22 | **Moot** (Spotify withdrawn). Original: on-device PKCE only. | — |
| D4 | macOS Spotify path | 2026-04-22 | **Moot** (Spotify withdrawn). Original: ship iOS-only alert, defer WKWebView spike. Cross-ref K21. | — |
| D5 | Update `CLAUDE.md` re: simulator unusability | 2026-04-22 | **Dropped.** No longer relevant without Spotify. | — |
| D6 | macOS Spotify behavior in Phase 2b | 2026-04-22 | **Moot** (Spotify withdrawn). | — |
| D7 | Scope of Phase 2b polish commit | 2026-04-22 | **Moot** (Spotify withdrawn). Constituent items absorbed into backlog (K5, K17, Library empty state). | — |
| D8 | Spotify playlist-tracks 403 + decoder malformedResponse | 2026-04-22 | **Moot** (Spotify withdrawn). Originally recommended hybrid D8(a) migration to `/playlists/{id}/items`. Never executed. | — |

---

## 6. Known Issues / Tech Debt

| # | Title | Severity | Note |
|---|-------|----------|------|
| K1 | `FakeAudioGraph` main-actor conformance | resolved | Closed in `c325b56`. Stacked: Info.plist, main-actor, stale assertions. |
| K2 | `@preconcurrency import FluidAudio` | low | FluidAudio isn't Swift 6 strict-concurrency-clean. Revisit on upstream update. |
| K3 | No per-voice mood descriptors for Kokoro | low | Upstream doesn't publish them. |
| K4 | App-bundle Spotify Client ID would leak | moot | Closed by Spotify withdrawal (`ca23170`). |
| K5 | `DJPersona.voicePreset` is dead weight | low | See Backlog #4. |
| K6 | `.help(...)` used as iOS accessibility hint | low | `.help` is macOS-only; iOS VoiceOver needs `.accessibilityLabel`. Grep `.help(` periodically. |
| K7 | `RSSFetcher.fetchHeadlines().first` always picks top | **superseded 2026-04-21 by N1** | In-memory rotation landed (see `Producer.recentHeadlineURLs`, cap 10) but does not survive app restart, and the broader "richer commentary + user-visible link" ask extends past pure rotation. Tracked as Backlog #3 (N1). |
| K8 | `voiceIdentifier` is device-local, but iCloud-synced | low | AVSpeech voice identifiers are per-device-install. Silent fallback to persona preset on missing. |
| K9 | FluidAudio exposes no download-progress callback | low | See Backlog #8. |
| K10 | `xcodegen generate` was stripping entitlements | resolved | Fixed in `dd6ff07`. New entitlements must be declared in `project.yml` to survive regen. |
| K11 | Empty-cache poison pattern | resolved | Fixed in `5c09db9`. |
| K12 | `MusicProviderService` leaked `MusicKit.Artwork` | resolved | Fixed in `8bb13d3`. |
| K13 | Build-system errors mask logic errors | low | Any time a test target goes red after a long quiet period, check `project.yml` target settings before debugging Swift. |
| K14 | Test suite staleness after refactor waves | low | Anytime a protocol-level contract shifts, sweep `AIDJTests/` in the same commit. |
| K15 | Transport transitions must bump `playbackGeneration` + stop `audioGraph` | med | Two invariants in `PlaybackCoordinator`: (1) end-of-segment transitions must `audioGraph.stop()` + bump generation; (2) transitions into `.playing` must set state before `monitorTrackUntilEnd`. Any future transport work must respect both. |
| K16 | macOS 26 `ASWebAuthenticationSession` libdispatch crash | moot | Closed by Spotify withdrawal (`ca23170`). Was only hit on Spotify auth; no other feature uses `ASWebAuthenticationSession`. Leave note for whoever re-encounters a similar framework crash on macOS 26 — `NSWorkspace.open` + `.onOpenURL` is the workaround. |
| K17 | `AttributeGraph: cycle detected` console warnings | low | Was likely from `.onOpenURL` + `.onChange(of: browseProvider)` binding combo, both gone in `ca23170`. Verify on fresh smoke; if gone, close. See Backlog #5. |
| K18 | Spotify Web API Feb-2026 migration broke DTOs | moot | Closed by Spotify withdrawal (`ca23170`). Retained for archival context: the `/playlists/{id}/items` rename + parent-key shape churn is documented in the official Spotify migration guide (`https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide`). Useful reference if a future non-Spotify provider has similar 4xx → field-rename symptoms. |
| K19 | Decoder tolerance is the wrong tool for a field rename | med | **Kept — general lesson.** When a 200 response produces `malformedResponse`, dump the raw body first. Tolerance layers (`try?`-decode, optional fields) hide renamed parent keys and turn populated responses into silent nils. Applies to any JSON-decoding provider we add in the future. |
| K20 | Vendor APIs churn; annotate endpoints with last-verified date | low | **Kept — general lesson.** Annotate every external-API call site with `// Verified against <vendor> docs YYYY-MM-DD`. First place to look on a 4xx. Applies to OpenAI TTS, any future music-provider REST, any cloud endpoint. |
| K21 | Spotify iOS has no standalone-playback path for third-party apps | **locked (high)** | **Verdict locked 2026-04-21.** No first-party or sanctioned SDK lets a third-party iOS app on the App Store stream Spotify audio in-process. Four pillars: (1) SPTAppRemote is IPC to the Spotify app, not a streaming SDK; (2) Web Playback SDK is browser JS + EME DRM, unsupported in `WKWebView`; (3) Spotify Connect Partner Program is hardware-OEM licensing only; (4) Developer Terms §III.2 prohibits streaming/proxying raw audio — djay lost Spotify July 2020 when the partnership was revoked; djay/Serato DJ/Traktor DJ have all shipped without Spotify since. Direction of travel is tighter, not looser. **Re-opening requires Andrew to produce a named App Store app that plays Spotify without the Spotify app installed** — unnamed rumor doesn't reopen this. 80%+ probability any candidate is SPTAppRemote; remaining 20% checkable in minutes by running the candidate without the Spotify app on-device. Closed out active Spotify work; drove `ca23170` (Option B — rip). |
| K22 | Do vendor-constraint research before starting SDK integration, not after | **high (process)** | **New 2026-04-22.** The Spotify arc cost ~two working days — 11 integration commits (`d69eadc` through `10fc7f3`), 7 smoke-fix commits (`8d926fd` through `3c968fc`), a Feb-2026 API-migration pivot (K18), and ultimately a full rip (`ca23170`). K21 research, which closed the question decisively, could have been run in ~30 minutes before starting Phase 2a and would have prevented the entire arc. **Standing rule going forward:** before starting any vendor-SDK integration (music providers, TTS providers, ASR providers, cloud LLMs with novel auth, any closed-source iOS SDK), the plan doc must include a **Constraints & Direction-of-Travel** section citing primary sources on: (a) what the SDK actually does vs what it appears to do (IPC vs streaming, remote-control vs playback, etc.), (b) vendor ToS restrictions on the intended use, (c) historical precedents — named apps that tried this and what happened, (d) direction of travel over the last 24 months (tightening or loosening). PM agent should flag missing Constraints section as **Hold** on any new SDK plan. Cost to enforce: ~30 min of research per SDK. Cost of skipping: potentially ~2 days per SDK. Applies retroactively — future SDK plans must contain this section. |

---

## 7. Plans & Specs

| Doc | Status | Summary |
|-----|--------|---------|
| `docs/superpowers/specs/2026-04-17-ai-dj-design.md` | active | Original architecture spec for the AI DJ MVP |
| `docs/superpowers/plans/2026-04-20-spotify-support.md` | **WITHDRAWN 2026-04-22 per K21** | Phased implementation plan for adding Spotify as a second music provider. Not deleted — useful historical context for (a) the phased-refactor pattern (Phase 1a/1b/1c + router abstraction shipped successfully and remain in the codebase), (b) the cost of skipping direct-source research (K22), (c) reference if a different music provider is considered in the future. Top-of-doc note added flagging withdrawal. Cross-ref: K21, K22, `ca23170`. |

---

## 8. Withdrawn: Spotify Integration Arc (2026-04-20 – 2026-04-22)

**Status:** Ripped out in `ca23170`. Retained here as an index of commits that shipped to `main` and were subsequently withdrawn, so future readers can trace history without scanning git.

**Withdrawal rationale:** K21 (locked) — no first-party iOS SDK path exists for a third-party App Store app to stream Spotify audio standalone. The SPTAppRemote path requires the user to have the Spotify app installed and running, which breaks the "hands-off radio" product goal. Pivoted to Apple-Music-only rather than ship a compromised experience.

**Phase 1 (refactor) — retained, still in the codebase:**
- `79df4af` — Phase 1a: rename to `MusicProviderService`, provider-namespaced `PlayableItem.id`
- `8bb13d3` — Phase 1b: provider-neutral `ProviderArtwork`
- `3d09898` — Phase 1c: `MusicProviderRouter`

These are the "paid-for" part of the arc. They're valuable abstraction even with one provider and cost nothing to keep.

**Phase 2a (read-only Spotify) — all withdrawn:**
- `d69eadc`, `9dd5d39`, `c9b0583`, `ac8a5ed`, `8a1eeee`, `10fc7f3`

**Phase 2a smoke fixes — all withdrawn:**
- `8d926fd`, `51b1080`, `a2c1516`, `564037f`, `4b5e97b`, `2854cd6`, `3c968fc`

**Phase 2b (SDK playback) — partially shipped before rip, all withdrawn:**
- `6497e5f` (2b.1 — SPM package), `aea38c3` (2b.2 — SPTAppRemote), `d57b3f9` (provider-scope library cache), `e62874c` (playlist diagnostics), `f2d6dbb` (human errors), `0c7de2d` (OAuth scope logging), `4f5381b` (scope persistence), `00c9bb0` (/me user id log), `ed6cdcf` (access probe matrix), `87e5180` (playlist-tracks pivot), `f023332` (tolerant track decoding), `b81a5ba` (raw body logging), `79ce718` (Feb-2026 API migration), `988faced* not applicable, `b1ea2ed` (persist toggles — **retained, unrelated**), `7fe11a6` (SPTAppRemote open-Spotify failure), `baed2f0` (SPTSessionManager 2b.3).

**Rip commit:**
- `ca23170` — refactor: drop Spotify integration, Apple Music only (Option B). 2,141 lines deleted.

**Lessons captured:** K21 (constraint), K22 (process rule), K18/K19/K20 (retained as general API-integration lessons).

**Scaffolding retained from the arc:**
- `MusicProviderRouter` (`@MainActor final`) — single-provider wrapper today, ready for a future provider
- `MusicProviderService` protocol — minus `handleAuthCallback(_:)` and `validateAuthorization()` (both Spotify-shaped)
- `ProviderAuthStatus` enum
- `ProviderArtwork` enum — only `.musicKit` case populated; URL-based case remains a plausible future shape
- `PlayableItem.id` provider-namespaced format (`track-appleMusic-<id>`)
- `LibrarySectionCache` provider-scoped keys
