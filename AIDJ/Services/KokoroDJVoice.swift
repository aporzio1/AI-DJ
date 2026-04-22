import Foundation
@preconcurrency import FluidAudio

/// American-English Kokoro voices exposed in Settings.
/// (FluidAudio supports more but only af_*/am_* are documented as production-ready.)
enum KokoroVoice: String, CaseIterable, Identifiable {
    case af_heart, af_bella, af_nicole, af_sarah, af_sky,
         af_alloy, af_aoede, af_jessica, af_kore, af_nova, af_river,
         am_adam, am_echo, am_eric, am_fenrir, am_liam,
         am_michael, am_onyx, am_puck, am_santa

    var id: String { rawValue }

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

/// Wraps a `KokoroTtsManager` in a Sendable holder so the actor can send
/// references across its own await points without tripping Swift 6's
/// strict "sending non-Sendable value" check. Safe because all access is
/// serialized by `KokoroSynthesizer`.
private final class ManagerBox: @unchecked Sendable {
    let manager: KokoroTtsManager
    init(_ manager: KokoroTtsManager) { self.manager = manager }

    func synthesize(text: String, voice: String?, outputURL: URL) async throws {
        try await manager.synthesizeToFile(
            text: text,
            outputURL: outputURL,
            voice: voice
        )
    }
}

/// Serializes access to the non-Sendable `KokoroTtsManager` and coalesces the
/// one-time model download behind the first render call.
private actor KokoroSynthesizer {
    private var box: ManagerBox?

    func ensureInitialized() async throws {
        if box != nil { return }
        // Distinguish "downloading from HuggingFace" (~30 s) from "cached
        // but needs CoreML compile + warm-up" (~2-3 s on macOS, 15-30 s on
        // iOS 26) by checking whether the model directory is already
        // populated. Different user messaging for each. Defer end() so
        // errors and cancellations still reset the indicator.
        let mode: KokoroDownloadState.Mode = KokoroDJVoice.isModelInstalled
            ? .loading
            : .downloading
        await KokoroDownloadState.shared.begin(mode)
        defer { Task { @MainActor in KokoroDownloadState.shared.end() } }
        // Guard initialize() with a timeout — iOS 26's CoreML Metal compile
        // has occasionally hung on the second (15 s) model, leaving the
        // "Loading DJ voice…" indicator stuck in the MiniPlayerBar forever.
        // Throwing here lets the defer end the indicator and forces a
        // retry path on the next render attempt. 120 s is a very generous
        // upper bound for a legitimate compile.
        do {
            let m = KokoroTtsManager()
            try await withTimeout(seconds: 120) {
                try await m.initialize()
            }
            box = ManagerBox(m)
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
    func reset() {
        box = nil
    }

    func render(text: String, voice: String?, outputURL: URL) async throws {
        try await ensureInitialized()
        do {
            try await box!.synthesize(text: text, voice: voice, outputURL: outputURL)
        } catch {
            throw KokoroDJVoiceError.synthesisFailed(underlying: error)
        }
    }
}

/// On-device TTS using FluidAudio's CoreML Kokoro model.
/// The model and G2P assets download on first use and cache under
/// ~/.cache/fluidaudio/Models/kokoro (macOS) or Caches/fluidaudio/Models/kokoro (iOS).
/// Initialization is deferred until the first renderToFile call so app launch
/// isn't blocked by a cold download.
final class KokoroDJVoice: DJVoiceProtocol, Sendable {

    private let synth = KokoroSynthesizer()

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        let voice = voiceIdentifier.isEmpty ? nil : voiceIdentifier
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        Log.voice.info("Kokoro TTS request (voice=\(voice ?? "default", privacy: .public), chars=\(script.count))")
        let started = ContinuousClock.now
        try await synth.render(text: script, voice: voice, outputURL: outputURL)
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

    /// Whether the Kokoro model directory exists and is non-empty on disk.
    static var isModelInstalled: Bool {
        let dir = modelCacheDirectory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !contents.isEmpty
    }

    /// Mirrors FluidAudio's own TTS cache-location rules. See
    /// `DownloadUtils.clearAllModelCaches` in the FluidAudio source.
    private static var modelCacheDirectory: URL {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/fluidaudio/Models/kokoro")
        #else
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("fluidaudio/Models/kokoro")
        #endif
    }
}
