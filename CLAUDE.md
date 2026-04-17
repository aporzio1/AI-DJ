# AI DJ — CLAUDE.md

## Setup

```bash
xcodegen generate
open "AI DJ.xcodeproj"
```

Re-run `xcodegen generate` any time `project.yml` changes.

## Build

Select the `AIDJ` scheme. Run on iOS Simulator or a physical iPhone/Mac.

Apple Intelligence (Foundation Models) requires a physical device with Apple Intelligence enabled — simulator will hit the onboarding gate.

## Tests

```bash
xcodebuild test -scheme AIDJ -destination 'platform=macOS'
```

## Architecture

- **Models** — pure `Sendable`/`Codable` value types, no service deps
- **Services** — protocol-backed, injected via constructors
- **ViewModels** — `@Observable` classes, constructed with service deps
- **Views** — receive ViewModels via environment or init

See `docs/superpowers/specs/2026-04-17-ai-dj-design.md` for full architecture.

## Key Facts

- Bundle ID: `com.andrewporzio.aidj`
- Targets: iOS 26.0, macOS 26.0 (Apple Silicon only)
- Swift 6.0 strict concurrency
- No Spotify, no MLX, no talk-over (MVP)
