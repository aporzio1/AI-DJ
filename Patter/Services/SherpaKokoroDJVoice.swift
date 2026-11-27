import Foundation
import AVFoundation
import SherpaOnnx

// MARK: - Assets

/// On-device Kokoro via sherpa-onnx: pure ONNX Runtime CPU inference inside
/// our own process. Deliberately independent of everything Apple-side that
/// went hostile on recent iOS betas — CoreML (Kokoro asserts in MPSGraph on
/// 27, segfaults in BNNS on 26) and the speech-synthesis AU server
/// (AVSpeechSynthesizer renderTimeout, IPCAUClient -66748). The tradeoff is
/// honest: no published iPhone latency exists for this stack, so the
/// provider ships opt-in behind a measured gate (p95 < 3 s for a 60-word
/// line on A19, int8) before it may become any default.
///
/// Assets (Apache-licensed Kokoro weights; lexicon-based English
/// phonemization — no GPL espeak-ng data anywhere in the bundle):
///   model.onnx  ~134 MB int8   RuiSumida/sherpa-onnx-kokoro-int8-en-v0_19 (HF)
///   voices.bin    ~6 MB        same repo
///   tokens.txt    ~4 KB        mirrored in-repo at assets/sherpa-kokoro/ (SPM-approved domain)
///   lexicon       ~6 MB        k2-fsa release asset tts-models/lexicon-en-us.txt
enum SherpaModel {

    static let dirName = "kokoro-onnx"

    /// CPU inference runs everywhere the app runs — no OS-version sealing.
    static var isUsableOnThisOS: Bool { true }

    static let fileBaseURL: URL = {
        #if os(macOS)
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/fluidaudio/Models", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fluidaudio/Models", isDirectory: true)
        #endif
        return base.appendingPathComponent(dirName, isDirectory: true)
    }()

    /// Remote sources. Files land verbatim under fileBaseURL.
    static let files: [RemoteAsset] = [
        RemoteAsset(name: "model.onnx",
                    url: URL(string: "https://huggingface.co/RuiSumida/sherpa-onnx-kokoro-int8-en-v0_19/resolve/main/model.onnx")!),
        RemoteAsset(name: "voices.bin",
                    url: URL(string: "https://huggingface.co/RuiSumida/sherpa-onnx-kokoro-int8-en-v0_19/resolve/main/voices.bin")!),
        RemoteAsset(name: "tokens.txt",
                    url: URL(string: "https://raw.githubusercontent.com/aporzio1/AI-DJ/main/Patter/Assets/sherpa-kokoro/tokens.txt")!),
        RemoteAsset(name: "lexicon-en-us.txt",
                    url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/lexicon-en-us.txt")!),
    ]

    struct RemoteAsset { let name: String; let url: URL }

    static var isModelInstalled: Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: fileBaseURL.appendingPathComponent($0.name).path) }
    }

    /// Download all four files with per-file progress, atomic promote
    /// (.part → final), resume-by-existence (finished files are skipped).
    static func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileBaseURL, withIntermediateDirectories: true)
        for (index, asset) in files.enumerated() {
            let target = fileBaseURL.appendingPathComponent(asset.name)
            if fm.fileExists(atPath: target.path) { continue }
            let part = target.appendingPathExtension("part")
            if !fm.fileExists(atPath: part.path) {
                let (temp, response) = try await URLSession.shared.download(from: asset.url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw SherpaTTSError.downloadFailed(asset.name, http.statusCode)
                }
                try? fm.removeItem(at: part)
                try fm.moveItem(at: temp, to: part)
            }
            // Fresh install: target does not exist yet — removeItem(at:) on a
            // missing path THROWS ("couldn't be removed"), which killed the
            // whole install after a successful 134 MB download.
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: part, to: target)
            progress(Double(index + 1) / Double(files.count))
        }
    }

    static func removeModel() throws {
        try FileManager.default.removeItem(at: fileBaseURL)
    }
}

enum SherpaTTSError: Error, LocalizedError {
    case downloadFailed(String, Int)
    case initializationFailed(String)
    case renderTimeout
    case noAudio

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let name, let code): "Kokoro CPU download failed for \(name) (HTTP \(code))."
        case .initializationFailed(let why):      "Kokoro CPU engine failed to load: \(why)"
        case .renderTimeout:                      "Kokoro CPU render timed out."
        case .noAudio:                            "Kokoro CPU produced no audio."
        }
    }
}

// MARK: - Provider

/// DJVoiceProtocol provider owning one sherpa-onnx engine on a dedicated
/// serial queue (the native engine is single-threaded-access; inference
/// never runs on a cooperative executor or MainActor).
final class SherpaKokoroDJVoice: DJVoiceProtocol, @unchecked Sendable {

    private let queue = DispatchQueue(label: "patter.sherpa.kokoro", qos: .userInitiated)
    private var engine: SherpaOnnxOfflineTtsWrapper?

    /// Speaker id for the Settings voice picker. Kokoro ships its voices as
    /// integer sids; Bella=0 stays first to match KokoroVoice ordering.
    var speakerID: Int

    init(speakerID: Int = 0) { self.speakerID = speakerID }

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        let text = script
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        let sid = speakerID

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            queue.async { [weak self] in
                guard let self else { continuation.resume(throwing: SherpaTTSError.noAudio); return }
                do {
                    let tts = try self.engineLoaded()
                    let box = SampleBox()
                    let unmanaged = Unmanaged.passUnretained(box)
                    let callback: TtsProgressCallbackWithArg = { samples, count, _, arg in
                        guard let samples, let arg, count > 0 else { return 1 }
                        let box = Unmanaged<SampleBox>.fromOpaque(arg).takeUnretainedValue()
                        for i in 0..<count { box.samples.append(samples[Int(i)]) }
                        return 1
                    }
                    let arg = unmanaged.toOpaque()
                    _ = callback
                    var genConfig = SherpaOnnxGenerationConfigSwift()
                    genConfig.sid = sid
                    genConfig.speed = 1.0
                    _ = tts.generateWithConfig(text: text, config: genConfig,
                                               callback: Self.callbackThunk, arg: arg)
                    let samples = box.samples
                    guard !samples.isEmpty else { throw SherpaTTSError.noAudio }
                    try Self.writeCAF(samples: samples, sampleRate: 24_000, to: outputURL)
                    continuation.resume(returning: outputURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // The C callback must be a plain function reference for the wrapper's
    // signature; the boxed instance is passed through `arg`.
    private static let callbackThunk: TtsProgressCallbackWithArg = { samples, count, _, arg in
        guard let samples, let arg, count > 0 else { return 1 }
        let box = Unmanaged<SampleBox>.fromOpaque(arg).takeUnretainedValue()
        for i in 0..<count { box.samples.append(samples[Int(i)]) }
        return 1
    }

    private final class SampleBox { var samples = [Float]() }

    private func engineLoaded() throws -> SherpaOnnxOfflineTtsWrapper {
        if let engine { return engine }
        let dir = SherpaModel.fileBaseURL
        guard SherpaModel.isModelInstalled else {
            throw SherpaTTSError.initializationFailed("model not downloaded")
        }
        var kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: dir.appendingPathComponent("model.onnx").path,
            voices: dir.appendingPathComponent("voices.bin").path,
            tokens: dir.appendingPathComponent("tokens.txt").path,
            lexicon: dir.appendingPathComponent("lexicon-en-us.txt").path
        )
        var modelConfig = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, debug: 0)
        _ = kokoro
        var ttsConfig = sherpaOnnxOfflineTtsConfig(model: modelConfig)
        _ = modelConfig
        let wrapper = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        engine = wrapper
        return wrapper
    }

    private static func writeCAF(samples: [Float], sampleRate: Int, to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            throw SherpaTTSError.noAudio
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for i in 0..<samples.count { buffer.floatChannelData![0][i] = samples[i] }
        try file.write(from: buffer)
    }
}
