# DJ News Verbosity Setting — Design

**Date:** 2026-07-06
**Status:** Approved by Andrew (chat, 2026-07-06)
**Owner:** Andrew P

## Problem

News segments are fixed at one depth: the DJ paraphrases the RSS summary in 4–5 sentences (60–100 words, set by N1.2). Andrew wants an adjustable verbosity — from a 1–2 sentence mention up to a few paragraphs of real detail — with a hard rule that the DJ only states facts from the article itself.

## Decisions already made (do not re-litigate)

- **Full-article fetch is in scope** (Option 1). The two upper levels download the article body; RSS-only was rejected because feed summaries can't support paragraph-depth output.
- **Four presets** (Option B), not a slider.
- **Deep Dive shows a one-time warning popup** about longer generation times.
- Generation stays on-device (Foundation Models, ~3B, ~4k-token context). No cloud LLM.

## The four levels

| Level | Source material | Prompt guidance | Fetches article? |
|---|---|---|---|
| Brief | headline only | 1–2 sentences, topic mention only | No |
| Standard (default) | RSS summary (today's behavior, unchanged) | 4–5 sentences, 60–100 words | No |
| Detailed | article body, trimmed ~1,500 chars | ~6–8 sentences, 120–180 words | Yes |
| Deep Dive | article body, trimmed ~3,500 chars | 2–3 short paragraphs, 220–320 words | Yes |

Existing users see zero change: default is `.standard`.

## Components

### 1. `NewsVerbosity` model
`enum NewsVerbosity: String, Codable, CaseIterable` (`brief`, `standard`, `detailed`, `deepDive`) in Models. Carries per-level constants: display name, prompt guidance text, article-body char cap (nil for brief/standard), needsArticleFetch flag. Pure value type, no service deps (project convention).

### 2. Settings plumbing
- `SettingsViewModel`: new persisted `newsVerbosity` property (UserDefaults, same pattern as `kokoroVoice` etc.), default `.standard`.
- One-shot popup sentinel key: `newsVerbosityDeepDiveWarned` (Bool).

### 3. Settings UI (Feeds/News section)
- Segmented `Picker("News detail", …)` over `NewsVerbosity.allCases`, footer text describing the selected level.
- Selecting `.deepDive` when the sentinel is unset presents an `Alert`: title "Deep Dive takes longer", message "Deep Dive downloads the full article and generates a longer segment. Expect a noticeably longer wait before news segments play."; buttons **Use Deep Dive** (confirms, burns sentinel) / **Cancel** (role .cancel, reverts picker to prior value). Standard HIG alert, no custom UI.

### 4. `ArticleFetcher` service
`struct ArticleFetcher` (protocol-backed like other services, injected into Producer).
- `func body(for url: URL, maxChars: Int) async -> String?`
- `URLSession` GET, ~6 s timeout, follow redirects; bail on non-HTML or non-200.
- Extraction: plain-Swift heuristic, no third-party dep — strip `<script>/<style>/<nav>/<header>/<footer>/<aside>`, collect text of `<p>` runs (regex/`NSAttributedString(html:)` is not used — main-thread + WebKit cost; hand-rolled tag stripping), collapse whitespace, take the longest contiguous paragraph cluster, truncate at word boundary to `maxChars`.
- Quality gate: result under ~200 chars → return nil (extraction junk).
- Returns nil on any failure. **Fallback rule: nil body ⇒ Producer proceeds exactly as `.standard`** (RSS summary, standard guidance). The DJ never blocks or goes silent on a bad website.

### 5. Producer / DJBrain / prompt changes
- Producer: when level `needsArticleFetch`, await `ArticleFetcher.body(for: headline.url, maxChars: cap)` before generation; pass result (or nil) into prompt build.
- `DJPromptTemplate`:
  - News guidance block becomes level-parameterized (replaces the fixed "4–5 sentences, 60–100 words" text).
  - New labeled field `ARTICLE TEXT: …` when a body is present (summary field still included).
  - Guardrail line added to news instructions: *"State only facts that appear in the NEWS SUMMARY or ARTICLE TEXT. If a detail is not there, do not invent or embellish it."*
  - `ARTICLE TEXT` added to `DJBrain.sanitizePromptLeakage` label list.
- `DJBrain` `@Guide` word bounds: widen only when verbosity > standard (level threaded through to generation options so brief/standard keep today's 30–70 guide).

## Constraints & risks

- **Context window:** 3,500-char cap (~875 tokens) + system prompt + metadata stays well inside the 4k-token Foundation Models window.
- **Latency (K38):** generation is already ~4–9 s at standard depth on iPhone; Deep Dive will be materially slower (bigger prompt + 3–4× output tokens) plus longer TTS render. Mitigations: the existing 35 s pre-render lead time, and the warning popup (Andrew's explicit ask). If real-device testing shows Deep Dive regularly missing the pre-render window, that's a tuning follow-up (shrink caps), not a design change.
- **Paywalls/JS sites:** expected to fail extraction often; silent Standard fallback is the designed behavior, not an error state.
- **Privacy:** article fetch is a direct GET of a URL the user's chosen feed already published; no new data shared beyond a normal web request.

## Testing

Unit (macOS suite):
- `NewsVerbosity` constants and persistence round-trip; default `.standard`.
- Prompt template per level: correct guidance text; `ARTICLE TEXT` present only when body given; guardrail line present for news; sanitizer strips `ARTICLE TEXT` leakage.
- Producer fallback: fetcher returns nil ⇒ prompt identical to `.standard` output.
- `ArticleFetcher` extraction against 2–3 HTML fixtures (clean article, boilerplate-heavy page, junk page → nil). Network layer stubbed via protocol.
- Settings: deep-dive sentinel one-shot behavior; cancel reverts selection.

Manual (device): Deep Dive end-to-end on iPhone — segment plays, latency acceptable, content matches article facts.

## Out of scope

- Talk-over/bed music, per-feed verbosity overrides, article caching, cloud summarization, comment/HN metadata enrichment.
