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

    /// When set, `start(track:)` throws this instead of recording the track —
    /// exercises PlaybackCoordinator/Producer error paths that a
    /// never-fails fake can't reach.
    var startError: Error?
    var songsInPlaylist: [String: [Patter.Track]] = [:]

    func requestAuthorization() async -> ProviderAuthStatus { .authorized }
    func signOut() async { authorizationStatus = .notAuthorized }
    func start(track: Patter.Track) async throws {
        if let startError { throw startError }
        startedTracks.append(track)
        currentTrack = track
    }
    func pause() async throws { pauseCallCount += 1 }
    func resume() async throws { resumeCallCount += 1 }
    func stop() async throws { stopCallCount += 1 }
    func seek(to time: TimeInterval) async throws { currentPlaybackTime = time }
    func playlists() async throws -> [PlaylistInfo] { [] }
    func songs(inPlaylistWith id: String) async throws -> [Patter.Track] { songsInPlaylist[id] ?? [] }
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

/// `DJBrainProtocol` requirements are all `async`, so a `@MainActor`
/// witness is a legal conformance — callers already cross an isolation
/// boundary to invoke them. Drops the `@unchecked Sendable` escape hatch
/// in favor of real actor isolation.
@MainActor
final class FakeDJBrain: DJBrainProtocol {
    var nextScript = "Up next, great stuff."
    var generateCallCount = 0
    var shouldThrow = false
    var lastContext: DJContext?

    func generateScript(for context: DJContext) async throws -> String {
        generateCallCount += 1
        lastContext = context
        if shouldThrow { throw FakeError.intentional }
        return nextScript
    }
}

// MARK: - FakeDJVoice

@MainActor
final class FakeDJVoice: DJVoiceProtocol {
    var renderCallCount = 0
    var shouldThrow = false
    var fakeURL = makeTemporaryFileURL(extension: "caf")
    var lastScript: String?
    var lastVoiceIdentifier: String?

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        renderCallCount += 1
        lastScript = script
        lastVoiceIdentifier = voiceIdentifier
        if shouldThrow { throw FakeError.intentional }
        return fakeURL
    }
}

// MARK: - FakeKokoroDJVoice

@MainActor
final class FakeKokoroDJVoice: DJVoiceProtocol, KokoroModelManaging {
    var renderCallCount = 0
    var shouldThrow = false
    var fakeURL = makeTemporaryFileURL(extension: "caf")
    var prepareModelCallCount = 0
    var removeModelCallCount = 0

    func renderToFile(script: String, voiceIdentifier: String) async throws -> URL {
        renderCallCount += 1
        if shouldThrow { throw FakeError.intentional }
        return fakeURL
    }

    func prepareModel() async throws { prepareModelCallCount += 1 }
    func removeModel() async throws { removeModelCallCount += 1 }
}

// MARK: - FakeRSSFetcher

/// Unlike `FakeDJBrain`/`FakeDJVoice`, `RSSFetcherProtocol` has one
/// non-async requirement (`updateFeeds`), so it can't take a `@MainActor`
/// witness without breaking nonisolated callers — stays `@unchecked
/// Sendable`, safe here since tests exercise it sequentially.
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

// MARK: - FakeArticleFetcher

final class FakeArticleFetcher: ArticleFetching, @unchecked Sendable {
    var result: String?
    var requestedURLs: [URL] = []
    var requestedMaxChars: [Int] = []
    func body(for url: URL, maxChars: Int) async -> String? {
        requestedURLs.append(url)
        requestedMaxChars.append(maxChars)
        return result
    }
}

// MARK: - Helpers

enum FakeError: Error {
    case intentional
}

/// A unique, non-colliding placeholder file URL under the system temp
/// directory — avoids fakes racing on a shared hardcoded path like
/// `/tmp/fake.caf` when tests run concurrently.
func makeTemporaryFileURL(extension ext: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
}

extension Patter.Track {
    static func stub(id: String = UUID().uuidString, title: String = "Track", duration: TimeInterval = 180) -> Patter.Track {
        Patter.Track(id: id, title: title, artist: "Artist", album: "Album", artworkURL: nil, duration: duration, providerID: .appleMusic)
    }
}

extension DJSegment {
    static func stub(duration: TimeInterval = 3.0) -> DJSegment {
        DJSegment(id: UUID(), kind: .banter, script: "Banter.", audioFileURL: makeTemporaryFileURL(extension: "caf"), duration: duration, overlapStart: nil, sourceHeadline: nil)
    }
}
