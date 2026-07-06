import Foundation
import FoundationModels

/// Checks Apple Intelligence availability. Returns a human-readable reason string if unavailable, nil if available.
func appleIntelligenceUnavailabilityReason() -> String? {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
        return nil
    case .unavailable(let reason):
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled on this device. Enable it in Settings → Apple Intelligence & Siri."
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence."
        case .modelNotReady:
            return "Apple Intelligence model is still downloading. Try again shortly."
        default:
            return "Apple Intelligence is not available."
        }
    }
}

@Generable
struct DJScriptResponse {
    @Guide(description: "Only the spoken radio DJ break. 2 to 4 complete sentences, 30-70 words. No labels, notes, URLs, lists, or repeated facts.")
    let script: String
}

@Generable
struct DJScriptResponseExtended {
    @Guide(description: "Only the spoken radio DJ break covering a news story in depth. Complete sentences, 120 to 320 words. No labels, notes, URLs, lists, or repeated facts.")
    let script: String
}

final class DJBrain: DJBrainProtocol {

    /// Touch the on-device LLM once to force model load. Dramatically reduces
    /// first-segment latency (cold start can take 30-60s; warm is ~1-3s).
    func warmUp() async {
        let start = ContinuousClock.now
        Log.brain.info("warming up Foundation Models…")
        let session = LanguageModelSession(instructions: "You are a radio DJ.")
        _ = try? await session.respond(to: "Say hi in three words.")
        let elapsed = ContinuousClock.now - start
        Log.brain.info("warm-up complete in \(String(describing: elapsed), privacy: .public)")
    }

    func generateScript(for context: DJContext) async throws -> String {
        let newsTopic = context.newsHeadline.map { cleanHeadline($0.title) }
        let newsSummary = context.newsHeadline.flatMap { usableNewsContext(from: $0.summary) }
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: newsTopic,
                                                  newsSummary: newsSummary,
                                                  articleBody: context.articleBody)
        Log.brain.debug("prompt: \(prompt, privacy: .public)")
        let instructions = DJPromptTemplate.instructions(context: context)
        let session = LanguageModelSession(instructions: instructions)
        let genStart = ContinuousClock.now
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
        let elapsed = ContinuousClock.now - genStart
        Log.brain.info("generated in \(String(describing: elapsed), privacy: .public): \(script, privacy: .public)")
        let clean = stripEmoji(script).trimmingCharacters(in: .whitespacesAndNewlines)
        var sanitized = sanitizePromptLeakage(clean)
        sanitized = removeRepeatedTimeMentions(sanitized, currentTimeString: context.currentTimeString)
        sanitized = removeDuplicateSongCallouts(sanitized, context: context)
        if sanitized.isEmpty {
            sanitized = "Up next, \(DJPromptTemplate.cleanTitle(context.upcomingTrack.title)) by \(context.upcomingTrack.artist)."
        }
        let guarded = enforceSongNewsBoundary(sanitized, context: context)
        let cap = useExtended ? context.newsVerbosity.scriptCharCap : 500
        return truncateAtSentenceBoundary(guarded, maxChars: cap)
    }

    private func stripEmoji(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            !scalar.properties.isEmojiPresentation && !scalar.properties.isEmojiModifier
        })
    }

    /// Best-effort strip of HTML tags and decoded entities from an RSS
    /// description / summary field. Feeds often embed `<p>`, `<br>`,
    /// `&nbsp;`, etc. — we want plain text in the prompt so the model
    /// doesn't paraphrase tag syntax into the spoken script.
    private func stripHTML(_ s: String) -> String {
        var result = s
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " "),
            ("&ndash;", "–"),
            ("&mdash;", "—"),
            ("&hellip;", "…"),
            ("&rsquo;", "'"),
            ("&lsquo;", "'"),
            ("&rdquo;", "\""),
            ("&ldquo;", "\""),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips bare URLs (`https?://\S+`) — shared by the news-summary cleanup
    /// below and by `sanitizePromptLeakage`'s leaked-metadata cleanup.
    private func stripURLs(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
    }

    func usableNewsContext(from summary: String) -> String? {
        var result = stripHTML(summary)
        result = stripURLs(result)
        result = result.replacingOccurrences(of: #"\bArticle URL:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bComments URL:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bPoints:\s*\d+\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"#\s*Comments:\s*\d+\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        let words = result.split(whereSeparator: { !$0.isLetter })
        guard words.count >= 6 else { return nil }
        return result
    }

    /// Strip awkward prefixes so the DJ doesn't read "Show HN: …" aloud.
    private func cleanHeadline(_ title: String) -> String {
        var cleaned = title
        let prefixes = ["Show HN:", "Ask HN:", "Tell HN:", "Launch HN:", "[PDF]", "[Video]"]
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    func enforceSongNewsBoundary(_ script: String, context: DJContext) -> String {
        guard let headline = context.newsHeadline else { return script }

        let headlineNeedle = normalizedForBoundaryCheck(cleanHeadline(headline.title))
        let nextPhrases = ["coming up", "up next", "about to play", "next song", "enjoy the song", "after the break", "stay tuned"]
        let newsTerms = ["news", "story", "article", "headline", "topic", "update"]
        let sentences = splitSentences(script)
        let cleanedSentences = sentences.compactMap { sentence -> String? in
            let normalized = normalizedForBoundaryCheck(sentence)
            let mentionsHeadline = !headlineNeedle.isEmpty && normalized.contains(headlineNeedle)
            let mentionsNews = newsTerms.contains { normalized.contains($0) }
            let usesNextLanguage = nextPhrases.contains { normalized.contains($0) }
            if (mentionsHeadline || mentionsNews) && usesNextLanguage {
                return nil
            }
            return sentence
        }

        var guarded = cleanedSentences.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if guarded.isEmpty {
            guarded = "A quick story caught my eye before the next track."
        }

        let normalizedGuarded = normalizedForBoundaryCheck(guarded)
        let songTitle = normalizedForBoundaryCheck(DJPromptTemplate.cleanTitle(context.upcomingTrack.title))
        let artist = normalizedForBoundaryCheck(context.upcomingTrack.artist)
        if (!songTitle.isEmpty && !normalizedGuarded.contains(songTitle)) || (!artist.isEmpty && !normalizedGuarded.contains(artist)) {
            guarded += " Up next, \(DJPromptTemplate.cleanTitle(context.upcomingTrack.title)) by \(context.upcomingTrack.artist)."
        }
        return guarded
    }

    func sanitizePromptLeakage(_ script: String) -> String {
        let promptLabels = [
            "NEWS TOPIC",
            "NEWS CONTEXT",
            "NEWS SUMMARY",
            "ARTICLE TEXT",
            "NEXT SONG",
            "SEGMENT:",
            "Current time:",
            "Listener name:",
            "Just played:",
            "Recently liked:",
            "Recently skipped",
            "Article URL:",
            "Comments URL:",
            "Points:",
            "# Comments:",
        ]

        var cleaned = script
        if let firstLeak = promptLabels
            .compactMap({ cleaned.range(of: $0, options: [.caseInsensitive])?.lowerBound })
            .min()
        {
            cleaned = String(cleaned[..<firstLeak])
        }

        cleaned = stripURLs(cleaned)
        cleaned = cleaned.replacingOccurrences(
            of: #"\b[a-z0-9.-]+\s*\.\s*(com|org|net|io|dev|edu|gov)\S*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedForBoundaryCheck(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeRepeatedTimeMentions(_ script: String, currentTimeString: String) -> String {
        guard !currentTimeString.isEmpty else { return script }
        var hasKeptTime = false
        let cleaned = splitSentences(script).compactMap { sentence -> String? in
            guard sentence.localizedCaseInsensitiveContains(currentTimeString) else { return sentence }
            if !hasKeptTime {
                hasKeptTime = true
                return sentence
            }

            let withoutTime = sentence
                .replacingOccurrences(of: currentTimeString, with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: #"^\s*[,.;:!-]+\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

            return withoutTime.isEmpty ? nil : withoutTime + "."
        }
        return cleaned.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeDuplicateSongCallouts(_ script: String, context: DJContext) -> String {
        let songTitle = normalizedForBoundaryCheck(DJPromptTemplate.cleanTitle(context.upcomingTrack.title))
        let artist = normalizedForBoundaryCheck(context.upcomingTrack.artist)
        guard !songTitle.isEmpty else { return script }

        var hasSongCallout = false
        let cleaned = splitSentences(script).compactMap { sentence -> String? in
            let normalized = normalizedForBoundaryCheck(sentence)
            let mentionsSong = normalized.contains(songTitle)
            let mentionsArtist = artist.isEmpty || normalized.contains(artist)
            guard mentionsSong && mentionsArtist else { return sentence }

            if hasSongCallout {
                return nil
            }
            hasSongCallout = true
            return sentence
        }
        return cleaned.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split a script on sentence-terminating punctuation while preserving the
    /// original `.`/`!`/`?` so AVSpeechSynthesizer can apply the right intonation.
    /// A trailing fragment without a terminator gets `.` appended so downstream
    /// callers (which rejoin with a space) produce well-formed sentences.
    /// Internal access (not private) so DJBrainTests can exercise it directly.
    func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            sentences.append(trailing + ".")
        }
        return sentences
    }

    private func truncateAtSentenceBoundary(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let prefix = String(text.prefix(maxChars))
        // Try to cut at the last sentence-ending punctuation
        if let lastTerminator = prefix.lastIndex(where: { ".!?".contains($0) }) {
            return String(prefix[...lastTerminator])
        }
        // Fall back to cutting at last space
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "…"
        }
        return prefix
    }
}
