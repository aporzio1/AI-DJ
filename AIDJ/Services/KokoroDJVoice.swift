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
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let e):
            "Kokoro failed to initialize: \(e.localizedDescription). The model may still be downloading."
        case .synthesisFailed(let e):
            "Kokoro synthesis failed: \(e.localizedDescription)"
        }
    }
}

/// Serializes access to the non-Sendable `KokoroTtsManager` and coalesces the
/// one-time model download behind the first render call.
private actor KokoroSynthesizer {
    private var manager: KokoroTtsManager?

    func render(text: String, voice: String?, outputURL: URL) async throws {
        if manager == nil {
            do {
                let m = KokoroTtsManager()
                try await m.initialize()
                manager = m
            } catch {
                throw KokoroDJVoiceError.initializationFailed(underlying: error)
            }
        }
        do {
            try await manager!.synthesizeToFile(
                text: text,
                outputURL: outputURL,
                voice: voice
            )
        } catch {
            throw KokoroDJVoiceError.synthesisFailed(underlying: error)
        }
    }
}

/// On-device TTS using FluidAudio's CoreML Kokoro model.
/// The model and G2P assets download on first use and cache under
/// ~/.cache/fluidaudio/Models/kokoro. Initialization is deferred until the
/// first renderToFile call so app launch isn't blocked by a cold download.
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
}
