import Foundation

/// Subscribes to PlaybackCoordinator advance events and primes DJ segments in advance.
/// On any failure in the generation pipeline, degrades gracefully (never stops music).
actor Producer {

    private let coordinator: PlaybackCoordinator
    private let brain: any DJBrainProtocol
    private let voice: any DJVoiceProtocol
    private let rssFetcher: any RSSFetcherProtocol
    private let persona: DJPersona
    private var listenerName: String?

    private var recentTracks: [AIDJ.Track] = []
    private var monitorTask: Task<Void, Never>?
    private var tracksSinceLastSegment = 0
    private var hasGivenIntro = false

    init(
        coordinator: PlaybackCoordinator,
        brain: any DJBrainProtocol,
        voice: any DJVoiceProtocol,
        rssFetcher: any RSSFetcherProtocol,
        persona: DJPersona = .default,
        listenerName: String? = nil
    ) {
        self.coordinator = coordinator
        self.brain = brain
        self.voice = voice
        self.rssFetcher = rssFetcher
        self.persona = persona
        self.listenerName = listenerName
    }

    func updateListenerName(_ name: String?) {
        listenerName = name
    }

    /// Generate and insert a DJ intro at position 0 of the queue, to play BEFORE the first track.
    func primeOpeningIntro() async {
        let queue = await coordinator.queue
        guard let firstTrack = queue.first, case .track(let upcoming) = firstTrack else { return }
        print("[Producer] Priming opening intro for '\(upcoming.title)'")
        hasGivenIntro = true
        tracksSinceLastSegment = 0
        guard let segment = await generateSegment(upcomingTrack: upcoming) else { return }
        await coordinator.insertAt(0, item: .djSegment(segment))
    }

    // MARK: Lifecycle

    func start() {
        print("[Producer] start() — subscribing to willAdvance events")
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await event in await coordinator.willAdvanceEvents {
                print("[Producer] Received willAdvance for '\(event.currentTrack.title)' → nextIndex=\(event.nextTrackIndex)")
                await self.handleWillAdvance(event)
            }
            print("[Producer] willAdvance stream ended")
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: Private

    /// Exposed for unit tests only.
    func handleWillAdvanceForTesting(_ event: WillAdvanceEvent) async {
        await handleWillAdvance(event)
    }

    private func handleWillAdvance(_ event: WillAdvanceEvent) async {
        let track = event.currentTrack
        recentTracks.append(track)
        if recentTracks.count > 5 { recentTracks.removeFirst() }

        let queue = await coordinator.queue
        guard event.nextTrackIndex < queue.count else { return }
        let nextItem = queue[event.nextTrackIndex]
        guard case .track(let upcomingTrack) = nextItem else { return }

        // Try to prime a DJ segment; degrade gracefully on any failure
        if let segment = await primeSegment(upcomingTrack: upcomingTrack) {
            await coordinator.insertAfterCurrent(.djSegment(segment))
        }
    }

    private func shouldGenerate() -> Bool {
        // First transition always gets a DJ intro
        if !hasGivenIntro {
            hasGivenIntro = true
            tracksSinceLastSegment = 0
            return true
        }
        // After 3 straight skips, force a segment so the DJ stays present
        if tracksSinceLastSegment >= 3 {
            tracksSinceLastSegment = 0
            return true
        }
        // Otherwise 50/50
        if Bool.random() {
            tracksSinceLastSegment = 0
            return true
        }
        tracksSinceLastSegment += 1
        return false
    }

    private func primeSegment(upcomingTrack: AIDJ.Track) async -> DJSegment? {
        guard shouldGenerate() else {
            print("[Producer] Skipping DJ for this transition (tracksSinceLast=\(tracksSinceLastSegment))")
            return nil
        }
        return await generateSegment(upcomingTrack: upcomingTrack)
    }

    private func generateSegment(upcomingTrack: AIDJ.Track) async -> DJSegment? {
        let headline = try? await rssFetcher.fetchHeadlines().first

        let context = DJContext(
            persona: persona,
            upcomingTrack: upcomingTrack,
            recentTracks: recentTracks,
            timeOfDay: .current(),
            newsHeadline: headline,
            listenerName: listenerName
        )

        let script: String
        do {
            script = try await brain.generateScript(for: context)
            print("[Producer] DJBrain script: \"\(script)\"")
        } catch {
            print("[Producer] DJBrain failed (\(error)) — falling back to canned template")
            script = "Up next, \(upcomingTrack.title) by \(upcomingTrack.artist)."
        }

        do {
            let audioURL = try await voice.renderToFile(script: script, voiceIdentifier: persona.voicePreset)
            print("[Producer] DJVoice rendered to \(audioURL.lastPathComponent)")
            return DJSegment(
                id: UUID(),
                kind: headline != nil ? .news : .announcement,
                script: script,
                audioFileURL: audioURL,
                duration: estimateDuration(script: script),
                overlapStart: nil
            )
        } catch {
            print("[Producer] DJVoice failed: \(error) — skipping segment")
            return nil
        }
    }

    private func estimateDuration(script: String) -> TimeInterval {
        // Rough estimate: ~130 words/min average speaking rate
        let words = script.split(separator: " ").count
        return max(1.0, Double(words) / 130.0 * 60.0)
    }
}
