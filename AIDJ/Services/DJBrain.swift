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
    @Guide(description: "A short DJ intro, 1-2 sentences total, no more than 30 words. Conversational and punchy.")
    let script: String
}

final class DJBrain: DJBrainProtocol {

    func generateScript(for context: DJContext) async throws -> String {
        let prompt = buildPrompt(context: context)
        print("[DJBrain] prompt: \(prompt)")
        let instructions = """
        \(context.persona.styleDescriptor)
        Rules: Output 1-2 sentences only. Never more than 30 words total. No intros like "Here's" or "And now"—just say it.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: DJScriptResponse.self)
        let script = response.content.script.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[DJBrain] raw response: \(script)")
        return truncateAtSentenceBoundary(script, maxChars: 220)
    }

    private func buildPrompt(context: DJContext) -> String {
        var parts: [String] = []
        parts.append("Introduce '\(context.upcomingTrack.title)' by \(context.upcomingTrack.artist).")
        parts.append("Time: \(context.timeOfDay.rawValue).")

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
