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
        let instructions = """
        \(context.persona.styleDescriptor)

        You are a real radio DJ. Bring energy and personality — reference the music, the time of day, the vibe,
        or what was just playing. Always 2 to 4 complete sentences, 30-70 words. Vary WHAT you talk about
        between segments, not the length. Never produce one-liners or fragments.
        Never say "Here's a script" or "Let me introduce" — just go.
        Song titles like "7\" Mix" or "(Remastered)" are not part of your script; read the song naturally.
        Do not use emojis, emoticons, or decorative symbols — your output is spoken aloud by a text-to-speech engine.
        """
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
        parts.append("Time: \(context.timeOfDay.rawValue).")

        if let name = context.listenerName, !name.isEmpty {
            parts.append("Listener name: \(name). Address them by name occasionally, not every time.")
        }

        if !context.recentTracks.isEmpty {
            let recent = context.recentTracks.prefix(3)
                .map { "\(cleanTitle($0.title)) by \($0.artist)" }
                .joined(separator: ", ")
            parts.append("Just played: \(recent).")
        }

        if let headline = context.newsHeadline {
            parts.append("Optional news hook: \(headline.title).")
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
