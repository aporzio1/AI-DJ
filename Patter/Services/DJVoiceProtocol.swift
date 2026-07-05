import Foundation
import AVFoundation

protocol DJVoiceProtocol: AnyObject, Sendable {
    /// Renders `script` to a local audio file and returns its URL. The
    /// container format is provider-specific (.caf for system, .mp3 for
    /// OpenAI, .wav for Kokoro) — AudioGraph handles all three.
    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL

    /// Best-effort warm-up hook: pays any first-render cold-start cost (AU
    /// IPC handshake, voice-model load) ahead of time so the first real
    /// render is fast. Default is a no-op — only providers with a
    /// meaningful cold-start path need to override.
    func warmUp(voiceIdentifier: String) async
}

extension DJVoiceProtocol {
    func warmUp(voiceIdentifier: String) async {}
}
