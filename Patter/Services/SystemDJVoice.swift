import Foundation
import AVFoundation

/// Renders DJ scripts using the OS-provided AVSpeechSynthesizer.
final class SystemDJVoice: DJVoiceProtocol, @unchecked Sendable {

    /// One synthesizer reused across every render. Per K35:
    /// (1) Constructing a fresh `AVSpeechSynthesizer` triggers an Audio Unit IPC
    /// handshake on first use — reusing a warm synth skips that on subsequent calls.
    /// (2) Setting `usesApplicationAudioSession = false` detaches the synth's
    /// internal AU pipeline from the shared `AVAudioSession`. The first warm-synth
    /// fix (commit `9779040`) skipped the handshake but the per-render AU
    /// activations (`mBuffers[0].mDataByteSize (0)` warnings) still kicked the
    /// shared session, freezing `ApplicationMusicPlayer`'s playback for ~10s at
    /// every track-end transition. With a private session, those AU activations
    /// happen in a sandbox that doesn't pre-empt MusicKit. We use
    /// `write(_:toBufferCallback:)` to render PCM in-memory — no audible playback
    /// is lost from session detachment, and `SpeechRenderer.handleBuffer` already
    /// reads the buffer's actual format dynamically so any sample-rate/channel
    /// shift the private session might pick is handled.
    /// Producer awaits each `renderToFile` before starting the next, so concurrent
    /// access to this synth doesn't happen in normal operation.
    private let synthesizer: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
#if os(iOS)
        // iOS-only: detach synth's internal audio session from the shared one
        // so per-render AU activations don't pre-empt MusicKit (K35).
        synth.usesApplicationAudioSession = false
#endif
        return synth
    }()

    /// Serializes access to the shared `synthesizer`. Without this, the
    /// launch-time `warmUp` and a real Producer render could overlap:
    /// AVSpeechSynthesizer only drives one utterance stream at a time, so
    /// interleaved `write` callbacks would corrupt both output files, and
    /// the warm-up's timeout `stop()` would kill a real render if they raced.
    private let chainLock = NSLock()
    private var tail: Task<Void, Never> = Task {}

    private func serialized<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        // Read the previous tail and install the new one inside a single
        // locked section. `Task { ... }` init is synchronous (it schedules
        // the closure but doesn't run/await it here), so no suspension point
        // exists between the read and the write — two concurrent callers
        // can't both observe the same `previous` the way they could with
        // separate get/set locks.
        let current: Task<T, Error> = {
            chainLock.lock(); defer { chainLock.unlock() }
            let previous = tail
            let current = Task<T, Error> {
                await previous.value
                return try await operation()
            }
            tail = Task<Void, Never> { _ = try? await current.value }
            return current
        }()
        return try await current.value
    }

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        // K35 diagnostics: total wall time including any queue wait behind
        // a concurrent warm-up/render on the shared synth — this is the
        // number that matches what the listener actually perceives.
        let callStart = ContinuousClock.now
        do {
            let url = try await serialized { [self] in
                try await performRender(script: script, voiceIdentifier: voiceIdentifier, label: "render")
            }
            Log.voice.info("SystemDJVoice.renderToFile total \(String(describing: ContinuousClock.now - callStart), privacy: .public) (incl. any queue wait)")
            return url
        } catch {
            Log.voice.error("SystemDJVoice.renderToFile failed after \(String(describing: ContinuousClock.now - callStart), privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Renders a minimal throwaway utterance so the first real render
    /// doesn't pay the AU IPC handshake + neural-voice-model load (K35).
    /// Best-effort: discards errors and deletes the temp file it produces.
    func warmUp(voiceIdentifier: String) async {
        let callStart = ContinuousClock.now
        Log.voice.info("SystemDJVoice.warmUp starting")
        do {
            let url = try await serialized { [self] in
                try await performRender(script: "Ready.", voiceIdentifier: voiceIdentifier, label: "warmup")
            }
            Log.voice.info("SystemDJVoice.warmUp total \(String(describing: ContinuousClock.now - callStart), privacy: .public) (incl. any queue wait)")
            try? FileManager.default.removeItem(at: url)
        } catch {
            Log.voice.error("SystemDJVoice.warmUp failed after \(String(describing: ContinuousClock.now - callStart), privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `label` distinguishes the launch warm-up from a real Producer render
    /// in the logs — both funnel through the same synth + serialization.
    private func performRender(script: String, voiceIdentifier: String, label: String) async throws -> URL {
        let renderStart = ContinuousClock.now
        Log.voice.info("SystemDJVoice[\(label, privacy: .public)] synth write starting")
        let voice = Self.voice(for: voiceIdentifier)
        let utterances = Self.makeUtterances(for: script, voice: voice)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        let renderer = SpeechRenderer(synthesizer: synthesizer, utterances: utterances, outputURL: outputURL)

        do {
            let url: URL = try await withCheckedThrowingContinuation { continuation in
                let timeout = Task {
                    try? await Task.sleep(for: .seconds(Self.timeoutSeconds(for: script)))
                    renderer.stop()
                }
                renderer.render { [renderer] result in
                    _ = renderer
                    timeout.cancel()
                    continuation.resume(with: result)
                }
            }
            Log.voice.info("SystemDJVoice[\(label, privacy: .public)] synth write finished in \(String(describing: ContinuousClock.now - renderStart), privacy: .public) — this is the AU handshake + speech-synthesis cost K35 targets")
            return url
        } catch {
            Log.voice.error("SystemDJVoice[\(label, privacy: .public)] synth write failed after \(String(describing: ContinuousClock.now - renderStart), privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static func makeUtterances(for script: String, voice: AVSpeechSynthesisVoice?) -> [AVSpeechUtterance] {
        let chunks = speechChunks(from: script)
        return chunks.map { chunk in
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = voice
            utterance.rate = 0.50
            utterance.pitchMultiplier = 0.98
            utterance.volume = 1.0
            utterance.preUtteranceDelay = 0.02
            utterance.postUtteranceDelay = 0.12
            return utterance
        }
    }

    private static func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return preferredEnglishVoice()
    }

    private static func preferredEnglishVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .max { lhs, rhs in
                voiceScore(lhs) < voiceScore(rhs)
            }
    }

    private static func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        let qualityScore: Int
        switch voice.quality {
        case .premium: qualityScore = 3_000
        case .enhanced: qualityScore = 2_000
        default: qualityScore = 1_000
        }

        let localeScore = voice.language == "en-US" ? 200 : 0
        let preferredNames = ["Ava", "Zoe", "Evan", "Allison", "Samantha", "Alex"]
        let nameScore = preferredNames.firstIndex(of: voice.name).map { 100 - $0 } ?? 0
        return qualityScore + localeScore + nameScore
    }

    private static func speechChunks(from script: String) -> [String] {
        let cleaned = script
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "—", with: ", ")
            .replacingOccurrences(of: "–", with: ", ")
            .replacingOccurrences(of: " & ", with: " and ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return [""] }

        var chunks: [String] = []
        cleaned.enumerateSubstrings(in: cleaned.startIndex..<cleaned.endIndex, options: [.bySentences]) { sentence, _, _, _ in
            guard let sentence else { return }
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
        }
        return chunks.isEmpty ? [cleaned] : chunks
    }

    private static func timeoutSeconds(for script: String) -> Int {
        max(20, min(60, script.count / 12))
    }
}

// MARK: - SpeechRenderer

/// Drives AVSpeechSynthesizer.write and accumulates PCM buffers into a .caf file.
/// Thread-safe: the synth callback can fire on any queue.
/// Borrows the synthesizer from the parent `SystemDJVoice` so its AU IPC graph
/// stays warm across renders (K35).
private final class SpeechRenderer: @unchecked Sendable {
    private let synthesizer: AVSpeechSynthesizer
    private let utterances: [AVSpeechUtterance]
    private let outputURL: URL
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var finished = false
    private var currentIndex = 0
    private var currentUtteranceWroteAudio = false

    init(synthesizer: AVSpeechSynthesizer, utterances: [AVSpeechUtterance], outputURL: URL) {
        self.synthesizer = synthesizer
        self.utterances = utterances
        self.outputURL = outputURL
    }

    func render(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        lock.lock()
        self.completion = completion
        lock.unlock()
        renderCurrentUtterance()
    }

    /// Force-stop the synthesizer and resume the caller with a timeout error.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish(with: .failure(DJVoiceError.renderTimeout))
    }

    private func handleBuffer(_ buffer: AVAudioBuffer) {
        if isFinished() { return }
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

        if pcmBuffer.frameLength == 0 {
            // Terminator. Only complete if we actually wrote audio — AVSpeechSynthesizer
            // can emit a spurious empty buffer before any real audio.
            if currentUtteranceWroteAudio {
                startNextUtteranceOrFinish()
            }
            return
        }

        do {
            if currentAudioFile() == nil {
                let file = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
                setAudioFile(file)
            }
            try currentAudioFile()?.write(from: pcmBuffer)
            currentUtteranceWroteAudio = true
        } catch {
            finish(with: .failure(error))
        }
    }

    private func renderCurrentUtterance() {
        if isFinished() { return }
        guard currentIndex < utterances.count else {
            finish(with: currentAudioFile() == nil ? .failure(DJVoiceError.noAudioRendered) : .success(outputURL))
            return
        }
        currentUtteranceWroteAudio = false
        synthesizer.write(utterances[currentIndex]) { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
    }

    private func startNextUtteranceOrFinish() {
        currentIndex += 1
        if currentIndex < utterances.count {
            renderCurrentUtterance()
        } else {
            finish(with: currentAudioFile() == nil ? .failure(DJVoiceError.noAudioRendered) : .success(outputURL))
        }
    }

    private func currentAudioFile() -> AVAudioFile? {
        lock.lock(); defer { lock.unlock() }
        return audioFile
    }

    private func setAudioFile(_ file: AVAudioFile) {
        lock.lock(); defer { lock.unlock() }
        audioFile = file
    }

    private func isFinished() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    private func finish(with result: Result<URL, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let cb = completion
        completion = nil
        // Drop the write handle BEFORE resuming the caller so AVAudioFile.deinit
        // flushes to disk. Otherwise the reader (AudioGraph) can open the file
        // while writes are still buffered and hear silence.
        audioFile = nil
        lock.unlock()
        cb?(result)
    }
}

enum DJVoiceError: Error {
    case renderTimeout
    case noAudioRendered
}
