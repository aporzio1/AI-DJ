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
    @Guide(description: "A radio DJ monologue. Vary the length: sometimes a full DJ moment with personality and context (2-4 sentences), sometimes just a quick callout (one sentence). No more than 60 words total.")
    let script: String
}

final class DJBrain: DJBrainProtocol {

    func generateScript(for context: DJContext) async throws -> String {
        let prompt = buildPrompt(context: context)
        print("[DJBrain] prompt: \(prompt)")
        let instructions = """
        \(context.persona.styleDescriptor)

        You are a real radio DJ. Bring energy and personality. Reference the music, the time of day, or the vibe.
        Mix up your length: some segments should be a full DJ moment (2-4 sentences, ~40-60 words), others a
        quick callout (one short sentence). Real DJs don't sound the same every time.
        Never say stuff like "Here's a script" or "Let me introduce"—just go.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: DJScriptResponse.self)
        let script = response.content.script.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[DJBrain] raw response: \(script)")
        return truncateAtSentenceBoundary(script, maxChars: 500)
    }

    private func buildPrompt(context: DJContext) -> String {
        var parts: [String] = []
        parts.append("Introduce '\(context.upcomingTrack.title)' by \(context.upcomingTrack.artist).")
        parts.append("Time: \(context.timeOfDay.rawValue).")

        if let name = context.listenerName, !name.isEmpty {
            parts.append("Listener name: \(name). Address them by name occasionally, not every time.")
        }

        if !context.recentTracks.isEmpty {
            let recent = context.recentTracks.prefix(3)
                .map { "\($0.title) by \($0.artist)" }
                .joined(separator: ", ")
            parts.append("Just played: \(recent).")
        }

        if let headline = context.newsHeadline {
            parts.append("Optional news hook: \(headline.title).")
        }

        return parts.joined(separator: " ")
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
