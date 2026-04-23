import Foundation

/// Composes one or more `MusicProviderService` instances and exposes both a
/// playback façade (dispatching on `track.providerID` per plan §4d) and a
/// per-provider accessor for library/search/auth calls that are inherently
/// per-provider. Mirrors the shape of `DJVoiceRouter`.
///
/// Apple Music is the only provider today. Spotify was attempted in Phase 2
/// but withdrawn (see `docs/project-tracker.md` K21 — Spotify's iOS SDK
/// only supports remote-control of the Spotify app, no standalone in-app
/// playback). The router abstraction is kept so a future provider that
/// actually ships a native streaming SDK can slot in without re-threading
/// the coordinator / VM plumbing.
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
