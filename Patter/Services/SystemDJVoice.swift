import Foundation
import AVFoundation

/// Renders DJ scripts using the OS-provided AVSpeechSynthesizer.
final class SystemDJVoice: DJVoiceProtocol {

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        let utterance = AVSpeechUtterance(string: script)
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        let renderer = SpeechRenderer(utterance: utterance, outputURL: outputURL)

        return try await withCheckedThrowingContinuation { continuation in
            let timeout = Task {
                try? await Task.sleep(for: .seconds(15))
                renderer.stop()
            }
            renderer.render { [renderer] result in
                _ = renderer
                timeout.cancel()
                continuation.resume(with: result)
            }
        }
    }
}

// MARK: - SpeechRenderer

/// Drives AVSpeechSynthesizer.write and accumulates PCM buffers into a .caf file.
/// Thread-safe: the synth callback can fire on any queue.
private final class SpeechRenderer: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let utterance: AVSpeechUtterance
    private let outputURL: URL
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var finished = false

    init(utterance: AVSpeechUtterance, outputURL: URL) {
        self.utterance = utterance
        self.outputURL = outputURL
    }

    func render(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        lock.lock()
        self.completion = completion
        lock.unlock()
        synthesizer.write(utterance) { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
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
            if currentAudioFile() != nil {
                finish(with: .success(outputURL))
            }
            return
        }

        do {
            if currentAudioFile() == nil {
                let file = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
                setAudioFile(file)
            }
            try currentAudioFile()?.write(from: pcmBuffer)
        } catch {
            finish(with: .failure(error))
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
}
