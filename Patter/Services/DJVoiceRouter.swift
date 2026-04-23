import Foundation

enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case openAI = "openai"
    case kokoro = "kokoro"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: "Device Voices"
        case .openAI: "OpenAI"
        case .kokoro: "Kokoro (on-device)"
        }
    }
}

/// Routes DJ-voice rendering requests to the active provider, with a fallback
/// to SystemDJVoice so a misconfigured cloud/on-device provider never stalls playback.
final class DJVoiceRouter: DJVoiceProtocol, @unchecked Sendable {

    private let system: SystemDJVoice
    private let openAI: OpenAIDJVoice
    private let kokoro: KokoroDJVoice

    private let lock = NSLock()
    private var _provider: TTSProvider = .system

    var provider: TTSProvider {
        get { lock.lock(); defer { lock.unlock() }; return _provider }
        set { lock.lock(); _provider = newValue; lock.unlock() }
    }

    init(system: SystemDJVoice = SystemDJVoice(),
         openAI: OpenAIDJVoice = OpenAIDJVoice(),
         kokoro: KokoroDJVoice = KokoroDJVoice()) {
        self.system = system
        self.openAI = openAI
        self.kokoro = kokoro
    }

    func setOpenAIModel(_ model: OpenAITTSModel) {
        openAI.updateModel(model)
    }

    // MARK: - Kokoro model management (proxied to the inner KokoroDJVoice)

    var isKokoroModelInstalled: Bool { KokoroDJVoice.isModelInstalled }
    func prepareKokoroModel() async throws { try await kokoro.prepareModel() }
    func removeKokoroModel() async throws { try await kokoro.removeModel() }

    /// Directly render a short sample with the Kokoro provider, ignoring the
    /// currently-active router provider. Used by the Settings voice preview.
    func renderKokoroSample(script: String, voiceIdentifier: String) async throws -> URL {
        try await kokoro.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
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
        case .kokoro:
            do {
                return try await kokoro.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
            } catch {
                Log.voice.error("Kokoro provider failed (\(error.localizedDescription, privacy: .public)) — falling back to System voice")
                return try await system.renderToFile(script: script, voiceIdentifier: fallbackSystemVoice())
            }
        }
    }

    /// If the user had a non-system voice identifier selected, it's not a valid AVSpeech ID.
    /// Pass empty string so SystemDJVoice uses the OS default voice.
    private func fallbackSystemVoice() -> String { "" }
}
