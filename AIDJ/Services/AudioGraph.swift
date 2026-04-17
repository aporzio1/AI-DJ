import Foundation
import AVFoundation

@MainActor
final class AudioGraph: AudioGraphProtocol {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playbackTask: Task<Void, Error>?

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
        playbackTask?.cancel()

        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else {
            print("[AudioGraph] file at \(url.lastPathComponent) has 0 frames — skipping playback")
            throw AudioGraphError.emptyFile
        }

        if !engine.isRunning {
            try engine.start()
        }
        playerNode.stop()
        await playerNode.scheduleFile(file, at: nil)
        playerNode.play()

        let duration = file.duration
        let task = Task<Void, Error> {
            try await Task.sleep(for: .seconds(duration + 0.15))
        }
        playbackTask = task
        try await task.value
    }

    func stop() {
        playbackTask?.cancel()
        playerNode.stop()
    }
}

enum AudioGraphError: Error {
    case emptyFile
}

private extension AVAudioFile {
    var duration: TimeInterval {
        Double(length) / processingFormat.sampleRate
    }
}
