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

    private let router: MusicProviderRouter
    private let audioGraph: any AudioGraphProtocol

    // MARK: Queue state

    private(set) var queue: [PlayableItem] = []
    private(set) var currentIndex: Int = 0
    private(set) var state: CoordinatorState = .idle
    private(set) var repeatMode: RepeatMode = .off
    /// Localized description of the most recent track-playback failure.
    /// Reset by `replaceQueue`. Surfaced to the caller (LibraryViewModel
    /// via `invokePlay`) so silent per-track try/catch skips don't leave
    /// the user staring at a UI that did nothing. Read once after
    /// `play()` returns; if non-nil and the queue exhausted, the UI
    /// shows it as a `playbackAlertMessage`.
    private(set) var lastPlaybackError: String?
    /// True when MusicKit is playing open-ended content (a station) that
    /// doesn't fit our [PlayableItem] queue model. Transport still works
    /// via ApplicationMusicPlayer directly; NowPlayingViewModel falls
    /// back to `router.currentTrack` for display.
    private(set) var externalPlaybackActive: Bool = false

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

    init(router: MusicProviderRouter, audioGraph: any AudioGraphProtocol) {
        self.router = router
        self.audioGraph = audioGraph
    }

    // MARK: Queue management

    /// Replace the queue. Stops whatever's currently playing first —
    /// MusicKit and AudioGraph both — and bumps `playbackGeneration` so
    /// any in-flight `playSegment` / `monitorTrackUntilEnd` tasks notice
    /// they've been superseded and exit cleanly. Without this, the
    /// previous track/segment keeps playing for the ~3 seconds it takes
    /// the new opening intro to generate, bleeding over the new audio.
    func replaceQueue(_ items: [PlayableItem]) async {
        playbackGeneration += 1
        try? await router.stop()
        audioGraph.stop()
        queue = items
        currentIndex = 0
        state = .idle
        externalPlaybackActive = false
        lastPlaybackError = nil
    }

    /// Start a station via MusicKit, bypassing our track queue entirely.
    /// Sets `externalPlaybackActive` so transport (pause / resume / skip)
    /// knows to route through `router` directly, and so the VM
    /// knows to display MusicKit's current track instead of our (empty)
    /// queue.
    func startStation(id: String) async throws {
        playbackGeneration += 1
        audioGraph.stop()
        queue = []
        currentIndex = 0
        externalPlaybackActive = true
        try await router.startStation(id: id)
        state = .playing
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
        // Station / external playback path — transport talks to MusicKit
        // directly, not to our queue.
        if externalPlaybackActive {
            if state == .paused {
                state = .playing
                try await router.resume()
            }
            return
        }
        guard !queue.isEmpty else { return }
        // Resume in place if we were paused on a track — avoid the
        // start(track:) call, which rebuilds the MusicKit queue and
        // restarts the song from the beginning.
        if state == .paused,
           currentIndex < queue.count,
           case .track(let track) = queue[currentIndex] {
            let resumePoint = await router.currentPlaybackTime
            Log.coordinator.info("play() — resuming '\(track.title, privacy: .public)' at \(resumePoint)s")
            // Flip state BEFORE entering the monitor. monitorTrackUntilEnd
            // exits immediately if state != .playing, so missing this
            // assignment left the coordinator stuck in .paused even though
            // MusicKit had already resumed — the play/pause button in the
            // UI never flipped back to "pause" on second-play-after-pause.
            state = .playing
            try await router.resume()
            try await monitorTrackUntilEnd(track: track)
            return
        }
        state = .playing
        try await playCurrentItem()
    }

    func pause() async throws {
        guard state == .playing else { return }
        state = .paused
        if externalPlaybackActive {
            try await router.pause()
            return
        }
        // Preserve position for tracks; DJ segments have no seek-resume so
        // their audioGraph output just gets stopped.
        if currentIndex < queue.count, case .track = queue[currentIndex] {
            try await router.pause()
        }
        audioGraph.stop()
    }

    func skip() async throws {
        if externalPlaybackActive {
            try await router.skipToNext()
            return
        }
        // Kill any in-flight DJ segment audio and invalidate in-flight
        // monitor / playSegment loops so they don't race the next item.
        // Without this, skipping while the DJ was mid-sentence left the
        // audio-graph player node playing the segment over the new track.
        playbackGeneration += 1
        audioGraph.stop()
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
        // Same DJ-audio + generation invalidation as skip().
        playbackGeneration += 1
        audioGraph.stop()
        currentIndex -= 1
        if state == .playing || state == .buffering {
            try await playCurrentItem()
        }
    }

    func seek(to time: TimeInterval) async throws {
        Log.coordinator.debug("seek(to: \(time, format: .fixed(precision: 1)))")
        try await router.seek(to: time)
    }

    // MARK: Shuffle + Repeat

    /// Shuffles everything after the currently-playing item. History stays in
    /// place; the current item stays where it is so playback doesn't restart.
    func shuffleUpcoming() {
        guard currentIndex + 1 < queue.count else { return }
        let head = Array(queue.prefix(currentIndex + 1))
        let tail = Array(queue.suffix(from: currentIndex + 1)).shuffled()
        queue = head + tail
        Log.coordinator.info("shuffleUpcoming: reshuffled \(tail.count) items after currentIndex=\(self.currentIndex)")
    }

    func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
        Log.coordinator.info("repeatMode → \(String(describing: mode), privacy: .public)")
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
        await router.currentPlaybackTime
    }

    func musicTrackDuration() async -> TimeInterval? {
        await router.currentTrackDuration
    }

    func isPlayable(_ track: Track) async -> Bool {
        await router.isPlayable(track)
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
                // MusicKit can fail per-track (unavailable in region,
                // removed from catalog, rights changed, etc.). Don't stall
                // the queue — log the specific error so the VM can surface
                // it after play() returns, then try the next track.
                Log.coordinator.error("playTrack failed for '\(track.title, privacy: .public)': \(error, privacy: .public) — skipping")
                lastPlaybackError = error.localizedDescription
                await advance()
            }
        case .djSegment(let segment):
            try await playSegment(segment)
        }
    }

    private func playTrack(_ track: Track) async throws {
        state = .playing
        Log.coordinator.info("playTrack '\(track.title, privacy: .public)' duration=\(track.duration)s")
        try await router.start(track: track)
        try await monitorTrackUntilEnd(track: track)
    }

    /// Polls MusicKit while a track is playing, emits willAdvance near the
    /// end, and advances when the track actually finishes. Shared between
    /// the cold-start path (playTrack → start + monitor) and the
    /// resume-from-pause path (play → resume + monitor).
    private func monitorTrackUntilEnd(track: Track) async throws {
        playbackGeneration += 1
        let myGen = playbackGeneration

        var emittedWillAdvance = false
        var willAdvanceRemaining: TimeInterval = 0
        var willAdvanceFiredAt: ContinuousClock.Instant? = nil
        let clock = ContinuousClock()
        var tickCount = 0
        var maxElapsedSeen: TimeInterval = 0

        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(500))

            if playbackGeneration != myGen {
                Log.coordinator.info("monitor superseded (gen \(myGen) → \(self.playbackGeneration)) — exiting")
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
            let elapsed = await router.currentPlaybackTime
            let duration = await router.currentTrackDuration ?? track.duration
            let remaining = duration - elapsed
            maxElapsedSeen = max(maxElapsedSeen, elapsed)

            if tickCount % 10 == 0 {
                Log.coordinator.debug("poll[gen=\(myGen)]: elapsed=\(elapsed, format: .fixed(precision: 1)) / \(duration, format: .fixed(precision: 1)) (remaining=\(remaining, format: .fixed(precision: 1)))")
            }

            // Fire willAdvance with a wide lead time so segment generation
            // (Foundation Models text + cloud TTS round-trip — combined this
            // can run 10–15s on slow generations) has room to finish before
            // the track ends. Without enough headroom, Producer drops the
            // rendered segment because the upcoming track has already become
            // the current track. The advance timer still pins the actual
            // handoff to the track's real end.
            if !emittedWillAdvance, duration > 0, remaining <= 35.0, remaining > 0 {
                if repeatMode == .one {
                    Log.coordinator.info("T-\(remaining, format: .fixed(precision: 1))s — repeat.one, skipping willAdvance emit (gen=\(myGen))")
                } else {
                    Log.coordinator.info("T-\(remaining, format: .fixed(precision: 1))s — emitting willAdvance (gen=\(myGen))")
                    emitWillAdvance(track: track)
                }
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
            Log.coordinator.info("monitor(gen=\(myGen)) skipping advance — superseded")
            return
        }
        await advance()
    }

    private func playSegment(_ segment: DJSegment) async throws {
        playbackGeneration += 1
        let myGen = playbackGeneration
        state = .playing
        Log.coordinator.info("playSegment kind=\(String(describing: segment.kind), privacy: .public) script=\"\(segment.script, privacy: .public)\" (gen=\(myGen))")
        try? await router.pause()
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

        // repeat.one replays the current item instead of advancing. Apply only
        // to tracks — a DJ segment is never worth looping forever.
        if repeatMode == .one, currentIndex < queue.count,
           case .track = queue[currentIndex] {
            Log.coordinator.info("repeat.one → replaying current track")
            try? await playCurrentItem()
            return
        }

        currentIndex += 1
        Log.coordinator.info("advance → currentIndex=\(self.currentIndex) (queue=\(self.queue.count))")
        if currentIndex < queue.count {
            try? await playCurrentItem()
        } else if repeatMode == .all, !queue.isEmpty {
            currentIndex = 0
            Log.coordinator.info("repeat.all → wrapping to start")
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
