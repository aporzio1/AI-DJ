# Patter — CLAUDE.md

## Setup

```bash
xcodegen generate
open "Patter.xcodeproj"
```

Re-run `xcodegen generate` any time `project.yml` changes.

## Build

Select the `Patter` scheme. Run on iOS Simulator or a physical iPhone/Mac.

Apple Intelligence (Foundation Models) requires a physical device with Apple Intelligence enabled — simulator will hit the onboarding gate.

## Tests

```bash
xcodebuild test -scheme Patter -destination 'platform=macOS'
```

## Architecture

- **Models** — pure `Sendable`/`Codable` value types, no service deps
- **Services** — protocol-backed, injected via constructors. Current surface includes MusicKitService/MusicProviderRouter (playback), DJBrain/Producer (script generation), DJVoiceRouter (voice, routes to SystemDJVoice/OpenAIDJVoice/KokoroDJVoice), AudioGraph/PlaybackCoordinator, RSSFetcher (news), CloudSyncService (iCloud KV sync, opt-in), TrackFeedbackStore.
- **ViewModels** — `@Observable` classes, constructed with service deps
- **Views** — receive ViewModels via environment or init

Personas, RSS/news injection, and CloudSync are shipped features, not future work — the stale spec doc below predates all three.

`docs/superpowers/specs/2026-04-17-ai-dj-design.md` has background architecture context (filename retains the original "ai-dj" codename) but predates Spotify removal, personas, CloudSync, RSS/news, and TrackFeedbackStore — treat it as historical, not current. For live project state (in-progress work, backlog, known issues), read `docs/project-tracker.md` first.

## Project Tracker & PM Agent

`docs/project-tracker.md` is the canonical live-state record — owner, in-progress work, backlog, known issues/tech debt, open decisions. Check it before assuming current state from code alone.

The `patter-pm` subagent owns that tracker. Consult it BEFORE surfacing non-trivial design decisions, scoping questions, or new-feature proposals, and AFTER shipping substantial work so the tracker stays current.

## Dependencies

- **FluidAudio** (SPM, pinned `0.13.5`) — on-device Kokoro TTS via CoreML, one of the pluggable `DJVoiceRouter` providers alongside AVSpeechSynthesizer (system) and OpenAI cloud TTS.

## Build Gotchas

- `CFBundleVersion` auto-bumps from `git rev-list --count HEAD` via a `preBuildScripts` phase in `project.yml` (writes directly to `Patter/Resources/Info.plist`). `ENABLE_USER_SCRIPT_SANDBOXING: NO` is set at the target level specifically so this script can read `.git/objects` and write the source plist — don't re-enable sandboxing without accounting for this. Don't hand-edit `CFBundleVersion` — it self-corrects on next build.
- Apple Intelligence/Foundation Models paths only run on a physical Apple Intelligence-capable device; simulator hits an onboarding availability gate regardless of scheme.
- CloudSync uses iCloud key-value storage (`iCloud.com.andrewporzio.patter` entitlement) and is opt-in — don't assume sync state without checking the toggle.
- Swift 6 strict concurrency is enforced project-wide; AudioGraph/PlaybackCoordinator have real actor-isolation boundaries — don't sprinkle `@unchecked Sendable` or `nonisolated(unsafe)` to silence a warning without understanding why isolation was needed there.

## Key Facts

- Bundle ID: `com.andrewporzio.patter`
- Targets: iOS 26.0, macOS 26.0 (Apple Silicon only)
- Swift 6.0 strict concurrency
- No Spotify, no MLX, no talk-over (MVP)
- Renamed from "AI DJ" → "Patter" on 2026-04-23 (see project tracker for the rename rationale + research)

For coding style, commit/PR conventions, and test-suite structure, see `AGENTS.md`.
