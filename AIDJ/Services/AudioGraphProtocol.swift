import Foundation

protocol AudioGraphProtocol: AnyObject, Sendable {
    /// Plays the audio file at `url`. Returns when playback completes.
    func play(url: URL) async throws
    /// Stop playback immediately. Safe to call from any thread — doesn't block the caller on CoreAudio.
    func stop()
}
