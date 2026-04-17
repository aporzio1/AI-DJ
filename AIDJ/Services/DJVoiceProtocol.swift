import Foundation
import AVFoundation

protocol DJVoiceProtocol: AnyObject, Sendable {
    /// Renders `script` to a local .caf file and returns its URL.
    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL
}
