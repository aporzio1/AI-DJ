import Foundation
import AVFoundation

protocol DJVoiceProtocol: AnyObject, Sendable {
    /// Renders `script` to a local audio file and returns its URL. The
    /// container format is provider-specific (.caf for system, .mp3 for
    /// OpenAI, .wav for Kokoro) — AudioGraph handles all three.
    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL
}
