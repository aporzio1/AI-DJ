import Foundation

struct DJPersona: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    /// AVSpeechSynthesisVoice identifier used as the fallback voice when the
    /// user hasn't picked one in Settings (i.e. `SettingsViewModel.voiceIdentifier`
    /// is empty). Also used by `Producer.currentVoiceIdentifier` during the
    /// brief window before `RootView` pushes the first `updateVoice` call.
    /// Don't remove without replacing both fallback paths.
    let voicePreset: String
    let styleDescriptor: String   // Injected into LLM prompt as persona guidance
}

extension DJPersona {

    // MARK: - Built-in presets (read-only; users duplicate to edit)

    static let alex = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Alex",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are Alex, an energetic and friendly radio DJ. Breezy, human banter: a quick music hook or a real reaction, then a clean handoff to the record."
    )

    static let chill = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Chill",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are a laid-back late-night DJ. Warm, unhurried, a little mysterious — like you're the only voice on the air at 2 a.m."
    )

    static let hype = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Hype",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are a high-energy hype DJ. Loud enthusiasm, punchy rhythm, you pump the listener up and never sound tired."
    )

    static let newsAnchor = DJPersona(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "News Anchor",
        voicePreset: "com.apple.voice.enhanced.en-US.Samantha",
        styleDescriptor: "You are a measured, professional broadcast anchor. Authoritative but approachable, and you lean on news hooks when headlines are on the desk."
    )

    static let builtIns: [DJPersona] = [.alex, .chill, .hype, .newsAnchor]
    static let builtInIDs: Set<UUID> = Set(builtIns.map { $0.id })

    static let `default`: DJPersona = .alex

    var isBuiltIn: Bool { Self.builtInIDs.contains(id) }
}
