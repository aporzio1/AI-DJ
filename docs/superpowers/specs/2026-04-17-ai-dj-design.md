# AI DJ — Design Spec

**Date:** 2026-04-17
**Status:** Approved, pre-implementation
**Author:** Andrew P (with Claude Code)

## Summary

A multiplatform (iOS 26+ / macOS 26+) SwiftUI app that plays music from Apple Music and interleaves short, AI-generated DJ segments — announcements, banter, and optional RSS-sourced news — between tracks. The DJ is generated on-device using the Foundation Models framework (Apple Intelligence) and spoken via `AVSpeechSynthesizer`. Architected from day one so that "talk over intros/outros" can be enabled later without a rewrite.

## Scope

### In scope (MVP)

- Apple Music playback via MusicKit (`ApplicationMusicPlayer`)
- Between-song DJ segments: announcement + banter + optional news
- On-device script generation via Foundation Models
- TTS via `AVSpeechSynthesizer` rendered to local audio files
- RSS feed management (add/remove URLs, import OPML on macOS)
- Single hardcoded DJ persona, with a picker scaffold for future presets
- iOS + macOS from a single SwiftUI app target

### Out of scope (explicitly deferred)

- Spotify integration (no stubs, no protocols; add when that work begins)
- Talk-over (speaking over track intros/outros) — architected for, not shipped
- User-defined DJ personas
- Custom/bundled ML models (MLX, llama.cpp, etc.)
- News sources other than RSS (calendar, weather, etc.)
- Intel Macs, pre-Apple-Silicon devices, pre-iOS-26 / pre-macOS-26 OS versions

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Platform targeting | SwiftUI multiplatform, iOS 26 + macOS 26 | Native on both; Catalyst is legacy in 2026 |
| On-device AI | Foundation Models only | DJ banter is exactly what it's good at; YAGNI on MLX fallback |
| DJ timing | Between-songs for MVP; audio graph ready for talk-over | Upfront cost is modest; retrofit later is painful |
| News content | User-configured RSS feeds | Only source that stays factual in 2026 without a subscription API |
| Music provider | Apple Music only | Spotify-on-macOS is a rabbit hole; revisit after MVP ships |
| Queue model | Unified timeline of `PlayableItem`s | Maps to SwiftUI `List` directly; extends to talk-over via `overlapStart` |
| TTS | `AVSpeechSynthesizer` | Built in, free, works on both platforms, no model bundling |
| Persona | Single hardcoded preset | YAGNI; picker UI is in place for later |

## Architecture

### Layers

```
Views → ViewModels → Services → Models
```

SwiftUI + MVVM + `@Observable` (Observation framework). Platform-specific code is isolated behind `#if os(macOS)` in menu commands, window commands, and the OPML importer — nowhere else.

### Models

Pure data types, `Sendable`, `Codable` where relevant, no service dependencies.

- **`Track`** — `id`, `title`, `artist`, `album`, `artworkURL`, `duration`, `providerID` (`.appleMusic` in MVP)
- **`DJSegment`** — `id`, `kind` (`.announcement` | `.banter` | `.news`), `script`, `audioFileURL`, `duration`, `overlapStart: TimeInterval?` (reserved for talk-over, always `nil` in MVP)
- **`PlayableItem`** — enum: `.track(Track)` | `.djSegment(DJSegment)`
- **`DJPersona`** — `name`, `voicePreset`, `styleDescriptor` (fed into LLM prompt as persona guidance)
- **`NewsHeadline`** — `title`, `source`, `url`, `publishedAt`, `summary`

### Services

Each is single-purpose, protocol-backed, and mockable for tests.

- **`MusicKitService`** — wraps Apple MusicKit. Responsibilities: authorization, library browse (playlists/artists/albums/songs), `ApplicationMusicPlayer` playback control, Now Playing metadata, track-ended callbacks.

- **`DJBrain`** — wraps the Foundation Models framework. Input: `DJPersona` + upcoming `Track` + last-N recent tracks + time-of-day + optional `[NewsHeadline]`. Output: a `DJScript` string (<= ~200 chars). Uses guided generation where possible. Device-level availability is checked once at onboarding via `SystemLanguageModel.availability` and blocks the app if unavailable; per-call generation failures at runtime (model errors, timeouts) throw, and `Producer` catches them to run the canned-template fallback described below.

- **`DJVoice`** — wraps `AVSpeechSynthesizer`. `renderToFile(script: String, voice: AVSpeechSynthesisVoice) async throws -> URL` returns a local `.caf`. One concrete voice per persona in MVP.

- **`RSSFetcher`** — async `URLSession` + `XMLParser`. Fetches configured feeds, parses RSS 2.0 and Atom, dedupes by URL, caps at ~20 recent headlines per feed. No third-party dependencies.

- **`AudioGraph`** — owns an `AVAudioEngine` with an `AVAudioPlayerNode` for TTS playback and configures `AVAudioSession` with `.duckOthers`. Key design detail: `ApplicationMusicPlayer` plays directly to the system output and is opaque to us, but `AVAudioSession` duck mode makes Apple Music auto-duck whenever we play TTS. This is exactly the mechanism that lets MVP (between-songs, no overlap) and future talk-over (overlap during intros/outros) share the same audio graph — the only difference is when the TTS player node starts relative to the music.

- **`PlaybackCoordinator`** — central actor. Owns queue `[PlayableItem]`, current index, and playback state (`.idle`/`.playing`/`.paused`/`.buffering`). Methods: `play()`, `pause()`, `skip()`, `previous()`, `enqueue(_:)`, `replaceQueue(_:)`. Drives transitions: routes `.track` items to `MusicKitService` and `.djSegment` items to `AudioGraph`. Emits transition events that `Producer` subscribes to.

- **`Producer`** — subscribes to Coordinator transition events. Lookahead = 1 item. When the current track has ~T-5s remaining, prime a `.djSegment` for the upcoming transition: gather context → `DJBrain` → `DJVoice` → insert `.djSegment` into queue immediately before the next `.track`. On any failure, falls back (see Error Handling).

### ViewModels

All `@Observable` classes, constructor-injected with service dependencies:

- `NowPlayingViewModel` — current item, playback state, controls
- `QueueViewModel` — queue contents, reorder, remove, skip-segment, regenerate-segment
- `LibraryViewModel` — MusicKit library browse, add-to-queue
- `SettingsViewModel` — persona picker, feature toggles (DJ / news / announcements), RSS feed CRUD
- `OnboardingViewModel` — MusicKit auth status, Apple Intelligence availability

### Views

- **`AIDJApp`** — `@main`. On macOS, adds `CommandGroup` entries (Play/Pause, Skip DJ, Regenerate Banter).
- **`RootView`** — `NavigationSplitView` on macOS + iPad, `TabView` on iPhone. Sections: Now Playing · Queue · Library · Settings.
- **`OnboardingView`** — gates on MusicKit auth and Apple Intelligence availability; blocks if either is missing, with deep links to Settings.
- **`NowPlayingView`** — artwork, transport controls, a "DJ is speaking" banner when the current item is a `.djSegment`.
- **`QueueView`** — list of `PlayableItem` rows with visual distinction between tracks and segments; swipe-to-skip on segments.
- **`LibraryView`** — MusicKit browse with add-to-queue actions.
- **`SettingsView`** — persona picker, feature toggles, RSS feed list (add/remove URL, import OPML on macOS via `fileImporter`).

## Data Flow — Happy Path

1. User picks a playlist in `LibraryView` → `PlaybackCoordinator.replaceQueue([Track])`.
2. Coordinator starts first track via `MusicKitService`.
3. At ~T-5s remaining, Coordinator emits `willAdvance`. `Producer` gathers context (next track + recent 3 + one RSS headline + persona + time-of-day), calls `DJBrain` → script → `DJVoice` → local audio file, and inserts `.djSegment(...)` into the queue immediately before the next track.
4. Current track ends. Coordinator advances to the `.djSegment`; `AudioGraph` plays the file via the TTS player node. MusicKit playback is paused.
5. Segment ends. Coordinator advances to the next `.track`; `MusicKitService` resumes playback with the new track.

## Error Handling

The DJ is strictly optional. Music never stops because the DJ broke.

| Failure | Behavior |
|---|---|
| MusicKit authorization denied | Onboarding gate with deep link to Settings |
| Apple Intelligence unavailable | Onboarding blocks app with "requires Apple Intelligence" copy |
| RSS fetch fails / no feeds configured | `Producer` omits news context; falls back to announcement + banter |
| `DJBrain` generation fails | `Producer` falls back to canned template: `"Up next, {title} by {artist}."` |
| `DJVoice` render fails | `Producer` skips the segment entirely; Coordinator goes straight to next track |
| Segment not ready by track-end (generation slower than remaining track time) | Coordinator advances straight to the next track; the missed segment is discarded, not deferred |
| `AVAudioSession` interruption (call, Siri) | Pause everything; resume on interruption-end if playback had been active |

## Testing Strategy

- **Unit**: models (`Codable` round-trip, equality), `DJBrain` prompt construction (given known inputs, assert prompt structure), `Producer` state machine (mocked `DJBrain` + `DJVoice`), `RSSFetcher` parser (RSS 2.0 and Atom fixtures).
- **Integration**: `PlaybackCoordinator` transitions with fake `MusicKitService` + fake `AudioGraph`. Covers: track→track, track→segment→track, user-skip during segment, user-skip during track.
- **Manual**: audio quality, voice naturalness, timing feel. No automation — a passing unit test cannot tell you whether the DJ sounds good.

## Project Layout (XcodeGen)

```
AI DJ/
├── project.yml                 # single app target, iOS + macOS destinations
├── CLAUDE.md
├── docs/
│   └── superpowers/specs/
│       └── 2026-04-17-ai-dj-design.md
├── AIDJ/
│   ├── App/                    # AIDJApp.swift, RootView.swift
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   ├── Views/
│   └── Resources/              # Assets.xcassets, Info.plist, entitlements
└── AIDJTests/
```

- **Bundle id**: `com.andrewporzio.aidj`
- **Module name**: `AIDJ`
- **Swift**: 5.9
- **Deployment targets**: iOS 26.0, macOS 26.0
- **Devices**: Apple Silicon Macs (M1+), iPhones capable of Apple Intelligence
- **Entitlements**: MusicKit, network client

## Notable Choices Worth Revisiting Later

- **No `MusicProvider` protocol in MVP.** When Spotify work begins, introduce the protocol and retrofit `MusicKitService` to conform. Building the abstraction before a second implementation exists is a common over-engineering mistake.
- **Persona is hardcoded; Settings has a picker anyway.** The picker is plumbing for future presets; it's one item in MVP.
- **Foundation Models only, no fallback model.** If device-support data after launch shows enough users blocked at onboarding, reconsider MLX.
- **`AVSpeechSynthesizer`, not a neural TTS model.** Voice quality is acceptable in iOS 26; revisit if the app ships and users complain.

## Open Questions

None at design time. All load-bearing decisions were resolved during brainstorming.
