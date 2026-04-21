import Foundation

/// Composes one or more `MusicProviderService` instances and exposes both a
/// playback façade (dispatching on `track.providerID` per plan §4d) and
/// per-provider accessors for library/search/auth calls that are inherently
/// per-provider. Mirrors the shape of `DJVoiceRouter`.
///
/// Phase 1 registers only Apple Music; Phase 2a introduces a second
/// provider. Non-track-bearing transport calls (pause/resume/stop/seek/
/// skipToNext/currentPlaybackTime/…) delegate to `currentProvider`, which
/// is whichever service started the last track. Until a second provider
/// exists, `currentProvider` is always the Apple Music service.
@MainActor
final class MusicProviderRouter {

    let appleMusic: any MusicProviderService

    init(appleMusic: any MusicProviderService) {
        self.appleMusic = appleMusic
    }

    // MARK: Track-bearing dispatch

    func start(track: Track) async throws {
        try await provider(for: track.providerID).start(track: track)
    }

    func isPlayable(_ track: Track) async -> Bool {
        await provider(for: track.providerID).isPlayable(trackId: track.id)
    }

    // MARK: Current-playback delegation

    func pause() async throws { try await currentProvider.pause() }
    func resume() async throws { try await currentProvider.resume() }
    func stop() async throws { try await currentProvider.stop() }
    func seek(to time: TimeInterval) async throws { try await currentProvider.seek(to: time) }
    func skipToNext() async throws { try await currentProvider.skipToNext() }
    func startStation(id: String) async throws { try await currentProvider.startStation(id: id) }

    var currentPlaybackTime: TimeInterval { currentProvider.currentPlaybackTime }
    var currentTrackDuration: TimeInterval? { currentProvider.currentTrackDuration }
    var currentTrack: Track? { currentProvider.currentTrack }
    var playbackStatus: MusicPlaybackStatus { currentProvider.playbackStatus }

    func artwork(for trackId: String) -> ProviderArtwork? { currentProvider.artwork(for: trackId) }

    // MARK: Internals

    private var currentProvider: any MusicProviderService { appleMusic }

    private func provider(for id: Track.MusicProviderID) -> any MusicProviderService {
        switch id {
        case .appleMusic: return appleMusic
        }
    }
}
