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
- **Services** — protocol-backed, injected via constructors
- **ViewModels** — `@Observable` classes, constructed with service deps
- **Views** — receive ViewModels via environment or init

See `docs/superpowers/specs/2026-04-17-ai-dj-design.md` for full architecture (filename retains the original "ai-dj" project codename).

## Key Facts

- Bundle ID: `com.andrewporzio.patter`
- Targets: iOS 26.0, macOS 26.0 (Apple Silicon only)
- Swift 6.0 strict concurrency
- No Spotify, no MLX, no talk-over (MVP)
- Renamed from "AI DJ" → "Patter" on 2026-04-23 (see project tracker for the rename rationale + research)
