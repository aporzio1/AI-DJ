# Repository Guidelines

## Project Structure & Module Organization

Patter is a Swift 6 Xcode project generated from `project.yml`. App source lives in `Patter/`, organized by responsibility:

- `Patter/App/` contains app entry and root composition.
- `Patter/Models/` contains `Sendable`/`Codable` value types.
- `Patter/Services/` contains protocol-backed integrations such as MusicKit, DJ generation, voice rendering, RSS, and playback coordination.
- `Patter/ViewModels/` contains `@Observable` state objects.
- `Patter/Views/` contains SwiftUI screens and components.
- `Patter/Resources/` contains `Info.plist`, entitlements, and asset catalogs.
- `PatterTests/` contains Swift Testing unit tests and fakes.
- `docs/` contains design notes, implementation plans, and the project tracker.

## Build, Test, and Development Commands

Regenerate the Xcode project after editing `project.yml`:

```bash
xcodegen generate
```

Build the app for an available simulator:

```bash
xcodebuild build -project Patter.xcodeproj -scheme Patter -destination 'platform=iOS Simulator,name=iPhone 17'
```

Run tests when the local destination supports the target:

```bash
xcodebuild test -project Patter.xcodeproj -scheme Patter -destination 'platform=macOS'
```

Open the project for interactive development:

```bash
open "Patter.xcodeproj"
```

Apple Intelligence/Foundation Models behavior requires a physical Apple Intelligence-capable device; simulator runs may hit onboarding availability gates.

## Coding Style & Naming Conventions

Use Swift 6 with strict concurrency in mind. Prefer constructor injection and protocol-backed services. Keep models pure and free of service dependencies. Use 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and descriptive test names. Keep comments short and useful; explain non-obvious behavior rather than restating code.

## Testing Guidelines

Tests use Swift Testing (`import Testing`) and live in `PatterTests/`. Use focused suites such as `@Suite("Producer")`, `@Test func behaviorUnderCondition() async`, and shared fakes in `PatterTests/Fakes.swift`. Add regression tests for playback state, prompt context, RSS parsing, and service fallback behavior when changing those areas.

## Commit & Pull Request Guidelines

Recent commits follow conventional prefixes: `feat:`, `fix:`, `docs:`, `build:`, `chore:`, and `refactor:`. Keep commit subjects imperative and scoped, for example `fix: prevent opening DJ intro from using past tense`.

Pull requests should include a concise summary, test/build results, linked issue or tracker item when applicable, and screenshots or short recordings for visible UI changes. Call out device-only validation needs, especially MusicKit, playback, TTS, and Apple Intelligence behavior.

## Security & Configuration Tips

Do not commit API keys, tokens, provisioning profiles, or generated private build artifacts. Keep bundle identifiers, entitlements, and deployment targets in sync through `project.yml` and regenerated Xcode project files.
