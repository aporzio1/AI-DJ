import Foundation

enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case openAI = "openai"
    case kokoro = "kokoro"
    case sherpaKokoro = "sherpa_kokoro"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: "Device Voices"
        case .openAI: "OpenAI"
        case .kokoro: "Kokoro (on-device)"
        case .sherpaKokoro: "Kokoro CPU (on-device)"
        }
    }
}

/// Routes DJ-voice rendering requests to the active provider, with a fallback
/// to SystemDJVoice so a misconfigured cloud/on-device provider never stalls playback.
final class DJVoiceRouter: DJVoiceProtocol, @unchecked Sendable {

    private let system: SystemDJVoice
    private let openAI: OpenAIDJVoice
    private let kokoro: KokoroDJVoice
    private let sherpa: SherpaKokoroDJVoice

    private let lock = NSLock()
    private var _provider: TTSProvider = .system
    private nonisolated(unsafe) var kokoroStrikes = 0
    private nonisolated(unsafe) var sherpaStrikes = 0

    var provider: TTSProvider {
        get { lock.lock(); defer { lock.unlock() }; return _provider }
        set { lock.lock(); _provider = newValue; lock.unlock() }
    }

    init(system: SystemDJVoice = SystemDJVoice(),
         openAI: OpenAIDJVoice = OpenAIDJVoice(),
         kokoro: KokoroDJVoice = KokoroDJVoice(),
         sherpa: SherpaKokoroDJVoice = SherpaKokoroDJVoice()) {
        self.system = system
        self.openAI = openAI
        self.kokoro = kokoro
        self.sherpa = sherpa
    }

    func setOpenAIModel(_ model: OpenAITTSModel) {
        openAI.updateModel(model)
    }

    // MARK: - Kokoro model management (proxied to the inner KokoroDJVoice)

    var isKokoroModelInstalled: Bool { KokoroDJVoice.isModelInstalled }
    var isSherpaModelInstalled: Bool { SherpaModel.isModelInstalled }
    func prepareSherpaModel(progress: @escaping @Sendable (Double) -> Void) async throws { try await SherpaModel.install(progress: progress) }
    func removeSherpaModel() throws { try SherpaModel.removeModel() }
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
                Log.voice.error("OpenAI provider failed (\(error.localizedDescription, privacy: .public)) — falling back")
                // Kokoro sounds materially more human than the system voices, so
                // prefer it whenever the model is already on disk; system is the
                // always-available floor.
                if KokoroDJVoice.isModelInstalled {
                    do {
                        return try await kokoro.renderToFile(script: script, voiceIdentifier: "")
                    } catch {
                        Log.voice.error("Kokoro fallback failed too — using System voice")
                    }
                }
                return try await system.renderToFile(script: script, voiceIdentifier: fallbackSystemVoice())
            }
        case .sherpaKokoro:
            // CPU Kokoro: no Apple ML, no speech server. Two misses and it
            // sits out the session; its only floor is System (which is
            // itself unreliable on 27 betas — failure surfaces as a skipped
            // segment, music rides on).
            if sherpaStrikes >= 2 {
                return try await system.renderToFile(script: script, voiceIdentifier: fallbackSystemVoice())
            }
            do {
                let url = try await sherpa.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
                sherpaStrikes = 0
                return url
            } catch {
                sherpaStrikes += 1
                Log.voice.error("Sherpa Kokoro failed (\(error.localizedDescription, privacy: .public)) — falling back to System voice")
                return try await system.renderToFile(script: script, voiceIdentifier: fallbackSystemVoice())
            }
        case .kokoro:
            // Circuit breaker: two init/synth misses and Kokoro sits out the
            // session — a 120 s timeout per break is silence in disguise.
            if kokoroStrikes >= 2 {
                return try await system.renderToFile(script: script, voiceIdentifier: fallbackSystemVoice())
            }
            do {
                let url = try await kokoro.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
                kokoroStrikes = 0
                return url
            } catch {
                kokoroStrikes += 1
                Log.voice.error("Kokoro provider failed (\(error.localizedDescription, privacy: .public)) — falling back to System voice")
                return try await system.renderToFile(script: script, voiceIdentifier: fallbackSystemVoice())
            }
        }
    }

    /// If the user had a non-system voice identifier selected, it's not a valid AVSpeech ID.
    /// Pass empty string so SystemDJVoice uses the OS default voice.
    private func fallbackSystemVoice() -> String { "" }
}
