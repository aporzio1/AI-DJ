import Foundation

enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case openAI = "openai"
    // case kokoro = "kokoro"  // Phase 2

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: "System"
        case .openAI: "OpenAI"
        }
    }
}

/// Routes DJ-voice rendering requests to the active provider, with a fallback
/// to SystemDJVoice so a misconfigured cloud provider never stalls playback.
final class DJVoiceRouter: DJVoiceProtocol, @unchecked Sendable {

    private let system: SystemDJVoice
    private let openAI: OpenAIDJVoice

    private let lock = NSLock()
    private var _provider: TTSProvider = .system

    var provider: TTSProvider {
        get { lock.lock(); defer { lock.unlock() }; return _provider }
        set { lock.lock(); _provider = newValue; lock.unlock() }
    }

    init(system: SystemDJVoice = SystemDJVoice(),
         openAI: OpenAIDJVoice = OpenAIDJVoice()) {
        self.system = system
        self.openAI = openAI
    }

    func setOpenAIModel(_ model: OpenAITTSModel) {
        openAI.updateModel(model)
    }

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        let active = provider
        switch active {
        case .system:
            return try await system.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
        case .openAI:
            do {
                return try await openAI.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
            } catch {
                Log.voice.error("OpenAI provider failed (\(error.localizedDescription, privacy: .public)) — falling back to System voice")
                return try await system.renderToFile(script: script, voiceIdentifier: fallbackSystemVoice())
            }
        }
    }

    /// If the user had an OpenAI voice identifier selected, it's not a valid AVSpeech ID.
    /// Pass empty string so SystemDJVoice uses the OS default voice.
    private func fallbackSystemVoice() -> String { "" }
}
