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

final class DJBrain: DJBrainProtocol {

    func generateScript(for context: DJContext) async throws -> String {
        let prompt = buildPrompt(context: context)
        print("[DJBrain] prompt: \(prompt)")
        let session = LanguageModelSession(instructions: context.persona.styleDescriptor)
        let response = try await session.respond(to: prompt)
        let script = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[DJBrain] raw response: \(script)")
        if script.count > 220 {
            return String(script.prefix(220))
        }
        return script
    }

    private func buildPrompt(context: DJContext) -> String {
        var parts: [String] = []

        parts.append("You're about to introduce '\(context.upcomingTrack.title)' by \(context.upcomingTrack.artist).")
        parts.append("Time of day: \(context.timeOfDay.rawValue).")

        if !context.recentTracks.isEmpty {
            let recent = context.recentTracks.prefix(3)
                .map { "\($0.title) by \($0.artist)" }
                .joined(separator: ", ")
            parts.append("Recent tracks: \(recent).")
        }

        if let headline = context.newsHeadline {
            parts.append("News hook (optional): \(headline.title) — \(headline.summary.prefix(100)).")
        }

        parts.append("Write a short DJ intro. Two sentences max. Sound natural and conversational.")
        return parts.joined(separator: " ")
    }
}
