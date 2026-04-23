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
    @Guide(description: "A radio DJ monologue: 2 to 4 complete sentences, 30-70 words. Reference the music, the time of day, or the vibe. Always a complete thought — never a fragment.")
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

        You are a real human radio DJ on the mic between songs. Sound like a person talking, not writing —
        casual contractions, natural rhythm, one or two offhand observations. Always 2 to 4 complete
        sentences, 30-70 words. Vary WHAT you talk about between segments, not the length.

        Hard rules:
        - Sound conversational. AVOID flowery or review-style phrasing like "melancholic beauty",
          "ethereal melody", "timeless elegance", "sonic landscape", "enjoy the journey". Those read as AI,
          not a human on the radio. Plain, direct words instead.
        - Never produce one-liners or fragments.
        - Never say "Here's a script" or "Let me introduce" — just go.
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


            A news headline and (usually) a short context blurb are provided below. You MUST weave them
            into the script — paraphrase naturally, NEVER recite the headline or blurb verbatim. Do not
            ignore them; the listener has explicitly opted in to hear news.

            Give the listener 2–3 sentences of actual context on the story — what happened, who's
            involved, why it matters — before bridging back to the track coming up. For this news
            segment, override the usual length guidance: aim for 4–5 sentences, 60–100 words.
            """
        }
        let session = LanguageModelSession(instructions: instructions)
        let genStart = ContinuousClock.now
        let response = try await session.respond(to: prompt, generating: DJScriptResponse.self)
        let elapsed = ContinuousClock.now - genStart
        let script = response.content.script.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.brain.info("generated in \(String(describing: elapsed), privacy: .public): \(script, privacy: .public)")
        let clean = stripEmoji(script).trimmingCharacters(in: .whitespacesAndNewlines)
        return truncateAtSentenceBoundary(clean, maxChars: 500)
    }

    private func stripEmoji(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            !scalar.properties.isEmojiPresentation && !scalar.properties.isEmojiModifier
        })
    }

    private func buildPrompt(context: DJContext) -> String {
        var parts: [String] = []
        parts.append("Introduce '\(cleanTitle(context.upcomingTrack.title))' by \(context.upcomingTrack.artist).")
        parts.append("Current time: \(context.currentTimeString) (\(context.timeOfDay.rawValue)). If you mention the time, use exactly this value.")

        if let name = context.listenerName, !name.isEmpty {
            parts.append("Listener name: \(name). Address them by name occasionally, not every time.")
        }

        if !context.recentTracks.isEmpty {
            let recent = context.recentTracks.prefix(3)
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
            // this segment. Pass the cleaned title + the feed's summary /
            // description field (HTML-stripped, truncated); system
            // instructions demand paraphrasing over verbatim recital.
            parts.append("News headline to reference: \(cleanHeadline(headline.title))")
            let context = stripHTML(headline.summary)
            if !context.isEmpty {
                let truncated = context.count > 500
                    ? String(context.prefix(500)) + "…"
                    : context
                parts.append("Headline context (paraphrase, never read verbatim): \(truncated)")
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
