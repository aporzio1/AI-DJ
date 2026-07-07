import Foundation
import FluidAudio

/// American-English Kokoro voices exposed in Settings.
/// (FluidAudio supports more but only af_*/am_* are documented as production-ready.)
enum KokoroVoice: String, CaseIterable, Identifiable {
    case af_heart, af_bella, af_nicole, af_sarah, af_sky,
         af_alloy, af_aoede, af_jessica, af_kore, af_nova, af_river,
         am_adam, am_echo, am_eric, am_fenrir, am_liam,
         am_michael, am_onyx, am_puck, am_santa

    var id: String { rawValue }

    /// Voices actually offered in pickers. The KokoroAne backend
    /// (FluidAudio 0.14.2+) ships only the `af_heart` voice pack on
    /// HuggingFace (`FluidInference/kokoro-82m-coreml/ANE`) — the other
    /// enum cases are retained so persisted selections keep decoding, but
    /// they clamp to `af_heart` at render time.
    static var available: [KokoroVoice] { [.af_heart] }

    /// Human-readable name shown in the Picker.
    var displayName: String {
        let parts = rawValue.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return rawValue.capitalized }
        let gender: String = parts[0].hasSuffix("f") ? "♀" : "♂"
        return "\(parts[1].capitalized) \(gender)"
    }

    static let defaultVoice: KokoroVoice = .af_heart
}

enum KokoroDJVoiceError: Error, LocalizedError {
    case initializationFailed(underlying: Error)
    case synthesisFailed(underlying: Error)
    case initializationTimeout(seconds: TimeInterval)
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let e):
            "Kokoro failed to initialize: \(e.localizedDescription). The model may still be downloading."
        case .synthesisFailed(let e):
            "Kokoro synthesis failed: \(e.localizedDescription)"
        case .initializationTimeout(let s):
            "Kokoro initialization timed out after \(Int(s)) seconds. CoreML compile may be stuck — try a different voice provider in Settings."
        }
    }
}

/// Serializes access to the `KokoroAneManager` and coalesces the one-time
/// model download behind the first render call.
private actor KokoroSynthesizer {
    private var manager: KokoroAneManager?

    func ensureInitialized() async throws {
        if manager != nil { return }
        // Distinguish "downloading from HuggingFace" (~30 s) from "cached
        // but needs CoreML compile + warm-up" by checking whether the model
        // directory is already populated. Different user messaging for each.
        // Defer end() so errors and cancellations still reset the indicator.
        let mode: KokoroDownloadState.Mode = KokoroDJVoice.isModelInstalled
            ? .loading
            : .downloading
        await KokoroDownloadState.shared.begin(mode)
        defer { Task { @MainActor in KokoroDownloadState.shared.end() } }
        // Guard initialize() with a timeout — the pre-0.14 mono-Kokoro
        // CoreML compile hung on iOS 26 (tracker K6), leaving the
        // "Loading DJ voice…" indicator stuck in the MiniPlayerBar forever.
        // The 7-stage KokoroAne chain hasn't shown that failure mode, but
        // the guard stays: throwing lets the defer end the indicator and
        // forces a retry path on the next render attempt. 120 s is a very
        // generous upper bound for a legitimate compile of all 7 models.
        do {
            let pending = KokoroAneManager()
            try await withTimeout(seconds: 120) {
                try await pending.initialize()
            }
            manager = pending
        } catch {
            throw KokoroDJVoiceError.initializationFailed(underlying: error)
        }
    }

    /// Runs `operation` but races it against a sleep of `seconds`; whichever
    /// finishes first wins. Throws `KokoroDJVoiceError.initializationTimeout`
    /// if the timeout hits. Cancels the loser in both directions.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw KokoroDJVoiceError.initializationTimeout(seconds: seconds)
            }
            defer { group.cancelAll() }
            let result = try await group.next()!
            return result
        }
    }

    /// Drop the in-memory manager so a subsequent call re-downloads / re-loads.
    func reset() async {
        await manager?.cleanup()
        manager = nil
    }

    func render(text: String, voice: String?, outputURL: URL) async throws {
        try await ensureInitialized()
        do {
            let wav = try await manager!.synthesize(text: text, voice: voice)
            try wav.write(to: outputURL)
        } catch {
            throw KokoroDJVoiceError.synthesisFailed(underlying: error)
        }
    }
}

/// On-device TTS using FluidAudio's KokoroAne model (7-stage CoreML chain).
/// The models, G2P assets, and voice pack download on first use and cache under
/// ~/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE (macOS) or
/// Application Support/fluidaudio/Models/kokoro-82m-coreml/ANE (iOS).
/// Initialization is deferred until the first renderToFile call so app launch
/// isn't blocked by a cold download.
final class KokoroDJVoice: DJVoiceProtocol, KokoroModelManaging, Sendable {

    private let synth = KokoroSynthesizer()

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        // Clamp to the published voice pack — see `KokoroVoice.available`.
        let voice: String?
        if voiceIdentifier.isEmpty {
            voice = nil
        } else if KokoroVoice.available.map(\.rawValue).contains(voiceIdentifier) {
            voice = voiceIdentifier
        } else {
            Log.voice.warning("Kokoro voice \(voiceIdentifier, privacy: .public) has no published KokoroAne voice pack — clamping to \(KokoroVoice.defaultVoice.rawValue, privacy: .public)")
            voice = KokoroVoice.defaultVoice.rawValue
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        // Kokoro's G2P/lexicon only recognizes the ASCII apostrophe — typographic
        // quotes from LLM output (e.g. "that’s") are read as an unknown character
        // and mispronounced (audibly "that ex s"). Normalize before synthesis.
        let normalizedScript = script
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")

        Log.voice.info("Kokoro TTS request (voice=\(voice ?? "default", privacy: .public), chars=\(normalizedScript.count))")
        let started = ContinuousClock.now
        try await synth.render(text: normalizedScript, voice: voice, outputURL: outputURL)
        let elapsed = ContinuousClock.now - started
        Log.voice.info("Kokoro TTS rendered in \(String(describing: elapsed), privacy: .public) → \(outputURL.lastPathComponent, privacy: .public)")
        return outputURL
    }

    // MARK: - Model management

    /// Forces a download + load without synthesizing, so the user can pre-stage
    /// the ~300 MB assets from Settings instead of paying the cost on first segment.
    func prepareModel() async throws {
        try await synth.ensureInitialized()
    }

    /// Drops the cached model files and the in-memory manager. Next render will
    /// re-download.
    func removeModel() async throws {
        await synth.reset()
        DownloadUtils.clearAllModelCaches()
        Log.voice.info("Kokoro model cache cleared")
    }

    /// Whether the KokoroAne model directory exists and is non-empty on disk.
    static var isModelInstalled: Bool {
        let dir = modelCacheDirectory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !contents.isEmpty
    }

    /// Mirrors FluidAudio's own TTS cache-location rules (`TtsCacheDirectory`
    /// + `ModelNames`): `<cache root>/Models/kokoro-82m-coreml/ANE`, where the
    /// cache root is `~/.cache/fluidaudio` on macOS and
    /// `Application Support/fluidaudio` on iOS.
    private static var modelCacheDirectory: URL {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/fluidaudio/Models/kokoro-82m-coreml/ANE")
        #else
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("fluidaudio/Models/kokoro-82m-coreml/ANE")
        #endif
    }
}
