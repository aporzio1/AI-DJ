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

    func seek(to time: TimeInterval) async throws {
        print("[Coordinator] seek(to: \(String(format: "%.1f", time)))")
        try await musicService.seek(to: time)
    }

    func musicPlaybackTime() async -> TimeInterval {
        await musicService.currentPlaybackTime
    }

    func musicTrackDuration() async -> TimeInterval? {
        await musicService.currentTrackDuration
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
        print("[Coordinator] playTrack '\(track.title)' duration=\(track.duration)s")
        try await musicService.start(track: track)

        var emittedWillAdvance = false
        var tickCount = 0
        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(500))
            tickCount += 1
            let elapsed = await musicService.currentPlaybackTime
            let duration = await musicService.currentTrackDuration ?? track.duration
            let remaining = duration - elapsed

            // Heartbeat every 5 seconds so we can see the poll loop is alive
            if tickCount % 10 == 0 {
                print("[Coordinator] poll: elapsed=\(String(format: "%.1f", elapsed)) / \(String(format: "%.1f", duration)) (remaining=\(String(format: "%.1f", remaining)))")
            }

            if !emittedWillAdvance, duration > 0, remaining <= 5.0, remaining > 0 {
                print("[Coordinator] T-\(String(format: "%.1f", remaining))s — emitting willAdvance")
                emitWillAdvance(track: track)
                emittedWillAdvance = true
            }

            let status = await musicService.playbackStatus
            if duration > 0 && elapsed >= duration - 0.3 {
                print("[Coordinator] track reached end by time (elapsed=\(elapsed))")
                break
            }
            if status == .stopped {
                print("[Coordinator] music service reports stopped")
                break
            }
            if state != .playing {
                print("[Coordinator] state is \(state), exiting poll loop")
                return
            }
        }
        await advance()
    }

    private func playSegment(_ segment: DJSegment) async throws {
        state = .playing
        print("[Coordinator] playSegment kind=\(segment.kind) script=\"\(segment.script)\"")
        try await musicService.pause()
        try await audioGraph.play(url: segment.audioFileURL)
        print("[Coordinator] segment done, resuming queue")
        await advance()
    }

    private func advance() async {
        guard state == .playing || state == .buffering else { return }
        currentIndex += 1
        print("[Coordinator] advance → currentIndex=\(currentIndex) (queue=\(queue.count))")
        if currentIndex < queue.count {
            try? await playCurrentItem()
        } else {
            state = .idle
            print("[Coordinator] queue exhausted → idle")
        }
    }

    private func emitWillAdvance(track: Track) {
        let nextIndex = currentIndex + 1
        let event = WillAdvanceEvent(currentTrack: track, nextTrackIndex: nextIndex)
        print("[Coordinator] emitWillAdvance: \(willAdvanceContinuations.count) subscribers")
        for continuation in willAdvanceContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeWillAdvanceContinuation(id: UUID) {
        willAdvanceContinuations.removeValue(forKey: id)
    }
}
