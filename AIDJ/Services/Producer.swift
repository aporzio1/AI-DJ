import Foundation

/// Subscribes to PlaybackCoordinator advance events and primes DJ segments in advance.
/// On any failure in the generation pipeline, degrades gracefully (never stops music).
actor Producer {

    struct Config: Sendable {
        var djEnabled: Bool
        var newsEnabled: Bool
        static let `default` = Config(djEnabled: true, newsEnabled: true)
    }

    private let coordinator: PlaybackCoordinator
    private let brain: any DJBrainProtocol
    private let voice: any DJVoiceProtocol
    private let rssFetcher: any RSSFetcherProtocol
    private let persona: DJPersona
    private var listenerName: String?
    private var config: Config = .default

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
        listenerName: String? = nil,
        config: Config = .default
    ) {
        self.coordinator = coordinator
        self.brain = brain
        self.voice = voice
        self.rssFetcher = rssFetcher
        self.persona = persona
        self.listenerName = listenerName
        self.config = config
    }

    // MARK: Lifecycle

    func start() {
        Log.producer.info("start() — subscribing to willAdvance events")
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await event in await coordinator.willAdvanceEvents {
                Log.producer.info("Received willAdvance for '\(event.currentTrack.title, privacy: .public)' → nextIndex=\(event.nextTrackIndex)")
                await self.handleWillAdvance(event)
            }
            Log.producer.info("willAdvance stream ended")
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func updateListenerName(_ name: String?) {
        listenerName = name
    }

    func updateConfig(_ newConfig: Config) {
        config = newConfig
    }

    /// Generate a replacement for the currently-playing DJ segment. Uses the same
    /// upcoming-track context as the original.
    func regenerateCurrentSegment() async -> DJSegment? {
        let queue = await coordinator.queue
        let currentIdx = await coordinator.currentIndex
        guard currentIdx < queue.count, case .djSegment = queue[currentIdx] else { return nil }

        // The segment introduces the next track in the queue.
        guard currentIdx + 1 < queue.count, case .track(let upcoming) = queue[currentIdx + 1] else {
            return nil
        }
        Log.producer.info("regenerating segment for '\(upcoming.title, privacy: .public)'")
        return await generateSegment(upcomingTrack: upcoming)
    }

    func primeOpeningIntro() async {
        guard config.djEnabled else {
            Log.producer.info("DJ disabled — skipping opening intro")
            return
        }
        let queue = await coordinator.queue
        guard let firstTrack = queue.first, case .track(let upcoming) = firstTrack else { return }
        Log.producer.info("Priming opening intro for '\(upcoming.title, privacy: .public)'")
        guard let segment = await generateSegment(upcomingTrack: upcoming) else { return }
        await coordinator.prependAndSelect(.djSegment(segment))
        hasGivenIntro = true
        tracksSinceLastSegment = 0
        Log.producer.info("Opening intro inserted at index 0")
    }

    /// Exposed for unit tests only.
    func handleWillAdvanceForTesting(_ event: WillAdvanceEvent) async {
        await handleWillAdvance(event)
    }

    // MARK: Private

    private func handleWillAdvance(_ event: WillAdvanceEvent) async {
        let track = event.currentTrack
        recentTracks.append(track)
        if recentTracks.count > 5 { recentTracks.removeFirst() }

        let queue = await coordinator.queue
        guard event.nextTrackIndex < queue.count else { return }
        let nextItem = queue[event.nextTrackIndex]
        guard case .track(let upcomingTrack) = nextItem else { return }

        guard let segment = await primeSegment(upcomingTrack: upcomingTrack) else { return }

        // Verify the upcoming track is still where we expect before inserting.
        // If generation took too long and the coordinator already advanced past it,
        // drop the segment rather than inserting at a stale slot.
        let refreshedQueue = await coordinator.queue
        let currentIdx = await coordinator.currentIndex
        guard refreshedQueue.indices.contains(event.nextTrackIndex),
              case .track(let stillThere) = refreshedQueue[event.nextTrackIndex],
              stillThere.id == upcomingTrack.id,
              event.nextTrackIndex > currentIdx else {
            Log.producer.info("Upcoming track moved/gone — dropping segment")
            return
        }

        await coordinator.insertAfterCurrent(.djSegment(segment))
    }

    private func shouldGenerate() -> Bool {
        guard config.djEnabled else { return false }
        if !hasGivenIntro {
            hasGivenIntro = true
            tracksSinceLastSegment = 0
            return true
        }
        if tracksSinceLastSegment >= 3 {
            tracksSinceLastSegment = 0
            return true
        }
        if Bool.random() {
            tracksSinceLastSegment = 0
            return true
        }
        tracksSinceLastSegment += 1
        return false
    }

    private func primeSegment(upcomingTrack: AIDJ.Track) async -> DJSegment? {
        guard shouldGenerate() else {
            Log.producer.debug("Skipping DJ for this transition (tracksSinceLast=\(self.tracksSinceLastSegment))")
            return nil
        }
        return await generateSegment(upcomingTrack: upcomingTrack)
    }

    private func generateSegment(upcomingTrack: AIDJ.Track) async -> DJSegment? {
        let headline: NewsHeadline? = config.newsEnabled
            ? try? await rssFetcher.fetchHeadlines().first
            : nil

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
            Log.producer.info("DJBrain script: \"\(script, privacy: .public)\"")
        } catch {
            Log.producer.error("DJBrain failed (\(error, privacy: .public)) — falling back to canned template")
            script = "Up next, \(upcomingTrack.title) by \(upcomingTrack.artist)."
        }

        do {
            let audioURL = try await voice.renderToFile(script: script, voiceIdentifier: persona.voicePreset)
            Log.producer.debug("DJVoice rendered to \(audioURL.lastPathComponent, privacy: .public)")
            return DJSegment(
                id: UUID(),
                kind: headline != nil ? .news : .announcement,
                script: script,
                audioFileURL: audioURL,
                duration: estimateDuration(script: script),
                overlapStart: nil
            )
        } catch {
            Log.producer.error("DJVoice failed: \(error, privacy: .public) — skipping segment")
            return nil
        }
    }

    private func estimateDuration(script: String) -> TimeInterval {
        let wpm = 130.0
        let words = script.split(separator: " ").count
        return max(1.0, Double(words) / wpm * 60.0)
    }
}
