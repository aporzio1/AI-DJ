# AI DJ — Project Tracker

**Owner:** Andrew P
**PM Agent:** `aidj-pm` (see `.claude/agents/aidj-pm.md`)
**Last updated:** 2026-04-20 (News pipeline triage — Split: Commit A diagnostic fixes, Commit B NewsFrequency slider)

---

## 1. Current State

- **Platforms:** iOS 26 / macOS 26, Apple Silicon only
- **Stack:** Swift 6.0 strict concurrency, SwiftUI, MusicKit, AVFoundation, Foundation Models
- **Version:** 1.0 (CFBundleVersion 1)
- **Core capability:** Plays an Apple Music playlist with an AI DJ narrating between tracks; can pull RSS news headlines for commentary
- **TTS providers (pluggable via `DJVoiceRouter`):** Device Voices (AVSpeechSynthesizer), OpenAI cloud TTS, Kokoro on-device (FluidAudio CoreML)
- **Music provider:** Apple Music only (Spotify planned — see plan doc)
- **UI tabs:** Library (default) / Queue / Settings, plus persistent MiniPlayerBar and an expandable Now Playing sheet

---

## 2. Shipped

Reverse-chronological. Commit hashes are 7-char.

### 2026-04-20
- `290263b` — Phase 1: Library landing page with Recently Played section. Horizontal-scrolling card row above the Playlists list, powered by `MusicRecentlyPlayedRequest<Song>`; new `LibraryItem` enum (track/playlist/album/station) + `LibraryCardView` + `ProviderArtwork` abstraction ready for Phase 2.
- `00041d3` — Grounded PM agent in PMI Talent Triangle + HBR project-management principles.
- `600ffae` — Added AI DJ project-manager agent and tracker.
- `c42dc1d` — Playlist detail view + shuffle button + OpenAI voice descriptors. Tapping a Library playlist row pushes a detail screen; rows gain a Shuffle button; TTS provider "System" renamed to "Device Voices".
- `946181a` — Spotify support implementation plan committed (docs only).
- `9fd34cf` — Kokoro voice preview button in Settings; explicit trash-can delete on RSS rows; fixed URL-auto-linkification bug in Add Feed placeholder.
- `423b27a` — Redesigned Add Feed row with visible TextField chrome and leading link icon so users can see where to type.
- `760e17e` — Manual Download and Remove Model buttons for the Kokoro TTS model, with confirmation dialog and inline progress.
- `0ad3c8a` — Phase 2: Kokoro on-device TTS via FluidAudio (CoreML). American-English voices exposed, first-run download, auto-fallback to Device Voices on failure.

### 2026-04-17
- `0f4422c` — `willAdvance` lead time widened to 20 s; softened news-hook prompt.
- `3c4df88` — Decode audio into a PCM buffer for reliable MP3 playback from OpenAI.
- `2c7a795` — Phase 1: pluggable TTS provider layer; added OpenAI TTS alongside system voices. API key stored in Keychain.
- `01022cf` — Deferred `playerNode.stop` to a utility-priority Task to eliminate a priority inversion.
- `5193ca1` — DJ no longer announces an unplayable track.
- `6a3a3bb` — Three QoL fixes from user logs.

### 2026-04-16 and earlier
- `84cf31c` — Step-by-step voice-download instructions in Settings footer (macOS).
- `15f9908` — macOS button that opens System Settings → Spoken Content directly.
- `c2d5a72` — Eliminated priority inversion in the AudioGraph stop path.
- `da5ffdc` — Voice picker in Settings: pick any installed English voice.
- `1b726b6` — Progress line across the top of MiniPlayerBar.
- `7ff8942` — Persistent MiniPlayerBar at the bottom; Library is the default tab.
- `a790a18` — Library search: filter playlists and play Apple Music catalog songs.
- `95dc898` — Removed "e.g. Andrew" placeholder from the name field.
- `0cec98d` — HIG pass on SettingsView: grouped Form, footers, semantic colors.

---

## 3. In Progress

| Item | Summary | Status |
|------|---------|--------|
| Library landing page — Phase 2: Recommendations | Add a Recommendations card row below Recently Played, powered by `MusicPersonalRecommendationsRequest`. **Scope: playlists only** — filter recommendation items to `.playlist` cases, reuse existing `PlaylistDetailView` on tap, no new playback wiring. Album/station recommendations deferred to a later phase (post-Spotify-abstraction). | Scope decided 2026-04-20; implementation not yet started |
| Editable personas — Phase 1: make Alex editable | Let the user rename the single existing persona and rewrite its `styleDescriptor` ("instructions"). Persist `DJPersona` as Codable JSON in UserDefaults. Add an editor sheet from the Settings Persona row (replaces the current disabled `LabeledContent`). Add `Producer.updatePersona(_:)` so changes take effect on the next `willAdvance` without relaunch. Cap styleDescriptor at ~500 chars with counter. Do NOT expose `voicePreset` in the editor — it's already overridden by the main voice picker via `effectiveVoiceIdentifier`. | Scope decided 2026-04-20; ready to plan |
| Editable personas — Phase 2: multi-persona | Introduce a persona list with an active-picker, built-in read-only presets (Chill / Hype / News Anchor / Alex-default), and user-created custom personas (duplicate / add / delete). Store `[DJPersona] + activePersonaID` in UserDefaults. Built-ins are rehydrated from code on every launch (cannot drift). Deleting the active persona falls back to `DJPersona.default`. Delete requires `confirmationDialog`. | Scope decided 2026-04-20; blocked on Phase 1 |
| DJ frequency setting | New Settings row: 4-preset segmented picker (Rarely / Balanced / Often / Every Song) controlling how often DJ comes in between songs. Maps to `(maxGap, randomChance)` pairs consumed by `Producer.shouldGenerate`. New `DJFrequency` enum + `djFrequency` field on `Producer.Config`; `SettingsViewModel` persists via `@AppStorage` and hot-reloads via existing `producer.updateConfig(_:)`. Default `.balanced` = current behavior (maxGap 3, 50% coin flip). Single commit, ~30 min. | Scope decided 2026-04-20; ready to implement |
| MiniPlayerBar — Phase 1: progress slider + two-row layout | Replace the 2pt top progress line with a draggable `Slider` below the text (~4-6pt track). Re-layout bar to two rows: row 1 artwork+title/subtitle, row 2 transport. Height grows ~64pt → ~88pt. Drag-in-flight gate on `NowPlayingViewModel` so the 250 ms poller doesn't fight the thumb. `coordinator.seek` already supported. Single commit, ~45 min. | Scope decided 2026-04-20; ready to implement |
| MiniPlayerBar — Phase 2: shuffle + repeat | Add `isShuffled: Bool` and `repeatMode: off/all/one` state (persisted via `@AppStorage` on VM). Shuffle transforms queue from `currentIndex+1` forward, preserving history. Repeat wires into `PlaybackCoordinator.advance()`. Interaction risk: on `.one`, Producer's `willAdvance` hook should NOT run — gate the emit. UI: two icon buttons on the transport row (segmented bookends around prev/play/skip). Single commit, ~2 hrs. | Scope decided 2026-04-20; blocked on Phase 1 |
| MiniPlayerBar — Phase 3: thumbs feedback | New `TrackFeedback` store: `[trackID: .up/.down]` in UserDefaults, keyed by `Track.id`. Thumbs-down = record + auto-skip. Producer reads last-N feedback and injects `"Recently liked: X, Y. Recently disliked: Z."` into the DJ prompt (only when non-empty). Thumbs live on the expanded `NowPlayingView`, NOT on the bar (bar is getting crowded; feedback is not glanceable transport). No MusicKit rating write-through (API half-deprecated); no permanent ban (backlog if requested). Single commit, ~90 min. | Scope decided 2026-04-20; blocked on Phases 1-2 |
| HIG audit fixes — Commit 1: P1 violations + double-fire bug | 13 real violations across 5 files + 1 correctness bug. (a) Tap targets: `NowPlayingView` transport prev/skip + `MiniPlayerBar` shuffle/repeat (32pt→44pt) + `QueueView` segment dismiss — apply `.frame(minWidth: 44, minHeight: 44)` pattern matching MiniPlayerBar transport. (b) Accessibility labels: `NowPlayingView` prev/play-pause/skip, Regenerate (`.help` is macOS-only — add `.accessibilityLabel`), `QueueView` segment dismiss. (c) Destructive confirmation on `SettingsView` RSS trash button (`confirmationDialog`). (d) Remove redundant `.onTapGesture` from `MiniPlayerBar.shuffleButton`/`repeatButton` — `Button` already handles tap; double-fire is a real correctness bug. Single commit, ~45 min. | Scope decided 2026-04-20; ready to implement |
| HIG audit fixes — Commit 2: P2 spacing drift | 6 mechanical 4pt-grid fixes: `LibraryCardView.swift:19` (6→8), `NowPlayingView.swift:150` (6→8), `SettingsView.swift:245` (6→8), `PersonaListView.swift:92` (6→8), `PersonaListView.swift:99` (6→8), `PersonaListView.swift:100` (2→4). Soft-call resolution: keep `spacing: 2` in the 7 title/subtitle stacks — tight label pairs are an established iOS idiom (see Apple Music, Podcasts), bumping to 4 would visibly loosen typography for no accessibility gain. Single commit, ~15 min. | Scope decided 2026-04-20; ready to implement, independent of Commit 1 |
| News pipeline — Commit A: diagnostic fixes | User reports "haven't heard any news recently." Three root causes confirmed: (1) **Stale feeds** — `RootView.handleReady()` builds `RSSFetcher(feedURLs:)` once with a snapshot; feeds added/removed post-onboarding never propagate. Fix: add `RSSFetcher.updateFeeds(_:)` mirroring `Producer.updateVoice`/`updateListenerName`/`updatePersona`; wire `.onChange(of: settings.feedURLStrings)` in RootView. (2) **Silent `try?` swallow** at `Producer.swift:217` — fetch failures (DNS/404/malformed XML) produce zero logs. Fix: `do/catch` with `Log.producer.error`. (3) **Prompt permits skipping** — `DJBrain.generateScript` instructions include "Skip news hooks that don't fit naturally; silence is fine." Remove that sentence so the DJ uses the hook when one is injected. Single commit, ~30 min. Ship-worthy independently. | Scope decided 2026-04-20; ready to implement |
| News pipeline — Commit B: NewsFrequency slider | Mirror `DJFrequency` shape. New `NewsFrequency` enum: `rarely / balanced / often / always` (4 levels — drop `.never`, the existing `newsEnabled` toggle already covers that, avoids two overlapping controls). Roll on each segment against `probability`; on miss pass `newsHeadline: nil` and skip the fetch entirely (saves network + latency on low settings). On hit, fetch + inject + append a per-segment brain instruction: "A news headline is provided below — you MUST weave it into your script." Defaults: `.balanced` (~50%). Persist via `@AppStorage` on SettingsViewModel; hot-reload via new `Producer.updateNewsFrequency(_:)`. Segmented picker in Settings directly under the existing newsEnabled toggle. Single commit, ~45 min. Blocked on Commit A. | Scope decided 2026-04-20; ready to implement after A |

---

## 4. Backlog

| Item | Summary | Plan |
|------|---------|------|
| Album & station recommendations | Extend the Recommendations row beyond playlists — add `album(id:)` / `station(id:)` on the provider protocol + album-detail view (or play-as-queue) + station playback via `ApplicationMusicPlayer.Queue`. Intentionally deferred so these methods land on the provider-neutral protocol, not `MusicKitService` directly. | Do after Spotify abstraction (Phase 2a of Spotify plan) |
| Spotify music provider | Add Spotify alongside Apple Music. Phased rollout: abstraction refactor → read-only API → iOS SDK playback → macOS decision. | `docs/superpowers/plans/2026-04-20-spotify-support.md` |
| Merged vs segmented library | UX decision for how playlists from multiple providers are shown. | Bundled into Spotify plan §6c |
| macOS Spotify playback | WKWebView + Web Playback SDK — separate Phase 4 decision, requires DRM spike. | Bundled into Spotify plan §9 |

---

## 5. Open Decisions

| # | Decision | Options | Current recommendation |
|---|----------|---------|------------------------|
| D1 | Merged library view or segmented provider picker? | (a) segmented per-provider tabs, (b) unified list with provider badges | Segmented for MVP; merge later |
| D2 | Dev vs prod Spotify Client IDs | (a) one Client ID in all builds, (b) xcconfig-driven per build config | Decide during Phase 2a |
| D3 | On-device PKCE only vs token-swap server | (a) ship Client ID in binary, (b) stand up a token-swap service | On-device PKCE for personal/hobby use |
| D4 | macOS Spotify path | (a) Phase 4 WKWebView spike, (b) ship "iOS-only" message | Defer until iOS phases land |
| D5 | Update `CLAUDE.md` re: simulator unusability | (a) add a note, (b) leave current wording | Add note after Spotify Phase 2b lands |

---

## 6. Known Issues / Tech Debt

| # | Title | Severity | Note |
|---|-------|----------|------|
| K1 | `FakeAudioGraph` main-actor conformance | medium | Pre-existing Swift 6 concurrency error in `AIDJTests/Fakes.swift`; blocks `xcodebuild test`. Unblocks unrelated work though — root cause is FakeAudioGraph's `stop()` being main-actor-isolated while the protocol requires nonisolated |
| K2 | `@preconcurrency import FluidAudio` | low | FluidAudio isn't Swift 6 strict-concurrency-clean. Per-file relaxation is acceptable; revisit if FluidAudio updates |
| K3 | No per-voice mood descriptors for Kokoro | low | Upstream doesn't publish them; anything we add would be subjective |
| K4 | App-bundle Spotify Client ID would leak | low | Not relevant until Spotify ships. Documented in Spotify plan §3c |
| K5 | `DJPersona.voicePreset` is dead weight | low | Persona carries a `voicePreset` but `SettingsViewModel.effectiveVoiceIdentifier` ignores it whenever the user has picked a voice in the main voice picker. Keep the field as a seed-default for built-ins, but do not surface it in the upcoming persona editor — two places to set the voice would confuse users. Revisit when/if per-persona default voice becomes a real request |
| K6 | `.help(...)` used as iOS accessibility hint | low | `NowPlayingView` Regenerate button used `.help(...)` to describe its action — `.help` is a macOS-only tooltip, iOS VoiceOver gets nothing. Lesson: when adding icon-only buttons, reach for `.accessibilityLabel` first; `.help` is a macOS bonus on top. Grep `.help(` periodically to catch recurrences |
| K7 | `RSSFetcher.fetchHeadlines().first` always picks top headline | low | Producer fetches and always uses `.first` (newest). Across several consecutive segments from the same feed, the DJ hears the same headline repeatedly and may skip it. After Commits A+B ship, consider: (a) rotate through top N, (b) remember last-used headline URLs and skip recently-used ones. Deferred until user reports repetition. |

---

## 7. Plans & Specs

| Doc | Summary |
|-----|---------|
| `docs/superpowers/specs/2026-04-17-ai-dj-design.md` | Original architecture spec for the AI DJ MVP |
| `docs/superpowers/plans/2026-04-20-spotify-support.md` | Phased implementation plan for adding Spotify as a second music provider |
