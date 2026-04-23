import Foundation
import MusicKit
@testable import Patter

// MARK: - FakeMusicService

@MainActor
final class FakeMusicService: MusicProviderService {
    var providerID: Patter.Track.MusicProviderID = .appleMusic
    var authorizationStatus: ProviderAuthStatus = .authorized

    var startedTracks: [Patter.Track] = []
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopCallCount = 0

    var currentPlaybackTime: TimeInterval = 0
    var currentTrackDuration: TimeInterval? = nil
    var currentTrack: Patter.Track? = nil
    var playbackStatus: MusicPlaybackStatus = .stopped

    func requestAuthorization() async -> ProviderAuthStatus { .authorized }
    func signOut() async { authorizationStatus = .notAuthorized }
    func start(track: Patter.Track) async throws { startedTracks.append(track); currentTrack = track }
    func pause() async throws { pauseCallCount += 1 }
    func resume() async throws { resumeCallCount += 1 }
    func stop() async throws { stopCallCount += 1 }
    func seek(to time: TimeInterval) async throws { currentPlaybackTime = time }
    func playlists() async throws -> [PlaylistInfo] { [] }
    func songs(inPlaylistWith id: String) async throws -> [Patter.Track] { [] }
    func songs(inAlbumWith id: String) async throws -> [Patter.Track] { [] }
    func startStation(id: String) async throws {}
    func skipToNext() async throws {}
    func searchCatalogSongs(query: String, limit: Int) async throws -> [Patter.Track] { [] }
    func isPlayable(trackId: String) async -> Bool { true }
    func artwork(for trackId: String) -> ProviderArtwork? { nil }

    var fakeRecentlyPlayed: [LibraryItem] = []
    var fakeRecommendations: [LibraryItem] = []
    func recentlyPlayed() async throws -> [LibraryItem] { fakeRecentlyPlayed }
    func recommendations() async throws -> [LibraryItem] { fakeRecommendations }
}

// MARK: - FakeAudioGraph

/// `AudioGraphProtocol` is non-isolated + `Sendable`, matching the production
/// `AudioGraph` actor which exposes a `nonisolated func stop()`. The fake
/// mirrors that isolation — `@unchecked Sendable` is safe here because the
/// unit tests exercise this class sequentially from a single `@MainActor`
/// context.
final class FakeAudioGraph: AudioGraphProtocol, @unchecked Sendable {
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
    var updatedFeeds: [URL] = []

    func fetchHeadlines() async throws -> [NewsHeadline] {
        fetchCallCount += 1
        return headlines
    }

    func updateFeeds(_ urls: [URL]) {
        updatedFeeds = urls
    }
}

// MARK: - Helpers

enum FakeError: Error {
    case intentional
}

extension Patter.Track {
    static func stub(id: String = UUID().uuidString, title: String = "Track", duration: TimeInterval = 180) -> Patter.Track {
        Patter.Track(id: id, title: title, artist: "Artist", album: "Album", artworkURL: nil, duration: duration, providerID: .appleMusic)
    }
}

extension DJSegment {
    static func stub(duration: TimeInterval = 3.0) -> DJSegment {
        DJSegment(id: UUID(), kind: .banter, script: "Banter.", audioFileURL: URL(filePath: "/tmp/seg.caf"), duration: duration, overlapStart: nil)
    }
}
