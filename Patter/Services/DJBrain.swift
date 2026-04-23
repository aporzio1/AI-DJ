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
        let prompt = buildPrompt(context: context)
        Log.brain.debug("prompt: \(prompt, privacy: .public)")
        var instructions = """
        \(context.persona.styleDescriptor)

        You are a real human radio DJ on the mic between songs. Write only the words spoken aloud.
        Sound like a person talking into the next record: casual contractions, natural rhythm, one
        quick thought, then a clean handoff. Always 2 to 4 complete sentences, 30-70 words.

        Traditional DJ shape:
        - If there was a previous song, acknowledge it once in plain language.
        - If there is news, make it one quick aside unless a summary gives real context.
        - End by naming the upcoming song once.
        - Do not repeat the same song, artist, listener name, or clock time.

        Hard rules:
        - Output the spoken break only. Never read or echo prompt labels like SEGMENT, NEXT SONG,
          NEWS TOPIC, NEWS SUMMARY, Just played, Listener name, or Current time.
        - Match the segment timing exactly. If this is an opening intro, the upcoming song has NOT played yet:
          talk about it as coming up / first / about to play, and never say "I just played" or "we just heard".
          If this is between songs, only "just played" can refer to tracks listed as recently played below,
          never to the upcoming song.
        - Mention the clock time only occasionally. Most announcements should skip the time entirely.
          If you use it, say it once and never repeat it.
        - The news headline is NOT a song, track, artist, album, playlist, or anything that can be "up next".
          "Coming up", "up next", "next", "about to play", and "enjoy the song" may refer ONLY to the song
          in the NEXT SONG field.
        - Never say a news story, news update, article, headline, or topic is "coming up", "up next",
          "after the break", or something to "stay tuned" for. If news is provided, you are talking
          about it now, then returning to the next song.
        - Sound conversational. AVOID flowery or review-style phrasing like "melancholic beauty",
          "ethereal melody", "timeless elegance", "sonic landscape", "enjoy the journey". Those read as AI,
          not a human on the radio. Plain, direct words instead.
        - Never produce one-liners or fragments.
        - Never say "Here's a script" or "Let me introduce" — just go.
        - Do not make a checklist or sequence of short metadata sentences. This should sound like
          one natural radio break, not a readout.
        - Song titles like "7\" Mix" or "(Remastered)" are not part of your script; read the song naturally.
        - No emojis, emoticons, or decorative symbols — your output is spoken aloud by a text-to-speech engine.
        - SPELL OUT INITIALISMS with spaces between letters: "GPT" → "G P T", "AI" → "A I",
          "API" → "A P I", "CEO" → "C E O", "HTTP" → "H T T P", "NPR" → "N P R". The TTS engine
          will otherwise try to pronounce them as made-up words (GPT → "gept"). Only do this for
          initialisms whose letters are pronounced individually. Acronyms pronounced as words
          stay unchanged: NASA, NATO, SCUBA, LASER, etc.
        - For version numbers like "GPT-5.4" spell the initialism and then say the number naturally:
          "G P T five point four". For years, read as normal ("2026" → "twenty twenty-six").

        NEVER invent a radio station name, call letters, frequency, or broadcast identifier ("104.7 FM",
        "KXYZ", "The Rock Station", etc.). This is a personal music app — you are just the voice between
        tracks. If you mention the time, use ONLY the exact current time provided below; never invent a
        clock time or programming schedule.
        """
        if context.newsHeadline != nil {
            instructions += """


            A news topic and (usually) a short context blurb are provided below. You MUST weave them
            into the script — paraphrase naturally, NEVER recite the headline or blurb verbatim. Do not
            ignore them; the listener has explicitly opted in to hear news. The news topic is only a
            quick aside right now, not a later tease and not the next item in the music queue.

            If a NEWS SUMMARY field is present, give the listener 1–2 sentences of actual context on
            the story — what happened, who's involved, why it matters — then bridge back by naming
            the NEXT SONG. If only a NEWS TOPIC is present, mention it briefly in one sentence and
            do not invent article details. For news segments with a summary, override the usual length
            guidance: aim for 4–5 sentences, 60–100 words.
            """
        }
        let session = LanguageModelSession(instructions: instructions)
        let genStart = ContinuousClock.now
        let response = try await session.respond(to: prompt, generating: DJScriptResponse.self)
        let elapsed = ContinuousClock.now - genStart
        let script = response.content.script.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.brain.info("generated in \(String(describing: elapsed), privacy: .public): \(script, privacy: .public)")
        let clean = stripEmoji(script).trimmingCharacters(in: .whitespacesAndNewlines)
        var sanitized = sanitizePromptLeakage(clean)
        sanitized = removeRepeatedTimeMentions(sanitized, currentTimeString: context.currentTimeString)
        sanitized = removeDuplicateSongCallouts(sanitized, context: context)
        if sanitized.isEmpty {
            sanitized = "Up next, \(cleanTitle(context.upcomingTrack.title)) by \(context.upcomingTrack.artist)."
        }
        let guarded = enforceSongNewsBoundary(sanitized, context: context)
        return truncateAtSentenceBoundary(guarded, maxChars: 500)
    }

    private func stripEmoji(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            !scalar.properties.isEmojiPresentation && !scalar.properties.isEmojiModifier
        })
    }

    private func buildPrompt(context: DJContext) -> String {
        var parts: [String] = []
        let upcoming = "'\(cleanTitle(context.upcomingTrack.title))' by \(context.upcomingTrack.artist)"
        switch context.placement {
        case .opening:
            parts.append("SEGMENT: Opening intro before any music has played.")
            parts.append("NEXT SONG: \(upcoming). Refer to this song only as coming up, up first, or about to play. Do not say it just played.")
        case .betweenSongs:
            parts.append("SEGMENT: Between-song break.")
            parts.append("NEXT SONG: \(upcoming). Refer to this song only as coming up, next, or about to play. Do not say it just played.")
        }
        parts.append("Current time: \(context.currentTimeString) (\(context.timeOfDay.rawValue)). Mention the time only if it adds variety; if you mention it, use exactly this value.")

        if let name = context.listenerName, !name.isEmpty {
            parts.append("Listener name: \(name). Address them by name occasionally, not every time.")
        }

        if !context.recentTracks.isEmpty {
            let recent = context.recentTracks.suffix(3)
                .map { "\(cleanTitle($0.title)) by \($0.artist)" }
                .joined(separator: ", ")
            parts.append("Just played: \(recent).")
        }

        if let feedback = context.feedback, !feedback.isEmpty {
            if !feedback.likes.isEmpty {
                parts.append("Recently liked: \(feedback.likes.joined(separator: "; ")). Reference naturally if a connection fits; never list them.")
            }
            if !feedback.dislikes.isEmpty {
                parts.append("Recently skipped/disliked: \(feedback.dislikes.joined(separator: "; ")). Avoid anything that sounds like those.")
            }
        }

        if let headline = context.newsHeadline {
            // Producer already gated on NewsFrequency probability before
            // fetching — if a headline is here, the user asked for news on
            // this segment. Pass the cleaned title plus only usable summary
            // text. HN RSS descriptions are often just "Article URL",
            // "Comments URL", points, and comment count; those are prompt
            // metadata, not speakable news context.
            parts.append("NEWS TOPIC, NOT A SONG: \(cleanHeadline(headline.title))")
            if let newsContext = usableNewsContext(from: headline.summary) {
                let truncated = newsContext.count > 500
                    ? String(newsContext.prefix(500)) + "…"
                    : newsContext
                parts.append("NEWS SUMMARY: \(truncated)")
            }
        }

        return parts.joined(separator: " ")
    }

    /// Strips parenthetical remix/version tags and quote characters that confuse the model.
    private func cleanTitle(_ title: String) -> String {
        var cleaned = title
        if let parenIndex = cleaned.firstIndex(of: "(") {
            cleaned = String(cleaned[..<parenIndex])
        }
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
        return cleaned.trimmingCharacters(in: .whitespaces)
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

    func usableNewsContext(from summary: String) -> String? {
        var result = stripHTML(summary)
        result = result.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
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
        let songTitle = normalizedForBoundaryCheck(cleanTitle(context.upcomingTrack.title))
        let artist = normalizedForBoundaryCheck(context.upcomingTrack.artist)
        if (!songTitle.isEmpty && !normalizedGuarded.contains(songTitle)) || (!artist.isEmpty && !normalizedGuarded.contains(artist)) {
            guarded += " Up next, \(cleanTitle(context.upcomingTrack.title)) by \(context.upcomingTrack.artist)."
        }
        return guarded
    }

    func sanitizePromptLeakage(_ script: String) -> String {
        let promptLabels = [
            "NEWS TOPIC",
            "NEWS CONTEXT",
            "NEWS SUMMARY",
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

        cleaned = cleaned.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
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
        let songTitle = normalizedForBoundaryCheck(cleanTitle(context.upcomingTrack.title))
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

    private func splitSentences(_ text: String) -> [String] {
        text.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0 + "." }
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
