import Foundation
import AVFoundation

@MainActor
final class AudioGraph: AudioGraphProtocol {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        try? session.setActive(true)
#endif
    }

    func play(url: URL) async throws {
        let file = try AVAudioFile(forReading: url)
        print("[AudioGraph] opened \(url.lastPathComponent) frames=\(file.length) sr=\(file.processingFormat.sampleRate)")
        guard file.length > 0 else {
            print("[AudioGraph] file has 0 frames — skipping playback")
            throw AudioGraphError.emptyFile
        }

        if !engine.isRunning {
            print("[AudioGraph] starting engine")
            try engine.start()
            print("[AudioGraph] engine started, isRunning=\(engine.isRunning)")
        }
        playerNode.stop()

        try await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                print("[AudioGraph] scheduling file with completion callback")
                playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                    print("[AudioGraph] completion callback fired")
                    continuation.resume()
                }
                print("[AudioGraph] calling play()")
                playerNode.play()
                print("[AudioGraph] play() called, isPlaying=\(self.playerNode.isPlaying)")
            }
            print("[AudioGraph] play() complete")
        } onCancel: {
            Task { @MainActor in self.playerNode.stop() }
        }
    }

    func stop() {
        playerNode.stop()
    }
}

enum AudioGraphError: Error {
    case emptyFile
}
