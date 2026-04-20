# AI DJ — Project Tracker

**Owner:** Andrew P
**PM Agent:** `aidj-pm` (see `.claude/agents/aidj-pm.md`)
**Last updated:** 2026-04-20 (editable-personas consultation: split into Phase 1 / Phase 2)

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

---

## 7. Plans & Specs

| Doc | Summary |
|-----|---------|
| `docs/superpowers/specs/2026-04-17-ai-dj-design.md` | Original architecture spec for the AI DJ MVP |
| `docs/superpowers/plans/2026-04-20-spotify-support.md` | Phased implementation plan for adding Spotify as a second music provider |
