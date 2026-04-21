# AI DJ — Project Tracker

**Owner:** Andrew P
**PM Agent:** `aidj-pm` (see `.claude/agents/aidj-pm.md`)
**Last updated:** 2026-04-21 — reconciled 39 commits of drift, cleared In Progress of shipped items, tracker now aligned with git HEAD at `11ca3ca`.

---

## 1. Current State

- **Platforms:** iOS 26 / macOS 26, Apple Silicon only
- **Stack:** Swift 6.0 strict concurrency, SwiftUI, MusicKit, AVFoundation, Foundation Models
- **Version:** 1.0 (CFBundleVersion 1)
- **Core capability:** Plays Apple Music content (playlists, albums, stations) with an AI DJ narrating between tracks; can pull RSS news headlines for commentary
- **TTS providers (pluggable via `DJVoiceRouter`):** Device Voices (AVSpeechSynthesizer), OpenAI cloud TTS, Kokoro on-device (FluidAudio CoreML) with launch-time warm-up
- **Music provider:** Apple Music only (Spotify planned — see plan doc)
- **UI tabs:** Library (default) / Queue / Settings, plus persistent MiniPlayerBar (2-row with progress slider, shuffle/repeat, thumbs feedback) and an expandable Now Playing sheet
- **Library landing:** Recently Played + Made for You (playlists, albums, stations) with stale-while-revalidate disk cache + pull-to-refresh
- **Onboarding:** 4-step first-launch wizard (Name → DJ + Voice → News → iCloud) with migration auto-completion for existing users
- **iCloud sync:** `CloudSyncService` mirrors curated Settings keys to NSUbiquitousKeyValueStore; opt-in toggle + hot-reload across devices
- **Personas:** Multiple personas with built-in presets + user-created custom personas; DJ frequency + News frequency pickers
- **Feedback:** Thumbs-up / thumbs-down per track injected into DJ prompt

---

## 2. Shipped

Reverse-chronological. Commit hashes are 7-char.

### 2026-04-21
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

*(empty — all previously in-flight items have shipped; HIG Commit 1 work is the next candidate to enter this table)*

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

---

## 5. Open Decisions

| # | Decision | Options | Current recommendation |
|---|----------|---------|------------------------|
| D1 | Merged library view or segmented provider picker? | (a) segmented per-provider tabs, (b) unified list with provider badges | Segmented for MVP; merge later |
| D2 | Dev vs prod Spotify Client IDs | (a) one Client ID in all builds, (b) xcconfig-driven per build config | Decide during Phase 2a |
| D3 | On-device PKCE only vs token-swap server | (a) ship Client ID in binary, (b) stand up token-swap service | On-device PKCE for personal/hobby use |
| D4 | macOS Spotify path | (a) Phase 4 WKWebView spike, (b) ship "iOS-only" message | Defer until iOS phases land |
| D5 | Update `CLAUDE.md` re: simulator unusability | (a) add a note, (b) leave current wording | Add note after Spotify Phase 2b lands |

---

## 6. Known Issues / Tech Debt

| # | Title | Severity | Note |
|---|-------|----------|------|
| K1 | `FakeAudioGraph` main-actor conformance | medium | Pre-existing Swift 6 concurrency error in `AIDJTests/Fakes.swift`; blocks `xcodebuild test`. Root cause is `FakeAudioGraph.stop()` being main-actor-isolated while the protocol requires nonisolated |
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

---

## 7. Plans & Specs

| Doc | Summary |
|-----|---------|
| `docs/superpowers/specs/2026-04-17-ai-dj-design.md` | Original architecture spec for the AI DJ MVP |
| `docs/superpowers/plans/2026-04-20-spotify-support.md` | Phased implementation plan for adding Spotify as a second music provider |
