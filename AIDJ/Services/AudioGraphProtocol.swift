import Foundation

protocol AudioGraphProtocol: AnyObject, Sendable {
    /// Plays the audio file at `url`. Returns when playback completes.
    func play(url: URL) async throws
    func stop() async
}
