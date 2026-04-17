import Foundation

enum CoordinatorState: Sendable, Equatable {
    case idle, playing, paused, buffering
}

/// Event emitted when the coordinator is about to advance past the current item.
struct WillAdvanceEvent: Sendable {
    let currentTrack: Track
    let nextTrackIndex: Int
}

actor PlaybackCoordinator {

    // MARK: Dependencies

    private let musicService: any MusicKitServiceProtocol
    private let audioGraph: any AudioGraphProtocol

    // MARK: Queue state

    private(set) var queue: [PlayableItem] = []
    private(set) var currentIndex: Int = 0
    private(set) var state: CoordinatorState = .idle

    // MARK: Advance notifications (Producer subscribes here)

    private var willAdvanceContinuations: [UUID: AsyncStream<WillAdvanceEvent>.Continuation] = [:]

    var willAdvanceEvents: AsyncStream<WillAdvanceEvent> {
        AsyncStream { continuation in
            let id = UUID()
            willAdvanceContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeWillAdvanceContinuation(id: id) }
            }
        }
    }

    // MARK: Init

    init(musicService: any MusicKitServiceProtocol, audioGraph: any AudioGraphProtocol) {
        self.musicService = musicService
        self.audioGraph = audioGraph
    }

    // MARK: Queue management

    func replaceQueue(_ items: [PlayableItem]) {
        queue = items
        currentIndex = 0
        state = .idle
    }

    func enqueue(_ item: PlayableItem) {
        queue.append(item)
    }

    func insertAfterCurrent(_ item: PlayableItem) {
        let insertIndex = currentIndex + 1
        if insertIndex <= queue.count {
            queue.insert(item, at: insertIndex)
        } else {
            queue.append(item)
        }
    }

    func removeItem(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex = max(0, currentIndex - 1)
        }
    }

    // MARK: Transport

    func play() async throws {
        guard !queue.isEmpty else { return }
        state = .playing
        try await playCurrentItem()
    }

    func pause() async throws {
        guard state == .playing else { return }
        state = .paused
        try await musicService.stop()
        await audioGraph.stop()
    }

    func skip() async throws {
        guard currentIndex + 1 < queue.count else {
            state = .idle
            return
        }
        currentIndex += 1
        if state == .playing || state == .buffering {
            try await playCurrentItem()
        }
    }

    func previous() async throws {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        if state == .playing || state == .buffering {
            try await playCurrentItem()
        }
    }

    // MARK: Private

    private func playCurrentItem() async throws {
        guard currentIndex < queue.count else {
            state = .idle
            return
        }

        let item = queue[currentIndex]
        switch item {
        case .track(let track):
            try await playTrack(track)
        case .djSegment(let segment):
            try await playSegment(segment)
        }
    }

    private func playTrack(_ track: Track) async throws {
        state = .playing
        let duration = track.duration
        // Background task emits willAdvance at T-5s so Producer can prime the next segment
        Task { [weak self] in
            guard let self else { return }
            let delay = max(0, duration - 5.0)
            try? await Task.sleep(for: .seconds(delay))
            await self.emitWillAdvance(track: track)
        }
        try await musicService.start(track: track)
        // Approximate wait for track duration; MusicKit drives the actual playback
        try await Task.sleep(for: .seconds(duration))
        await advance()
    }

    private func playSegment(_ segment: DJSegment) async throws {
        state = .playing
        try await musicService.pause()
        try await audioGraph.play(url: segment.audioFileURL)
        await advance()
    }

    private func advance() async {
        guard state == .playing || state == .buffering else { return }
        currentIndex += 1
        if currentIndex < queue.count {
            try? await playCurrentItem()
        } else {
            state = .idle
        }
    }

    private func emitWillAdvance(track: Track) {
        let nextIndex = currentIndex + 1
        let event = WillAdvanceEvent(currentTrack: track, nextTrackIndex: nextIndex)
        for continuation in willAdvanceContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeWillAdvanceContinuation(id: UUID) {
        willAdvanceContinuations.removeValue(forKey: id)
    }
}
