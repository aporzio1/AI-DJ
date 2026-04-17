import Foundation
import MusicKit

@Observable
@MainActor
final class NowPlayingViewModel {

    private(set) var currentItem: PlayableItem?
    private(set) var playbackState: CoordinatorState = .idle
    private(set) var isDJSpeaking: Bool = false
    private(set) var playbackTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentArtwork: Artwork?

    private let coordinator: PlaybackCoordinator
    private let musicService: any MusicKitServiceProtocol
    private var monitorTask: Task<Void, Never>?

    init(coordinator: PlaybackCoordinator, musicService: any MusicKitServiceProtocol) {
        self.coordinator = coordinator
        self.musicService = musicService
    }

    func startObserving() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let state = await coordinator.state
                let index = await coordinator.currentIndex
                let queue = await coordinator.queue
                let item = queue.indices.contains(index) ? queue[index] : nil
                let time = await coordinator.musicPlaybackTime()
                let dur = await coordinator.musicTrackDuration() ?? 0

                await MainActor.run {
                    self.playbackState = state
                    self.currentItem = item
                    self.playbackTime = time
                    self.duration = dur
                    self.isDJSpeaking = {
                        if case .djSegment = item { return state == .playing }
                        return false
                    }()
                    self.currentArtwork = {
                        if case .track(let t) = item { return self.musicService.artwork(for: t.id) }
                        return nil
                    }()
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stopObserving() {
        monitorTask?.cancel()
    }

    func play() {
        Task { try? await coordinator.play() }
    }

    func pause() {
        Task { try? await coordinator.pause() }
    }

    func skip() {
        Task { try? await coordinator.skip() }
    }

    func previous() {
        Task { try? await coordinator.previous() }
    }

    func seek(to time: TimeInterval) {
        Task { try? await coordinator.seek(to: time) }
    }
}
