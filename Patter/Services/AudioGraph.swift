import Foundation
import AVFoundation

actor AudioGraph: AudioGraphProtocol {

    nonisolated(unsafe) private let engine = AVAudioEngine()
    nonisolated(unsafe) private let playerNode = AVAudioPlayerNode()
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var lastBufferFormat: AVAudioFormat?

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

        // Decode the whole file into a PCM buffer. scheduleBuffer is more reliable
        // than scheduleFile for compressed formats (MP3, AAC), and lets us reconnect
        // the player node with whatever format the buffer actually has — which avoids
        // silent-output issues when segments arrive in different formats (CAF from
        // system TTS, MP3 from OpenAI TTS).
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioGraphError.bufferAllocationFailed
        }
        try file.read(into: buffer)

        // Only stop + reconnect on format change. playerNode.stop() blocks on
        // a CoreAudio default-QoS thread; calling it from a user-initiated
        // caller trips the priority-inversion diagnostic. Skipping it in the
        // common same-format case, and using scheduleBuffer(options:.interrupts)
        // to supersede any in-flight buffer, avoids the inversion on >90% of
        // back-to-back DJ segments (same provider = same format).
        let formatChanged = (lastBufferFormat != buffer.format)
        if formatChanged {
            Log.audio.debug("format change → reconnect: \(String(describing: buffer.format), privacy: .public)")
            playerNode.stop()
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
            lastBufferFormat = buffer.format
        }

        if !engine.isRunning {
            Log.audio.debug("starting engine")
            try engine.start()
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.pendingContinuation = continuation
                let options: AVAudioPlayerNodeBufferOptions = formatChanged ? [] : .interrupts
                playerNode.scheduleBuffer(buffer, at: nil, options: options, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task(priority: .utility) { await self?.resumePending() }
                }
                if !playerNode.isPlaying {
                    playerNode.play()
                }
                Log.audio.debug("play() called, isPlaying=\(self.playerNode.isPlaying) format=\(String(describing: buffer.format), privacy: .public)")
            }
            Log.audio.debug("play() complete")
        } onCancel: {
            stop()
        }
    }

    /// Nonisolated so callers at any QoS don't block on CoreAudio teardown.
    /// The actual stop is deferred to a utility-priority Task so the caller
    /// returns immediately (audio stops within a few ms on the background).
    nonisolated func stop() {
        Task(priority: .utility) { [self] in
            self.playerNode.stop()
            await self.resumePending()
        }
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
    case bufferAllocationFailed
}
