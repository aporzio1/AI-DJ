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
        print("[AudioGraph] scheduling file")
        await playerNode.scheduleFile(file, at: nil)
        print("[AudioGraph] calling play()")
        playerNode.play()
        print("[AudioGraph] play() called, isPlaying=\(playerNode.isPlaying)")

        let duration = file.duration
        print("[AudioGraph] sleeping for \(duration + 0.15)s")
        let task = Task<Void, Error> {
            try await Task.sleep(for: .seconds(duration + 0.15))
        }
        playbackTask = task
        try await task.value
        print("[AudioGraph] play() complete")
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
