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
    private(set) var repeatMode: RepeatMode = .off
    private(set) var currentFeedback: TrackFeedback.Rating? = nil

    private(set) var isRegenerating = false

    private static let repeatModeKey = "nowPlayingRepeatMode"

    private let coordinator: PlaybackCoordinator
    private let musicService: any MusicKitServiceProtocol
    private let producer: Producer?
    private let feedbackStore: TrackFeedbackStore?
    private var monitorTask: Task<Void, Never>?

    init(coordinator: PlaybackCoordinator,
         musicService: any MusicKitServiceProtocol,
         producer: Producer? = nil,
         feedbackStore: TrackFeedbackStore? = nil) {
        self.coordinator = coordinator
        self.musicService = musicService
        self.producer = producer
        self.feedbackStore = feedbackStore

        // Hydrate repeat mode from UserDefaults and push it down to the
        // coordinator so its advance loop honors it from the first track.
        if let raw = UserDefaults.standard.string(forKey: Self.repeatModeKey),
           let mode = RepeatMode(rawValue: raw) {
            self.repeatMode = mode
            Task { await coordinator.setRepeatMode(mode) }
        }
    }

    func startObserving() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let state = await coordinator.state
                let index = await coordinator.currentIndex
                let queue = await coordinator.queue
                let item = queue.indices.contains(index) ? queue[index] : nil
                let time = await coordinator.musicPlaybackTime()
                let dur = await coordinator.musicTrackDuration() ?? 0

                // Pre-fetch current-track feedback outside the MainActor hop so
                // the actor call doesn't block the UI-state apply.
                let currentRating: TrackFeedback.Rating? = await {
                    if case .track(let t) = item {
                        return await self.feedbackStore?.rating(for: t.id)
                    }
                    return nil
                }()

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
                    self.currentFeedback = currentRating
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stopObserving() {
        monitorTask?.cancel()
        monitorTask = nil
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

    func shuffleUpcoming() {
        Task { await coordinator.shuffleUpcoming() }
    }

    func cycleRepeatMode() {
        let next = repeatMode.next()
        repeatMode = next
        UserDefaults.standard.set(next.rawValue, forKey: Self.repeatModeKey)
        Task { await coordinator.setRepeatMode(next) }
    }

    // MARK: - Feedback

    /// Thumbs-up / thumbs-down the current track. Re-tapping the active
    /// rating clears it (neutral). Thumbs-down also auto-skips the current
    /// track per the PM's Phase 3 spec.
    func rateCurrentTrack(_ rating: TrackFeedback.Rating) {
        guard case .track(let track) = currentItem, let store = feedbackStore else { return }
        if currentFeedback == rating {
            currentFeedback = nil
            Task { await store.clear(trackID: track.id) }
            return
        }
        currentFeedback = rating
        Task { await store.record(rating, trackID: track.id, title: track.title, artist: track.artist) }
        if rating == .down {
            skip()
        }
    }

    func regenerateDJ() {
        guard let producer, !isRegenerating else { return }
        isRegenerating = true
        Task {
            if let newSegment = await producer.regenerateCurrentSegment() {
                await coordinator.swapCurrentSegment(with: newSegment)
            }
            isRegenerating = false
        }
    }
}
