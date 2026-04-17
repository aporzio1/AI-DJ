import Foundation

/// Subscribes to PlaybackCoordinator advance events and primes DJ segments in advance.
/// On any failure in the generation pipeline, degrades gracefully (never stops music).
actor Producer {

    private let coordinator: PlaybackCoordinator
    private let brain: any DJBrainProtocol
    private let voice: any DJVoiceProtocol
    private let rssFetcher: any RSSFetcherProtocol
    private let persona: DJPersona

    private var recentTracks: [AIDJ.Track] = []
    private var monitorTask: Task<Void, Never>?

    init(
        coordinator: PlaybackCoordinator,
        brain: any DJBrainProtocol,
        voice: any DJVoiceProtocol,
        rssFetcher: any RSSFetcherProtocol,
        persona: DJPersona = .default
    ) {
        self.coordinator = coordinator
        self.brain = brain
        self.voice = voice
        self.rssFetcher = rssFetcher
        self.persona = persona
    }

    // MARK: Lifecycle

    func start() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await event in await coordinator.willAdvanceEvents {
                await self.handleWillAdvance(event)
            }
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

    private func primeSegment(upcomingTrack: AIDJ.Track) async -> DJSegment? {
        let headline = try? await rssFetcher.fetchHeadlines().first

        let context = DJContext(
            persona: persona,
            upcomingTrack: upcomingTrack,
            recentTracks: recentTracks,
            timeOfDay: .current(),
            newsHeadline: headline
        )

        let script: String
        do {
            script = try await brain.generateScript(for: context)
        } catch {
            // DJBrain failed — fall back to canned template
            script = "Up next, \(upcomingTrack.title) by \(upcomingTrack.artist)."
        }

        guard let audioURL = try? await voice.renderToFile(script: script, voiceIdentifier: persona.voicePreset) else {
            // DJVoice failed — skip segment entirely
            return nil
        }

        return DJSegment(
            id: UUID(),
            kind: headline != nil ? .news : .announcement,
            script: script,
            audioFileURL: audioURL,
            duration: estimateDuration(script: script),
            overlapStart: nil
        )
    }

    private func estimateDuration(script: String) -> TimeInterval {
        // Rough estimate: ~130 words/min average speaking rate
        let words = script.split(separator: " ").count
        return max(1.0, Double(words) / 130.0 * 60.0)
    }
}
