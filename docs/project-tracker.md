# AI DJ — Project Tracker

**Owner:** Andrew P
**PM Agent:** `aidj-pm` (see `.claude/agents/aidj-pm.md`)
**Last updated:** 2026-04-22 — **Spotify integration withdrawn per K21; Apple Music is the sole provider.** Commit `ca23170` ripped out 2,141 lines of Spotify code (auth coordinator, API client, service, 18 tests, SPM package, URL scheme) after K21 research confirmed no first-party iOS path exists for a third-party app to stream Spotify audio standalone. The `MusicProviderRouter` / `MusicProviderService` abstraction stays — it's free-tier scaffolding for a future provider with a real streaming SDK. 25 tests pass; green on macOS + iOS. Process lesson captured as K22: primary-source vendor research before any SDK integration, not after 11 integration + 20+ chase commits.

---

## 1. Current State

- **Platforms:** iOS 26 / macOS 26, Apple Silicon only
- **Stack:** Swift 6.0 strict concurrency, SwiftUI, MusicKit, AVFoundation, Foundation Models
- **Version:** 1.0 (CFBundleVersion 1)
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

*(Nothing active. Next work TBD from backlog.)*

---

## 4. Backlog

Rough priority, top-down.

| # | Item | Summary | Plan |
|---|------|---------|------|
| 1 | **iPhone Phase 1 smoke** | Confirm pure Apple Music playback works cleanly on physical iPhone (iOS 26) — user never smoked Phase 1 on iPhone in isolation before Spotify work began. Covers: onboarding, tab bar, MiniPlayerBar transport, Library landing sections, playlist / album / station tap-to-play, DJ segments between tracks, news commentary, persona switching. Est. small. | — |
| 2 | **Album & station detail views** | Station playback works via tap-to-play; album playback not yet verified end-to-end. Dedicated album-detail (track list, shuffle) and station-detail (now-playing only) views. No longer gated on multi-provider work — router abstraction is already in place. Est. medium. | — |
| 3 | **K7 — rotate RSS headlines across segments** | `RSSFetcher.fetchHeadlines().first` always picks the top headline, so DJ repeats the same story across several segments from the same feed. Options: (a) rotate through top N, (b) remember last-used URLs and skip recently-used. Est. small. | — |
| 4 | **K5 — remove dead `DJPersona.voicePreset`** | Persona carries a `voicePreset` but `SettingsViewModel.effectiveVoiceIdentifier` ignores it when the user has picked a voice. Kept as seed-default for built-ins only. Either fully integrate or fully remove. Est. small. | — |
| 5 | **K17 — investigate `AttributeGraph: cycle detected`** | Console warnings first seen during Spotify work. With `.onOpenURL` + Spotify `.onChange` observers gone, re-run a clean log pass on iPhone and macOS. May be resolved incidentally by `ca23170`; verify before filing further. Est. small. | — |
| 6 | **Kokoro iOS 26 CoreML compile hang** | Unresolved from earlier. CoreML model compile on iOS 26 hangs. Matters only if user enables DJ with Kokoro voice on iPhone. Investigation paths: (a) file FluidAudio upstream issue with exact trace, (b) try different Kokoro model variant, (c) default iOS new installs to System Voice or OpenAI rather than Kokoro, (d) gate Kokoro behind a "Download model" button on iOS only. Est. medium–large depending on path. | — |
| 7 | **Macro tidy-up after Spotify rip** | Sweep for cruft the `ca23170` rip left behind: unused imports, dead helpers, stale comments mentioning Spotify, doc references in `CLAUDE.md` / spec, any `MusicProviderID` usages that silently reduce to `.appleMusic`. Est. small. Low priority but satisfying to clear. | — |
| 8 | Kokoro download indicator — real % progress | Replace indeterminate spinner with `ProgressView(value:)`. Blocked on FluidAudio upstream exposing a progress callback. Revisit quarterly. | — |
| 9 | Onboarding + iCloud sync — Commit C: Keychain iCloud sync (optional) | Flip `kSecAttrSynchronizable = true` on the OpenAI API key. One-line change. Only ship if user explicitly asks; revoked keys silently propagate. Deferred — gauge demand. | — |

---

## 5. Open Decisions

*(None active.)*

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
| K7 | `RSSFetcher.fetchHeadlines().first` always picks top | low | See Backlog #3. |
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
