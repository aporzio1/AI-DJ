import Foundation
import AVFoundation

/// Renders DJ scripts using the OS-provided AVSpeechSynthesizer.
final class SystemDJVoice: DJVoiceProtocol {

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        let voice = Self.voice(for: voiceIdentifier)
        let utterances = Self.makeUtterances(for: script, voice: voice)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        let renderer = SpeechRenderer(utterances: utterances, outputURL: outputURL)

        return try await withCheckedThrowingContinuation { continuation in
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
private final class SpeechRenderer: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let utterances: [AVSpeechUtterance]
    private let outputURL: URL
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var finished = false
    private var currentIndex = 0
    private var currentUtteranceWroteAudio = false

    init(utterances: [AVSpeechUtterance], outputURL: URL) {
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
