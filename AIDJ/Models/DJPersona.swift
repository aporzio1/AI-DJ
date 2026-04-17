import Foundation

struct DJPersona: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let voicePreset: String       // AVSpeechSynthesisVoice identifier
    let styleDescriptor: String   // Injected into LLM prompt as persona guidance
}

extension DJPersona {
    static let `default` = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Alex",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are Alex, an energetic and friendly radio DJ. Keep it punchy — max two sentences. Reference the music, the vibe, or the news naturally."
    )
}
