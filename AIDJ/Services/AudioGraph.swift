import Foundation
import AVFoundation

actor AudioGraph: AudioGraphProtocol {

    nonisolated(unsafe) private let engine = AVAudioEngine()
    nonisolated(unsafe) private let playerNode = AVAudioPlayerNode()
    private var pendingContinuation: CheckedContinuation<Void, Never>?

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
        Log.audio.debug("opened \(url.lastPathComponent, privacy: .public) frames=\(file.length) sr=\(file.processingFormat.sampleRate)")
        guard file.length > 0 else {
            Log.audio.error("file has 0 frames — skipping playback")
            throw AudioGraphError.emptyFile
        }

        if !engine.isRunning {
            Log.audio.debug("starting engine")
            try engine.start()
        }
        playerNode.stop()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.pendingContinuation = continuation
                playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task(priority: .utility) { await self?.resumePending() }
                }
                playerNode.play()
                Log.audio.debug("play() called, isPlaying=\(self.playerNode.isPlaying)")
            }
            Log.audio.debug("play() complete")
        } onCancel: {
            // Stop the player directly (thread-safe); resume the continuation via the actor.
            playerNode.stop()
            Task(priority: .utility) { await self.resumePending() }
        }
    }

    /// Nonisolated so callers at any QoS don't block the actor's executor on the
    /// synchronous CoreAudio stop (which runs at default QoS → priority inversion).
    nonisolated func stop() {
        playerNode.stop()
        Task(priority: .utility) { await self.resumePending() }
    }

    private func resumePending() {
        if let c = pendingContinuation {
            pendingContinuation = nil
            c.resume()
        }
    }
}

enum AudioGraphError: Error {
    case emptyFile
}
