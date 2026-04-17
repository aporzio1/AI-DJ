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

        return try await withCheckedThrowingContinuation { continuation in
            let renderer = SpeechRenderer(utterance: utterance, outputURL: outputURL)
            renderer.render { result in
                continuation.resume(with: result)
            }
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
            finished = true
            completion?(.success(outputURL))
            completion = nil
            return
        }

        do {
            if audioFile == nil {
                guard let format = pcmBuffer.format.settings as [String: Any]? else {
                    finished = true
                    completion?(.failure(DJVoiceError.invalidFormat))
                    completion = nil
                    return
                }
                audioFile = try AVAudioFile(forWriting: outputURL, settings: format)
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
}
