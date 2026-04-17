import Foundation
import AVFoundation

final class DJVoice: DJVoiceProtocol {

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

        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    renderer.render { [renderer] result in
                        _ = renderer // keep alive until callback fires
                        continuation.resume(with: result)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw DJVoiceError.renderTimeout
            }
            let url = try await group.next()!
            group.cancelAll()
            return url
        }
    }
}

// MARK: - SpeechRenderer

/// Wraps AVSpeechSynthesizer write callback, retaining the synthesizer for the duration of rendering.
private final class SpeechRenderer: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let utterance: AVSpeechUtterance
    private let outputURL: URL
    private var audioFile: AVAudioFile?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var finished = false

    init(utterance: AVSpeechUtterance, outputURL: URL) {
        self.utterance = utterance
        self.outputURL = outputURL
    }

    func render(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.completion = completion
        synthesizer.write(utterance) { [weak self] buffer in
            self?.handleBuffer(buffer)
        }
    }

    private func handleBuffer(_ buffer: AVAudioBuffer) {
        guard !finished else { return }
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

        if pcmBuffer.frameLength == 0 {
            // Terminator. Only treat as success if we actually wrote audio.
            // AVSpeechSynthesizer sometimes emits a spurious empty buffer before any real audio.
            if audioFile != nil {
                finished = true
                completion?(.success(outputURL))
                completion = nil
            }
            // Else: ignore — wait for actual audio buffers
            return
        }

        do {
            if audioFile == nil {
                audioFile = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
            }
            try audioFile?.write(from: pcmBuffer)
        } catch {
            finished = true
            completion?(.failure(error))
            completion = nil
        }
    }
}

enum DJVoiceError: Error {
    case invalidFormat
    case noAudioGenerated
    case renderTimeout
}
