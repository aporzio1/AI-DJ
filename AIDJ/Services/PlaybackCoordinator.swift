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

    // Incremented every time a new playback starts. In-flight loops check this to detect
    // when they've been superseded and should exit without advancing.
    private var playbackGeneration: Int = 0

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

    func insertAt(_ index: Int, item: PlayableItem) {
        let clamped = max(0, min(index, queue.count))
        queue.insert(item, at: clamped)
        if clamped < currentIndex {
            currentIndex += 1
        }
    }

    /// Prepends an item at index 0 AND sets currentIndex to 0.
    /// Safe to call only when idle — used to prepend an opening DJ segment.
    func prependAndSelect(_ item: PlayableItem) {
        queue.insert(item, at: 0)
        currentIndex = 0
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
        audioGraph.stop()
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
        Log.coordinator.debug("seek(to: \(time, format: .fixed(precision: 1)))")
        try await musicService.seek(to: time)
    }

    /// Replace the currently-playing DJ segment with a new one and restart playback.
    /// No-op if the current item is not a segment.
    func swapCurrentSegment(with newSegment: DJSegment) async {
        guard currentIndex < queue.count, case .djSegment = queue[currentIndex] else {
            Log.coordinator.info("swapCurrentSegment: current item is not a segment")
            return
        }
        Log.coordinator.info("swapping current segment with fresh one")
        queue[currentIndex] = .djSegment(newSegment)
        playbackGeneration += 1
        audioGraph.stop()
        if state == .playing || state == .buffering {
            try? await playCurrentItem()
        }
    }

    func musicPlaybackTime() async -> TimeInterval {
        await musicService.currentPlaybackTime
    }

    func musicTrackDuration() async -> TimeInterval? {
        await musicService.currentTrackDuration
    }

    func isPlayable(trackId: String) async -> Bool {
        await musicService.isPlayable(trackId: trackId)
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
            do {
                try await playTrack(track)
            } catch {
                // MusicKit can fail for a specific track (unavailable in region,
                // removed from catalog, network blip, etc.). Don't stall the queue —
                // log and move to the next item.
                Log.coordinator.error("playTrack failed for '\(track.title, privacy: .public)': \(error, privacy: .public) — skipping")
                await advance()
            }
        case .djSegment(let segment):
            try await playSegment(segment)
        }
    }

    private func playTrack(_ track: Track) async throws {
        playbackGeneration += 1
        let myGen = playbackGeneration
        state = .playing
        Log.coordinator.info("playTrack '\(track.title, privacy: .public)' duration=\(track.duration)s (gen=\(myGen))")
        try await musicService.start(track: track)

        var emittedWillAdvance = false
        var willAdvanceRemaining: TimeInterval = 0
        var willAdvanceFiredAt: ContinuousClock.Instant? = nil
        let clock = ContinuousClock()
        var tickCount = 0
        var maxElapsedSeen: TimeInterval = 0

        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(500))

            if playbackGeneration != myGen {
                Log.coordinator.info("playTrack superseded (gen \(myGen) → \(self.playbackGeneration)) — exiting")
                return
            }

            // Check state BEFORE end-of-track heuristics. A pause() call that resets
            // playbackTime to 0 would otherwise falsely trigger the reset heuristic
            // and auto-advance to the next track.
            if state != .playing {
                Log.coordinator.info("state is \(String(describing: self.state), privacy: .public), exiting poll loop (gen=\(myGen))")
                return
            }

            tickCount += 1
            let elapsed = await musicService.currentPlaybackTime
            let duration = await musicService.currentTrackDuration ?? track.duration
            let remaining = duration - elapsed
            maxElapsedSeen = max(maxElapsedSeen, elapsed)

            if tickCount % 10 == 0 {
                Log.coordinator.debug("poll[gen=\(myGen)]: elapsed=\(elapsed, format: .fixed(precision: 1)) / \(duration, format: .fixed(precision: 1)) (remaining=\(remaining, format: .fixed(precision: 1)))")
            }

            if !emittedWillAdvance, duration > 0, remaining <= 5.0, remaining > 0 {
                Log.coordinator.info("T-\(remaining, format: .fixed(precision: 1))s — emitting willAdvance (gen=\(myGen))")
                emitWillAdvance(track: track)
                emittedWillAdvance = true
                willAdvanceRemaining = remaining
                willAdvanceFiredAt = clock.now
            }

            if let firedAt = willAdvanceFiredAt {
                let sinceFired = clock.now - firedAt
                if sinceFired >= .seconds(willAdvanceRemaining + 1.5) {
                    Log.coordinator.info("willAdvance timer elapsed — advancing (gen=\(myGen))")
                    break
                }
            }

            if maxElapsedSeen > 10, elapsed < 1.0 {
                Log.coordinator.info("playbackTime reset after progress — track ended (gen=\(myGen))")
                break
            }
        }
        guard playbackGeneration == myGen else {
            Log.coordinator.info("playTrack(gen=\(myGen)) skipping advance — superseded")
            return
        }
        await advance()
    }

    private func playSegment(_ segment: DJSegment) async throws {
        playbackGeneration += 1
        let myGen = playbackGeneration
        state = .playing
        Log.coordinator.info("playSegment kind=\(String(describing: segment.kind), privacy: .public) script=\"\(segment.script, privacy: .public)\" (gen=\(myGen))")
        try? await musicService.pause()
        do {
            try await audioGraph.play(url: segment.audioFileURL)
            Log.coordinator.info("segment done, resuming queue (gen=\(myGen))")
        } catch {
            Log.coordinator.error("segment playback failed: \(error, privacy: .public) — advancing anyway (gen=\(myGen))")
        }
        guard playbackGeneration == myGen else {
            Log.coordinator.info("playSegment(gen=\(myGen)) skipping advance — superseded")
            return
        }
        await advance()
    }

    private func advance() async {
        guard state == .playing || state == .buffering else { return }
        currentIndex += 1
        Log.coordinator.info("advance → currentIndex=\(self.currentIndex) (queue=\(self.queue.count))")
        if currentIndex < queue.count {
            try? await playCurrentItem()
        } else {
            state = .idle
            Log.coordinator.info("queue exhausted → idle")
        }
    }

    private func emitWillAdvance(track: Track) {
        let nextIndex = currentIndex + 1
        let event = WillAdvanceEvent(currentTrack: track, nextTrackIndex: nextIndex)
        Log.coordinator.debug("emitWillAdvance: \(self.willAdvanceContinuations.count) subscribers")
        for continuation in willAdvanceContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeWillAdvanceContinuation(id: UUID) {
        willAdvanceContinuations.removeValue(forKey: id)
    }
}
