import Foundation

enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case openAI = "openai"
    case kokoro = "kokoro"
    case sherpaKokoro = "sherpa_kokoro"
    case edgeTTS = "edge_tts"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: "Device Voices"
        case .openAI: "OpenAI"
        case .kokoro: "Kokoro (on-device)"
        case .sherpaKokoro: "Kokoro CPU (on-device)"
        case .edgeTTS: "Edge Neural (free cloud)"
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
    let edge: EdgeTTSDJVoice

    private let lock = NSLock()
    private var _provider: TTSProvider = .system
    private nonisolated(unsafe) var kokoroStrikes = 0
    private nonisolated(unsafe) var sherpaStrikes = 0
    private nonisolated(unsafe) var edgeStrikes = 0

    var provider: TTSProvider {
        get { lock.lock(); defer { lock.unlock() }; return _provider }
        set { lock.lock(); _provider = newValue; lock.unlock() }
    }

    init(system: SystemDJVoice = SystemDJVoice(),
         openAI: OpenAIDJVoice = OpenAIDJVoice(),
         kokoro: KokoroDJVoice = KokoroDJVoice(),
         sherpa: SherpaKokoroDJVoice = SherpaKokoroDJVoice(),
         edge: EdgeTTSDJVoice = EdgeTTSDJVoice()) {
        self.system = system
        self.openAI = openAI
        self.kokoro = kokoro
        self.sherpa = sherpa
        self.edge = edge
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

    /// Direct Edge render honoring the Settings-selected Edge voice (read live
    /// from UserDefaults by EdgeTTSDJVoice). Used by the voice preview.
    func renderEdgeSample(script: String) async throws -> URL {
        let url = try await edge.renderToFile(script: script, voiceIdentifier: "")
        edgeStrikes = 0
        return url
    }

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        let active = provider
        switch active {
        case .system:
            return try await renderEdgeThenLocal(script: script, voiceIdentifier: voiceIdentifier)
        case .edgeTTS:
            // Explicit selection: network tier with the full local floor behind it.
            return try await renderEdgeThenLocal(script: script, voiceIdentifier: voiceIdentifier)
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
            // Self-healing install: the first render after provider selection
            // (or after a Remove) pulls the assets itself — LAN mirror first,
            // public sources as fallback. One-time cost, then silent forever.
            if !SherpaModel.isModelInstalled {
                do { try await SherpaModel.install(progress: { _ in }) }
                catch { Log.voice.error("Sherpa auto-install failed (\(error.localizedDescription, privacy: .public))") }
            }
            do {
                let url = try await sherpa.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
                sherpaStrikes = 0
                return url
            } catch {
                sherpaStrikes += 1
                logEngine("SHERPA-FAIL(\(error.localizedDescription)) -> edge")
                Log.voice.error("Sherpa Kokoro failed (\(error.localizedDescription, privacy: .public)) — trying Edge Neural")
                if edgeStrikes < 2 {
                    do {
                        let url = try await edge.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
                        edgeStrikes = 0
                        return url
                    } catch {
                        edgeStrikes += 1
                        logEngine("EDGE-FAIL -> system")
                    }
                }
                logEngine("SYSTEM voice spoke")
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

    /// Edge Neural (free, keyless, ~1 s neural audio) ahead of the local tiers.
    /// On the 26/27 betas the AVSpeech server is dead (-66748), so a live
    /// network tier beats a dead native one; the two-strike breaker keeps
    /// offline sessions fast by skipping the network after repeated misses.
    private func renderEdgeThenLocal(script: String, voiceIdentifier: String) async throws -> URL {
        if edgeStrikes < 2 {
            do {
                let url = try await edge.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
                edgeStrikes = 0
                return url
            } catch {
                edgeStrikes += 1
                logEngine("EDGE-FAIL(\(error.localizedDescription)) -> local tier")
                Log.voice.error("Edge TTS failed (\(error.localizedDescription, privacy: .public)) — falling back to local tier")
            }
        }
        // Local floor: Sherpa wherever its assets survived; System when even
        // that is gone (alive again once Apple ships a fixed speech server).
        if SherpaModel.isModelInstalled {
            do {
                let url = try await sherpa.renderToFile(script: script, voiceIdentifier: voiceIdentifier)
                logEngine("SHERPA floor spoke")
                return url
            } catch {
                logEngine("SHERPA floor failed -> system")
                Log.voice.error("Sherpa floor failed too — using system voice")
            }
        }
        logEngine("SYSTEM voice spoke")
        return try await system.renderToFile(script: script, voiceIdentifier: fallbackSystemVoice())
    }

    /// If the user had a non-system voice identifier selected, it's not a valid AVSpeech ID.
    /// Pass empty string so SystemDJVoice uses the OS default voice.
    private func fallbackSystemVoice() -> String { "" }
}
