import Foundation
import MusicKit
@testable import AIDJ

// MARK: - FakeMusicService

@MainActor
final class FakeMusicService: MusicKitServiceProtocol {
    var authorizationStatus: MusicAuthorization.Status = .authorized

    var startedTracks: [AIDJ.Track] = []
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopCallCount = 0

    var currentPlaybackTime: TimeInterval = 0
    var currentTrackDuration: TimeInterval? = nil
    var currentTrack: AIDJ.Track? = nil
    var playbackStatus: MusicPlaybackStatus = .stopped

    func requestAuthorization() async -> MusicAuthorization.Status { .authorized }
    func start(track: AIDJ.Track) async throws { startedTracks.append(track); currentTrack = track }
    func pause() async throws { pauseCallCount += 1 }
    func resume() async throws { resumeCallCount += 1 }
    func stop() async throws { stopCallCount += 1 }
    func seek(to time: TimeInterval) async throws { currentPlaybackTime = time }
    func playlists() async throws -> [PlaylistInfo] { [] }
    func songs(inPlaylistWith id: String) async throws -> [AIDJ.Track] { [] }
    func searchCatalogSongs(query: String, limit: Int) async throws -> [AIDJ.Track] { [] }
    func artwork(for trackId: String) -> Artwork? { nil }
}

// MARK: - FakeAudioGraph

@MainActor
final class FakeAudioGraph: AudioGraphProtocol {
    var playedURLs: [URL] = []
    var stopCallCount = 0
    var playDelay: TimeInterval = 0

    func play(url: URL) async throws {
        playedURLs.append(url)
        if playDelay > 0 {
            try await Task.sleep(for: .seconds(playDelay))
        }
    }

    func stop() {
        stopCallCount += 1
    }
}

// MARK: - FakeDJBrain

final class FakeDJBrain: DJBrainProtocol, @unchecked Sendable {
    var nextScript = "Up next, great stuff."
    var generateCallCount = 0
    var shouldThrow = false

    func generateScript(for context: DJContext) async throws -> String {
        generateCallCount += 1
        if shouldThrow { throw FakeError.intentional }
        return nextScript
    }
}

// MARK: - FakeDJVoice

final class FakeDJVoice: DJVoiceProtocol, @unchecked Sendable {
    var renderCallCount = 0
    var shouldThrow = false
    var fakeURL = URL(filePath: "/tmp/fake.caf")
    var lastScript: String?

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        renderCallCount += 1
        lastScript = script
        if shouldThrow { throw FakeError.intentional }
        return fakeURL
    }
}

// MARK: - FakeRSSFetcher

final class FakeRSSFetcher: RSSFetcherProtocol, @unchecked Sendable {
    var headlines: [NewsHeadline] = []
    var fetchCallCount = 0

    func fetchHeadlines() async throws -> [NewsHeadline] {
        fetchCallCount += 1
        return headlines
    }
}

// MARK: - Helpers

enum FakeError: Error {
    case intentional
}

extension AIDJ.Track {
    static func stub(id: String = UUID().uuidString, title: String = "Track", duration: TimeInterval = 180) -> AIDJ.Track {
        AIDJ.Track(id: id, title: title, artist: "Artist", album: "Album", artworkURL: nil, duration: duration, providerID: .appleMusic)
    }
}

extension DJSegment {
    static func stub(duration: TimeInterval = 3.0) -> DJSegment {
        DJSegment(id: UUID(), kind: .banter, script: "Banter.", audioFileURL: URL(filePath: "/tmp/seg.caf"), duration: duration, overlapStart: nil)
    }
}
