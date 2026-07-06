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

    /// Providers offered in the picker.
    ///
    /// SPIKE (kokoro-ane-0.15.4): the iOS 26+ Kokoro exclusion (K6/K24/K26)
    /// is lifted on this branch. FluidAudio 0.14.2+ replaced the mono
    /// Kokoro CoreML model that crashed iOS 26/27 with the 7-stage
    /// KokoroAne chain; this spike exists to verify that on a physical
    /// iPhone (tracker Backlog #12 gates: OOV proper-noun inputs per
    /// upstream #587, backgrounded render per #738). Do not merge without
    /// both gates passing — restore the filter if either fails.
    static var available: [TTSProvider] {
        TTSProvider.allCases
    }
}

/// Model-management surface for an on-device TTS provider whose model is a
/// separate downloadable asset (Kokoro today). Kept apart from
/// `DJVoiceProtocol` because rendering and model lifecycle are independent
/// concerns — a provider with no downloadable model (System, OpenAI) has
/// nothing to conform to here.
protocol KokoroModelManaging {
    func prepareModel() async throws
    func removeModel() async throws
}

/// Routes DJ-voice rendering requests to the active provider, with a fallback
/// to SystemDJVoice so a misconfigured cloud/on-device provider never stalls playback.
final class DJVoiceRouter: DJVoiceProtocol, @unchecked Sendable {

    private let system: any DJVoiceProtocol
    private let openAI: any DJVoiceProtocol
    private let kokoro: any DJVoiceProtocol & KokoroModelManaging

    private let lock = NSLock()
    private var _provider: TTSProvider = .system

    var provider: TTSProvider {
        get { lock.lock(); defer { lock.unlock() }; return _provider }
        set { lock.lock(); _provider = newValue; lock.unlock() }
    }

    init(system: any DJVoiceProtocol = SystemDJVoice(),
         openAI: any DJVoiceProtocol = OpenAIDJVoice(),
         kokoro: any DJVoiceProtocol & KokoroModelManaging = KokoroDJVoice()) {
        self.system = system
        self.openAI = openAI
        self.kokoro = kokoro
    }

    func setOpenAIModel(_ model: OpenAITTSModel) {
        // Model selection is provider-specific, not part of the render
        // protocol — downcast rather than growing DJVoiceProtocol for one
        // provider's concern. No-op for fakes/other providers in tests.
        (openAI as? OpenAIDJVoice)?.updateModel(model)
    }

    /// Warms the System-voice provider ahead of the first real render (K35).
    /// Proxied rather than folded into the protocol's `warmUp` because it's
    /// meant to be called once at launch regardless of the active provider,
    /// not routed through the provider-switch logic in `renderToFile`.
    func warmUpSystemVoice(voiceIdentifier: String) async {
        await system.warmUp(voiceIdentifier: voiceIdentifier)
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
