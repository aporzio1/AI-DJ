# DJ News Verbosity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four-level news verbosity setting (Brief / Standard / Detailed / Deep Dive); the two upper levels fetch and inject full article text, with a one-time Deep Dive latency warning and silent fallback to Standard on fetch failure.

**Architecture:** New `NewsVerbosity` value type carries all per-level constants. New `ArticleFetcher` service (protocol-backed, injected into `Producer`) downloads + extracts article body only when the level needs it. Verbosity + optional article body thread through `DJContext` → `DJPromptTemplate` → `DJBrain`. Settings UI adds a picker to `NewsSection` with a one-shot alert.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Foundation Models (on-device), Swift Testing (`@Suite`/`@Test`/`#expect`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-06-news-verbosity-design.md`

## Global Constraints

- Default level is `.standard` and must reproduce today's behavior byte-for-byte in the prompt (existing users see zero change).
- Article fetch happens ONLY for `.detailed`/`.deepDive`, only for the one headline in the segment being generated.
- Fetch/extraction failure ⇒ proceed exactly as `.standard` (RSS summary, standard guidance). Never block or skip the segment because of a bad website.
- Article body caps: 1,500 chars (Detailed), 3,500 chars (Deep Dive) — protects the ~4k-token Foundation Models context.
- The generated script must state only facts from the provided summary/article (prompt guardrail line).
- Deep Dive warning alert fires once per device (UserDefaults sentinel), Cancel reverts the picker.
- Tests run via `xcodebuild test -scheme Patter -destination 'platform=macOS'`. Regenerate project with `xcodegen generate` only if files are added (XcodeGen globs sources — new files under `Patter/`/`PatterTests/` are picked up by regeneration).
- This work lands on its own branch off the integration point Andrew chooses (NOT mixed into `spike/kokoro-ane-0.15.4`'s app-code changes; the spec/plan docs already live there and merge with it).

---

### Task 1: `NewsVerbosity` model

**Files:**
- Create: `Patter/Models/NewsVerbosity.swift`
- Test: `PatterTests/NewsVerbosityTests.swift`

**Interfaces:**
- Produces: `enum NewsVerbosity: String, Codable, CaseIterable, Identifiable, Sendable` with cases `brief, standard, detailed, deepDive`; members `displayName: String`, `needsArticleFetch: Bool`, `articleBodyCharCap: Int?`, `promptGuidance: String`, `scriptCharCap: Int`, `static let default`.

- [ ] **Step 1: Write the failing test**

```swift
// PatterTests/NewsVerbosityTests.swift
import Testing
import Foundation
@testable import Patter

@Suite("NewsVerbosity")
struct NewsVerbosityTests {

    @Test func defaultIsStandard() {
        #expect(NewsVerbosity.default == .standard)
    }

    @Test func onlyUpperLevelsFetchArticles() {
        #expect(!NewsVerbosity.brief.needsArticleFetch)
        #expect(!NewsVerbosity.standard.needsArticleFetch)
        #expect(NewsVerbosity.detailed.needsArticleFetch)
        #expect(NewsVerbosity.deepDive.needsArticleFetch)
    }

    @Test func articleCapsMatchSpec() {
        #expect(NewsVerbosity.brief.articleBodyCharCap == nil)
        #expect(NewsVerbosity.standard.articleBodyCharCap == nil)
        #expect(NewsVerbosity.detailed.articleBodyCharCap == 1500)
        #expect(NewsVerbosity.deepDive.articleBodyCharCap == 3500)
    }

    @Test func scriptCapsWidenWithLevel() {
        #expect(NewsVerbosity.brief.scriptCharCap == 500)
        #expect(NewsVerbosity.standard.scriptCharCap == 500)
        #expect(NewsVerbosity.detailed.scriptCharCap == 1200)
        #expect(NewsVerbosity.deepDive.scriptCharCap == 2200)
    }

    @Test func rawValuesRoundTripForPersistence() {
        for level in NewsVerbosity.allCases {
            #expect(NewsVerbosity(rawValue: level.rawValue) == level)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | grep -E "error|FAIL" | head`
Expected: compile error "cannot find 'NewsVerbosity' in scope"

- [ ] **Step 3: Write minimal implementation**

```swift
// Patter/Models/NewsVerbosity.swift
import Foundation

/// How much detail the DJ gives when covering a news story. The two upper
/// levels download the full article; Brief/Standard use only RSS data.
/// All per-level constants live here so Producer/DJPromptTemplate/Settings
/// can't drift on the numbers.
enum NewsVerbosity: String, Codable, CaseIterable, Identifiable, Sendable {
    case brief
    case standard
    case detailed
    case deepDive

    static let `default`: NewsVerbosity = .standard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brief:    "Brief"
        case .standard: "Standard"
        case .detailed: "Detailed"
        case .deepDive: "Deep Dive"
        }
    }

    /// Settings footer copy for the selected level.
    var settingsDescription: String {
        switch self {
        case .brief:    "A quick one-line mention of the headline."
        case .standard: "A few sentences of context from the feed summary."
        case .detailed: "Downloads the article and covers it in about a paragraph."
        case .deepDive: "Downloads the article and covers it in a few paragraphs. Segments take noticeably longer to generate."
        }
    }

    /// Whether Producer should download the article body before generation.
    var needsArticleFetch: Bool {
        self == .detailed || self == .deepDive
    }

    /// Max article-body characters fed to the on-device model (nil = no fetch).
    /// Caps keep the prompt well inside the ~4k-token Foundation Models window.
    var articleBodyCharCap: Int? {
        switch self {
        case .brief, .standard: nil
        case .detailed:         1500
        case .deepDive:         3500
        }
    }

    /// News-segment length guidance injected into the LLM instructions.
    var promptGuidance: String {
        switch self {
        case .brief:
            "Mention the news topic in at most 1–2 sentences as a quick aside. Do not go into story details even if a summary is present. Keep the whole break at 2 to 4 sentences, 30-70 words."
        case .standard:
            "aim for 4–5 sentences, 60–100 words."
        case .detailed:
            "cover the story in 6–8 sentences, 120–180 words, before bridging back to the next song."
        case .deepDive:
            "cover the story in depth: 2–3 short spoken paragraphs, 220–320 words total, before bridging back to the next song."
        }
    }

    /// Cap for DJBrain's sentence-boundary truncation of the final script.
    var scriptCharCap: Int {
        switch self {
        case .brief, .standard: 500
        case .detailed:         1200
        case .deepDive:         2200
        }
    }
}
```

- [ ] **Step 4: Regenerate project and run tests**

Run: `xcodegen generate && xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Patter/Models/NewsVerbosity.swift PatterTests/NewsVerbosityTests.swift Patter.xcodeproj
git commit -m "feat(news): add NewsVerbosity model with per-level constants"
```

---

### Task 2: Settings persistence

**Files:**
- Modify: `Patter/Utilities/SettingsKeys.swift` (add two keys after `newsFrequency`)
- Modify: `Patter/ViewModels/SettingsViewModel.swift` (property + save/load + synced-keys list)
- Test: `PatterTests/SettingsViewModelTests.swift` (append tests)

**Interfaces:**
- Consumes: `NewsVerbosity` (Task 1).
- Produces: `SettingsViewModel.newsVerbosity: NewsVerbosity` (persisted); `SettingsViewModel.markDeepDiveWarned()` + `SettingsViewModel.hasSeenDeepDiveWarning: Bool`; keys `SettingsKeys.newsVerbosity`, `SettingsKeys.newsVerbosityDeepDiveWarned`.

- [ ] **Step 1: Write the failing tests**

Append inside the existing `@Suite` in `PatterTests/SettingsViewModelTests.swift`, following that file's existing pattern for constructing `SettingsViewModel` with an isolated `UserDefaults` (reuse the same helper the neighboring tests use — e.g. the suite's `makeDefaults()`/fresh-suite-name pattern):

```swift
@Test func newsVerbosityDefaultsToStandard() {
    let defaults = makeDefaults()
    let settings = SettingsViewModel(defaults: defaults)
    #expect(settings.newsVerbosity == .standard)
}

@Test func newsVerbosityPersistsAcrossInstances() {
    let defaults = makeDefaults()
    let settings = SettingsViewModel(defaults: defaults)
    settings.newsVerbosity = .deepDive
    settings.save()
    let reloaded = SettingsViewModel(defaults: defaults)
    #expect(reloaded.newsVerbosity == .deepDive)
}

@Test func deepDiveWarningSentinelIsOneShot() {
    let defaults = makeDefaults()
    let settings = SettingsViewModel(defaults: defaults)
    #expect(!settings.hasSeenDeepDiveWarning)
    settings.markDeepDiveWarned()
    #expect(settings.hasSeenDeepDiveWarning)
    let reloaded = SettingsViewModel(defaults: defaults)
    #expect(reloaded.hasSeenDeepDiveWarning)
}
```

(If the suite's defaults helper has a different name, match it — the assertion bodies stay the same.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | grep -E "error" | head`
Expected: compile error — `newsVerbosity` not a member of `SettingsViewModel`

- [ ] **Step 3: Implement**

`SettingsKeys.swift` — add after the `newsFrequency` line:

```swift
    static let newsVerbosity = "newsVerbosity"
    static let newsVerbosityDeepDiveWarned = "newsVerbosityDeepDiveWarned"  // device-local sentinel; one-shot
```

`SettingsViewModel.swift`:
1. Property, next to `newsFrequency` (line ~11): `var newsVerbosity: NewsVerbosity = .default`
2. Synced-keys array (the list containing `SettingsKeys.newsFrequency`, line ~39): add `SettingsKeys.newsVerbosity,` (the sentinel stays device-local — do NOT add it).
3. In `save()` next to the `newsFrequency` write (line ~143): `write(newsVerbosity.rawValue, forKey: SettingsKeys.newsVerbosity)`
4. In `load()` next to the `newsFrequency` read (line ~165):

```swift
        if let raw = defaults.string(forKey: SettingsKeys.newsVerbosity),
           let level = NewsVerbosity(rawValue: raw) {
            newsVerbosity = level
        } else {
            newsVerbosity = .default
        }
```

5. Sentinel accessors (near the other one-shot sentinel logic, e.g. by `applyIOS26KokoroDowngradeIfNeeded`):

```swift
    /// One-shot "Deep Dive takes longer" alert bookkeeping (device-local).
    var hasSeenDeepDiveWarning: Bool {
        defaults.bool(forKey: SettingsKeys.newsVerbosityDeepDiveWarned)
    }

    func markDeepDiveWarned() {
        defaults.set(true, forKey: SettingsKeys.newsVerbosityDeepDiveWarned)
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Patter/Utilities/SettingsKeys.swift Patter/ViewModels/SettingsViewModel.swift PatterTests/SettingsViewModelTests.swift
git commit -m "feat(news): persist news verbosity setting + deep-dive warning sentinel"
```

---

### Task 3: `ArticleFetcher` service

**Files:**
- Create: `Patter/Services/ArticleFetching.swift` (protocol)
- Create: `Patter/Services/ArticleFetcher.swift` (implementation)
- Test: `PatterTests/ArticleFetcherTests.swift`

**Interfaces:**
- Produces:
  - `protocol ArticleFetching: Sendable { func body(for url: URL, maxChars: Int) async -> String? }`
  - `struct ArticleFetcher: ArticleFetching` with `init(dataLoader:)` for test injection, default = real `URLSession` with 6 s timeout.
  - Internal `static func extractBody(html: String, maxChars: Int) -> String?` (tested directly).

- [ ] **Step 1: Write the failing tests**

```swift
// PatterTests/ArticleFetcherTests.swift
import Testing
import Foundation
@testable import Patter

@Suite("ArticleFetcher")
struct ArticleFetcherTests {

    private let cleanArticle = """
    <html><head><title>T</title><style>p{color:red}</style></head><body>
    <nav><p>Home News Sports Weather Subscribe Login</p></nav>
    <article>
    <p>The first paragraph of the story explains what happened in enough detail to be useful.</p>
    <p>The second paragraph adds who was involved and quotes an official on why it matters going forward.</p>
    <p>The third paragraph gives background context about prior events leading up to this development.</p>
    </article>
    <footer><p>Copyright 2026. All rights reserved. Privacy. Terms.</p></footer>
    <script>var x = "<p>not content</p>";</script>
    </body></html>
    """

    @Test func extractsParagraphsAndDropsChrome() {
        let body = ArticleFetcher.extractBody(html: cleanArticle, maxChars: 4000)
        #expect(body != nil)
        let text = body ?? ""
        #expect(text.contains("first paragraph of the story"))
        #expect(text.contains("prior events"))
        #expect(!text.contains("Subscribe"))
        #expect(!text.contains("var x"))
        #expect(!text.contains("<p>"))
    }

    @Test func truncatesAtWordBoundaryToMaxChars() {
        let body = ArticleFetcher.extractBody(html: cleanArticle, maxChars: 120)
        let text = body ?? ""
        #expect(text.count <= 120)
        #expect(!text.hasSuffix(" "))       // clean word boundary
        #expect(text.contains("first paragraph"))
    }

    @Test func junkPageReturnsNil() {
        let junk = "<html><body><div>OK</div><p>Loading…</p></body></html>"
        #expect(ArticleFetcher.extractBody(html: junk, maxChars: 4000) == nil)
    }

    @Test func fetchFailureReturnsNil() async {
        let fetcher = ArticleFetcher(dataLoader: { _ in
            throw URLError(.timedOut)
        })
        let body = await fetcher.body(for: URL(string: "https://example.com/a")!, maxChars: 1500)
        #expect(body == nil)
    }

    @Test func non200ReturnsNil() async {
        let fetcher = ArticleFetcher(dataLoader: { url in
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (Data("<html><p>Not found page body text that is fairly long anyway</p></html>".utf8), resp)
        })
        let body = await fetcher.body(for: URL(string: "https://example.com/a")!, maxChars: 1500)
        #expect(body == nil)
    }

    @Test func successfulFetchExtracts() async {
        let html = cleanArticle
        let fetcher = ArticleFetcher(dataLoader: { url in
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            return (Data(html.utf8), resp)
        })
        let body = await fetcher.body(for: URL(string: "https://example.com/a")!, maxChars: 1500)
        #expect(body?.contains("first paragraph of the story") == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | grep -E "error" | head`
Expected: compile error — `ArticleFetcher` not found

- [ ] **Step 3: Implement**

```swift
// Patter/Services/ArticleFetching.swift
import Foundation

/// Downloads an article URL and returns readable body text, or nil on any
/// failure. Callers treat nil as "fall back to the RSS summary" — this
/// service never throws into the DJ pipeline.
protocol ArticleFetching: Sendable {
    func body(for url: URL, maxChars: Int) async -> String?
}
```

```swift
// Patter/Services/ArticleFetcher.swift
import Foundation

/// Heuristic full-article text extraction for the Detailed/Deep Dive news
/// verbosity levels. Plain-Swift tag stripping (no WebKit, no third-party
/// readability dep): drop script/style/nav/header/footer/aside blocks,
/// collect <p> runs, keep the result only if it looks like real prose.
struct ArticleFetcher: ArticleFetching {

    /// Injectable network layer so tests never touch the real network.
    private let dataLoader: @Sendable (URL) async throws -> (Data, URLResponse)

    init(dataLoader: (@Sendable (URL) async throws -> (Data, URLResponse))? = nil) {
        if let dataLoader {
            self.dataLoader = dataLoader
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 6
            let session = URLSession(configuration: config)
            self.dataLoader = { url in try await session.data(from: url) }
        }
    }

    func body(for url: URL, maxChars: Int) async -> String? {
        do {
            let (data, response) = try await dataLoader(url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                Log.producer.info("ArticleFetcher: HTTP \(http.statusCode) for \(url.host ?? "?", privacy: .public) — falling back to summary")
                return nil
            }
            guard let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else { return nil }
            let extracted = Self.extractBody(html: html, maxChars: maxChars)
            if extracted == nil {
                Log.producer.info("ArticleFetcher: extraction produced no usable text for \(url.host ?? "?", privacy: .public)")
            }
            return extracted
        } catch {
            Log.producer.info("ArticleFetcher: fetch failed (\(error, privacy: .public)) — falling back to summary")
            return nil
        }
    }

    /// Minimum extracted length before we trust the result — anything
    /// shorter is boilerplate/consent-wall junk, not an article.
    private static let minUsableChars = 200

    static func extractBody(html: String, maxChars: Int) -> String? {
        var work = html
        // Drop whole non-content blocks (case-insensitive, dot matches newlines).
        for tag in ["script", "style", "nav", "header", "footer", "aside", "noscript", "form", "svg"] {
            work = work.replacingOccurrences(
                of: "<\(tag)\\b[^>]*>.*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Collect <p>…</p> contents in document order.
        var paragraphs: [String] = []
        let pattern = "<p\\b[^>]*>(.*?)</p>"
        if let regex = try? NSRegularExpression(pattern: pattern,
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let ns = work as NSString
            for match in regex.matches(in: work, range: NSRange(location: 0, length: ns.length)) {
                let inner = ns.substring(with: match.range(at: 1))
                let text = stripTagsAndEntities(inner)
                // Skip obvious chrome: very short fragments rarely carry story text.
                if text.count >= 60 { paragraphs.append(text) }
            }
        }
        let joined = paragraphs.joined(separator: " ")
        guard joined.count >= minUsableChars else { return nil }
        return truncateAtWordBoundary(joined, maxChars: maxChars)
    }

    private static func stripTagsAndEntities(_ s: String) -> String {
        var result = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " "), ("&ndash;", "–"),
            ("&mdash;", "—"), ("&hellip;", "…"), ("&rsquo;", "'"), ("&lsquo;", "'"),
            ("&rdquo;", "\""), ("&ldquo;", "\""),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncateAtWordBoundary(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let prefix = String(text.prefix(maxChars))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        }
        return prefix
    }
}
```

- [ ] **Step 4: Regenerate project and run tests**

Run: `xcodegen generate && xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Patter/Services/ArticleFetching.swift Patter/Services/ArticleFetcher.swift PatterTests/ArticleFetcherTests.swift Patter.xcodeproj
git commit -m "feat(news): add ArticleFetcher with heuristic body extraction"
```

---

### Task 4: Prompt plumbing (DJContext, DJPromptTemplate, DJBrain)

**Files:**
- Modify: `Patter/Services/DJBrainProtocol.swift` (DJContext fields)
- Modify: `Patter/Services/DJPromptTemplate.swift` (level guidance, ARTICLE TEXT, guardrail)
- Modify: `Patter/Services/DJBrain.swift` (extended response struct, per-level truncation cap, ARTICLE TEXT in leak list, pass articleBody)
- Test: `PatterTests/DJBrainTests.swift` (append tests)

**Interfaces:**
- Consumes: `NewsVerbosity` (Task 1).
- Produces:
  - `DJContext.newsVerbosity: NewsVerbosity` and `DJContext.articleBody: String?` — declared as `var` with defaults (`.standard` / `nil`) so every existing construction site compiles unchanged.
  - `DJPromptTemplate.buildPrompt(context:newsTopic:newsSummary:articleBody:)` — `articleBody` defaulted to `nil`.
  - `@Generable struct DJScriptResponseExtended` in DJBrain.

- [ ] **Step 1: Write the failing tests**

Append to `PatterTests/DJBrainTests.swift` (match its existing helper for building a `DJContext`; if it has none, construct inline as below — all new fields have defaults, so the existing tests keep compiling):

```swift
@Test func newsGuidanceVariesByVerbosity() {
    let headline = NewsHeadline(id: UUID(), title: "T", source: "s",
                                url: URL(string: "https://example.com")!,
                                publishedAt: Date(), summary: "sum")
    func instructions(_ level: NewsVerbosity) -> String {
        let ctx = DJContext(
            placement: .betweenSongs, persona: .default,
            upcomingTrack: Track.fixture(), recentTracks: [],
            timeOfDay: .afternoon, currentTimeString: "2:11 PM",
            newsHeadline: headline, listenerName: nil, feedback: nil,
            newsVerbosity: level
        )
        return DJPromptTemplate.instructions(context: ctx)
    }
    #expect(instructions(.standard).contains("4–5 sentences, 60–100 words"))
    #expect(instructions(.detailed).contains("120–180 words"))
    #expect(instructions(.deepDive).contains("220–320 words"))
    #expect(instructions(.brief).contains("at most 1–2 sentences"))
}

@Test func newsInstructionsIncludeArticleFactGuardrail() {
    let headline = NewsHeadline(id: UUID(), title: "T", source: "s",
                                url: URL(string: "https://example.com")!,
                                publishedAt: Date(), summary: "sum")
    let ctx = DJContext(
        placement: .betweenSongs, persona: .default,
        upcomingTrack: Track.fixture(), recentTracks: [],
        timeOfDay: .afternoon, currentTimeString: "2:11 PM",
        newsHeadline: headline, listenerName: nil, feedback: nil,
        newsVerbosity: .deepDive
    )
    let instructions = DJPromptTemplate.instructions(context: ctx)
    #expect(instructions.contains("State only facts that appear in the NEWS SUMMARY or ARTICLE TEXT"))
}

@Test func promptIncludesArticleTextOnlyWhenBodyPresent() {
    let headline = NewsHeadline(id: UUID(), title: "Big Story", source: "s",
                                url: URL(string: "https://example.com")!,
                                publishedAt: Date(), summary: "sum")
    let ctx = DJContext(
        placement: .betweenSongs, persona: .default,
        upcomingTrack: Track.fixture(), recentTracks: [],
        timeOfDay: .afternoon, currentTimeString: "2:11 PM",
        newsHeadline: headline, listenerName: nil, feedback: nil,
        newsVerbosity: .deepDive, articleBody: "Full article body text here."
    )
    let withBody = DJPromptTemplate.buildPrompt(context: ctx, newsTopic: "Big Story",
                                                newsSummary: "sum",
                                                articleBody: ctx.articleBody)
    #expect(withBody.contains("ARTICLE TEXT: Full article body text here."))

    let without = DJPromptTemplate.buildPrompt(context: ctx, newsTopic: "Big Story",
                                               newsSummary: "sum", articleBody: nil)
    #expect(!without.contains("ARTICLE TEXT"))
}

@Test func sanitizerStripsArticleTextLeakage() {
    let brain = DJBrain()
    let leaked = "Great song coming up. ARTICLE TEXT: the model echoed the prompt"
    #expect(brain.sanitizePromptLeakage(leaked) == "Great song coming up. ")
}

@Test func standardPromptUnchangedByNewFields() {
    // Regression guard: default-verbosity prompt must be identical to the
    // pre-feature output for the same inputs.
    let headline = NewsHeadline(id: UUID(), title: "T", source: "s",
                                url: URL(string: "https://example.com")!,
                                publishedAt: Date(), summary: "context blurb")
    let ctx = DJContext(
        placement: .betweenSongs, persona: .default,
        upcomingTrack: Track.fixture(), recentTracks: [],
        timeOfDay: .afternoon, currentTimeString: "2:11 PM",
        newsHeadline: headline, listenerName: nil, feedback: nil
    )
    let prompt = DJPromptTemplate.buildPrompt(context: ctx, newsTopic: "T",
                                              newsSummary: "context blurb", articleBody: nil)
    #expect(prompt.contains("NEWS SUMMARY: context blurb"))
    #expect(!prompt.contains("ARTICLE TEXT"))
}
```

If `Track.fixture()` doesn't exist in the test target, use whatever Track-construction helper `DJBrainTests` already uses (a plain `Track(...)` literal is fine); keep the assertions identical.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | grep -E "error" | head`
Expected: compile errors — `newsVerbosity` not a member of `DJContext`; `buildPrompt` has no `articleBody` parameter

- [ ] **Step 3: Implement**

`DJBrainProtocol.swift` — add to `DJContext` after `feedback`:

```swift
    /// News coverage depth + optional full-article body (fetched by Producer
    /// for .detailed/.deepDive only). Defaults keep existing construction
    /// sites and .standard behavior unchanged.
    var newsVerbosity: NewsVerbosity = .standard
    var articleBody: String? = nil
```

`DJPromptTemplate.swift`:
1. In `instructions(context:)`, replace the news block's last paragraph. Old text (delete):

```
            If a NEWS SUMMARY field is present, give the listener 1–2 sentences of actual context on
            the story — what happened, who's involved, why it matters — then bridge back by naming
            the NEXT SONG. If only a NEWS TOPIC is present, mention it briefly in one sentence and
            do not invent article details. For news segments with a summary, override the usual length
            guidance: aim for 4–5 sentences, 60–100 words.
```

New text:

```swift
        if context.newsHeadline != nil {
            instructions += """


            A news topic and (usually) a short context blurb are provided below. You MUST weave them
            into the script — paraphrase naturally, NEVER recite the headline or blurb verbatim. Do not
            ignore them; the listener has explicitly opted in to hear news. The news topic is only a
            quick aside right now, not a later tease and not the next item in the music queue.

            If a NEWS SUMMARY field is present, give the listener actual context on the story — what
            happened, who's involved, why it matters — then bridge back by naming the NEXT SONG. If an
            ARTICLE TEXT field is present, it is the article itself: draw your details from it.
            State only facts that appear in the NEWS SUMMARY or ARTICLE TEXT. If a detail is not
            there, do not invent or embellish it. If only a NEWS TOPIC is present, mention it briefly
            in one sentence and do not invent article details. For news segments with a summary,
            override the usual length guidance: \(context.newsVerbosity.promptGuidance)
            """
        }
```

2. `buildPrompt` signature gains a defaulted parameter and appends the field after the `NEWS SUMMARY` part:

```swift
    static func buildPrompt(context: DJContext, newsTopic: String?, newsSummary: String?,
                            articleBody: String? = nil) -> String {
```

```swift
            if let articleBody, !articleBody.isEmpty {
                parts.append("ARTICLE TEXT: \(articleBody)")
            }
```

(inside the existing `if let newsTopic { … }` block, after the `NEWS SUMMARY` append.)

`DJBrain.swift`:
1. Add next to `DJScriptResponse`:

```swift
@Generable
struct DJScriptResponseExtended {
    @Guide(description: "Only the spoken radio DJ break covering a news story in depth. Complete sentences, 120 to 320 words. No labels, notes, URLs, lists, or repeated facts.")
    let script: String
}
```

2. In `generateScript`, pass the body and select the response type + truncation cap by level:

```swift
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: newsTopic,
                                                  newsSummary: newsSummary,
                                                  articleBody: context.articleBody)
```

and replace the fixed respond/truncate calls:

```swift
        let useExtended = context.newsHeadline != nil
            && (context.newsVerbosity == .detailed || context.newsVerbosity == .deepDive)
            && context.articleBody != nil
        let script: String
        if useExtended {
            let response = try await session.respond(to: prompt, generating: DJScriptResponseExtended.self)
            script = response.content.script.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let response = try await session.respond(to: prompt, generating: DJScriptResponse.self)
            script = response.content.script.trimmingCharacters(in: .whitespacesAndNewlines)
        }
```

and at the end:

```swift
        let cap = useExtended ? context.newsVerbosity.scriptCharCap : 500
        return truncateAtSentenceBoundary(guarded, maxChars: cap)
```

3. Add `"ARTICLE TEXT"` to the `promptLabels` array in `sanitizePromptLeakage` (before `"NEXT SONG"`).

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Patter/Services/DJBrainProtocol.swift Patter/Services/DJPromptTemplate.swift Patter/Services/DJBrain.swift PatterTests/DJBrainTests.swift
git commit -m "feat(news): thread verbosity + article body through prompt pipeline"
```

---

### Task 5: Producer — fetch-when-needed + fallback

**Files:**
- Modify: `Patter/Services/Producer.swift` (Config field, fetcher injection, generateSegment)
- Test: `PatterTests/ProducerTests.swift` (append tests), `PatterTests/Fakes.swift` (fake fetcher)

**Interfaces:**
- Consumes: `ArticleFetching` (Task 3), `NewsVerbosity` (Task 1), `DJContext.newsVerbosity/articleBody` (Task 4).
- Produces: `Producer.Config.newsVerbosity: NewsVerbosity` (defaulted `.default`); `Producer.init` gains `articleFetcher: any ArticleFetching = ArticleFetcher()`.

- [ ] **Step 1: Add fake + failing tests**

`PatterTests/Fakes.swift` — append:

```swift
final class FakeArticleFetcher: ArticleFetching, @unchecked Sendable {
    var result: String?
    var requestedURLs: [URL] = []
    var requestedMaxChars: [Int] = []
    func body(for url: URL, maxChars: Int) async -> String? {
        requestedURLs.append(url)
        requestedMaxChars.append(maxChars)
        return result
    }
}
```

`PatterTests/ProducerTests.swift` — append (follow the suite's existing setup: it builds `Producer(coordinator:brain:voice:rssFetcher:)` with fakes; extend that call with `articleFetcher:` and a `FakeRSSFetcher` primed with one headline, matching how the existing news tests prime it):

```swift
@Test func standardVerbosityNeverFetchesArticle() async {
    let (producer, _, fetcher) = makeProducerWithNews(verbosity: .standard)
    _ = await producer.testGenerateSegment()   // use the suite's existing segment-trigger helper
    #expect(fetcher.requestedURLs.isEmpty)
}

@Test func deepDiveFetchesArticleWithCap() async {
    let (producer, brain, fetcher) = makeProducerWithNews(verbosity: .deepDive)
    fetcher.result = "ARTICLE BODY TEXT"
    _ = await producer.testGenerateSegment()
    #expect(fetcher.requestedMaxChars == [3500])
    #expect(brain.lastContext?.articleBody == "ARTICLE BODY TEXT")
    #expect(brain.lastContext?.newsVerbosity == .deepDive)
}

@Test func fetchFailureFallsBackToStandard() async {
    let (producer, brain, fetcher) = makeProducerWithNews(verbosity: .deepDive)
    fetcher.result = nil
    _ = await producer.testGenerateSegment()
    #expect(brain.lastContext?.articleBody == nil)
    #expect(brain.lastContext?.newsVerbosity == .standard)   // spec: nil body ⇒ behave as .standard
}
```

Adapt the scaffolding to the suite's real helpers: `makeProducerWithNews` is shorthand for "construct Producer exactly as the neighboring news tests do, but with `config: .init(djEnabled: true, newsEnabled: true, newsVerbosity: <level>)` and the fake fetcher injected"; `testGenerateSegment` is shorthand for whatever entry point the existing tests use to force a segment (e.g. the prime/opening-intro path used by `primeSegmentInsertsAfterCurrentTrack`). `FakeDJBrain` must record the context it receives — if it doesn't already, add `var lastContext: DJContext?` set inside its `generateScript`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | grep -E "error" | head`
Expected: compile errors — `Config` has no `newsVerbosity`; `Producer.init` has no `articleFetcher`

- [ ] **Step 3: Implement**

`Producer.swift`:
1. `Config` gains `var newsVerbosity: NewsVerbosity = .default` (and add it to the `default` static if that initializer lists fields explicitly).
2. Stored property + init parameter:

```swift
    private let articleFetcher: any ArticleFetching
```

`init(... rssFetcher: any RSSFetcherProtocol, articleFetcher: any ArticleFetching = ArticleFetcher(), ...)` with `self.articleFetcher = articleFetcher`.

3. In `generateSegment(upcomingTrack:placement:)`, after `let headline = await fetchTopHeadlineIfEnabled()`:

```swift
        // Detailed/Deep Dive: pull the article body; on any failure fall back
        // to Standard behavior (spec rule — the DJ never blocks on a website).
        var effectiveVerbosity = config.newsVerbosity
        var articleBody: String? = nil
        if let headline, effectiveVerbosity.needsArticleFetch,
           let cap = effectiveVerbosity.articleBodyCharCap {
            articleBody = await articleFetcher.body(for: headline.url, maxChars: cap)
            if articleBody == nil {
                Log.producer.info("Article fetch failed for \(headline.source, privacy: .public) — using Standard verbosity")
                effectiveVerbosity = .standard
            }
        }
```

and in the `DJContext(...)` construction add:

```swift
            newsVerbosity: effectiveVerbosity,
            articleBody: articleBody
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **` (all suites — the existing Producer tests must still pass with the defaulted parameter)

- [ ] **Step 5: Commit**

```bash
git add Patter/Services/Producer.swift PatterTests/ProducerTests.swift PatterTests/Fakes.swift
git commit -m "feat(news): Producer fetches article body for high verbosity with standard fallback"
```

---

### Task 6: Settings UI + RootView wiring

**Files:**
- Modify: `Patter/Views/Settings/NewsSection.swift` (picker + footer + one-shot alert)
- Modify: `Patter/App/RootView.swift` (config plumbing + onChange)

**Interfaces:**
- Consumes: `SettingsViewModel.newsVerbosity` / `hasSeenDeepDiveWarning` / `markDeepDiveWarned()` (Task 2), `Producer.Config.newsVerbosity` (Task 5).

- [ ] **Step 1: NewsSection picker + alert**

In `NewsSection.swift`, add state and the control inside `newsSection`'s `Section`, after the existing Frequency picker:

```swift
    @State private var showDeepDiveWarning = false
    @State private var verbosityBeforeDeepDive: NewsVerbosity = .default
```

```swift
            Picker("News Detail", selection: $vm.newsVerbosity) {
                ForEach(NewsVerbosity.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!vm.djEnabled || !vm.newsEnabled)
            .onChange(of: vm.newsVerbosity) { old, new in
                if new == .deepDive && !vm.hasSeenDeepDiveWarning {
                    verbosityBeforeDeepDive = old
                    showDeepDiveWarning = true
                } else {
                    vm.save()
                }
            }
            .alert("Deep Dive Takes Longer", isPresented: $showDeepDiveWarning) {
                Button("Use Deep Dive") {
                    vm.markDeepDiveWarned()
                    vm.save()
                }
                Button("Cancel", role: .cancel) {
                    vm.newsVerbosity = verbosityBeforeDeepDive
                }
            } message: {
                Text("Deep Dive downloads the full article and generates a longer segment. Expect a noticeably longer wait before news segments play.")
            }
```

Add a `footer:` to that `Section` (or extend the existing one) showing `Text(vm.newsVerbosity.settingsDescription)`.

- [ ] **Step 2: RootView wiring**

In `RootView.swift`:
1. `producerConfig()` gains `newsVerbosity: settings.newsVerbosity,` (after `newsFrequency`).
2. Add alongside the other config observers (line ~46):

```swift
                    .onChange(of: settings.newsVerbosity) { _, _ in updateProducerConfig() }
```

- [ ] **Step 3: Build both platforms + full test run**

Run:
```bash
xcodebuild test -scheme Patter -destination 'platform=macOS' 2>&1 | tail -3
xcodebuild build -scheme Patter -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "^\*\* BUILD" 
```
Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Patter/Views/Settings/NewsSection.swift Patter/App/RootView.swift
git commit -m "feat(news): verbosity picker with one-time Deep Dive warning"
```

---

### Task 7: Manual device verification (Andrew) + tracker update

- [ ] **Step 1:** On iPhone: set Detailed → play until a news segment fires → confirm ~paragraph coverage, facts match the article, latency acceptable within the 35 s pre-render lead.
- [ ] **Step 2:** Set Deep Dive (first time) → confirm the alert appears once, Cancel reverts, confirming proceeds; segment gives multi-paragraph coverage.
- [ ] **Step 3:** Pick a paywalled feed item (or airplane-mode the fetch) → confirm the segment still plays at Standard depth.
- [ ] **Step 4:** Consult patter-pm to log the shipped feature in `docs/project-tracker.md` (§2 entry + backlog/K38 cross-refs: Deep Dive materially increases generation time; if it regularly misses the pre-render window, tune `articleBodyCharCap` down as the first lever).
