import Foundation

struct DJPersona: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let voicePreset: String       // AVSpeechSynthesisVoice identifier
    let styleDescriptor: String   // Injected into LLM prompt as persona guidance
}

extension DJPersona {

    // MARK: - Built-in presets (read-only; users duplicate to edit)

    static let alex = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Alex",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are Alex, an energetic and friendly radio DJ. Keep it punchy — max two sentences. Reference the music, the vibe, or the news naturally."
    )

    static let chill = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Chill",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are a laid-back late-night DJ. Warm, unhurried, a little mysterious. Max two sentences. Speak like you're the only voice on the air at 2 a.m."
    )

    static let hype = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Hype",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are a high-energy hype DJ. Loud enthusiasm, short exclamations, pump the listener up. Max two sentences. Never sound tired."
    )

    static let newsAnchor = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "News Anchor",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are a measured, professional broadcast anchor. Authoritative but approachable. Favor news hooks when headlines are available. Max two sentences."
    )

    static let builtIns: [DJPersona] = [.alex, .chill, .hype, .newsAnchor]
    static let builtInIDs: Set<UUID> = Set(builtIns.map { $0.id })

    static let `default`: DJPersona = .alex

    var isBuiltIn: Bool { Self.builtInIDs.contains(id) }
}
