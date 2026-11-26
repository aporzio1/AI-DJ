import Foundation
import AVFoundation

/// Subscribes to PlaybackCoordinator advance events and primes DJ segments in advance.
/// On any failure in the generation pipeline, degrades gracefully (never stops music).
actor Producer {

    struct Config: Sendable {
        var djEnabled: Bool
        var newsEnabled: Bool
        var djFrequency: DJFrequency = .default
        var newsFrequency: NewsFrequency = .default
        /// Seconds of the upcoming track that start under the tail of the DJ's
        /// voice (talk-over handoff) so breaks don't end in dead air. 0 disables.
        var talkOverTail: TimeInterval = 1.8
        static let `default` = Config(
            djEnabled: true,
            newsEnabled: true,
            djFrequency: .default,
            newsFrequency: .default
        )
    }

    private let coordinator: PlaybackCoordinator
    private let brain: any DJBrainProtocol
    private let voice: any DJVoiceProtocol
    private let rssFetcher: any RSSFetcherProtocol
    private let feedbackStore: TrackFeedbackStore?
    private var persona: DJPersona
    private var listenerName: String?
    private var config: Config = .default
    private var voiceOverride: String?

    private var recentTracks: [Patter.Track] = []
    /// First words of the last few breaks — keeps the DJ from opening every
    /// break with the same greeting.
    private var recentOpenings: [String] = []
    private static let openingMemoryCount = 3
    private var monitorTask: Task<Void, Never>?
    private var tracksSinceLastSegment = 0
    private var hasGivenIntro = false

    /// Rolling list of headline URLs we've handed to the DJ recently, so we
    /// don't inject the same headline repeatedly. Oldest-first; capped at
    /// `Self.recentHeadlineCap`. Persisted to UserDefaults so the dedup
    /// survives across app launches — prior in-memory-only behavior reset
    /// on every cold start and the DJ kept narrating yesterday's top story.
    /// Device-local by design (D9): recently-heard state is inherently
    /// per-device, and syncing would add a conflict surface for zero UX gain.
    private var recentHeadlineURLs: [String] = []

    private static let recentHeadlineCap = 200
    private static let recentHeadlineDefaultsKey = "producer.recentHeadlineURLs.v1"

    init(
        coordinator: PlaybackCoordinator,
        brain: any DJBrainProtocol,
        voice: any DJVoiceProtocol,
        rssFetcher: any RSSFetcherProtocol,
        feedbackStore: TrackFeedbackStore? = nil,
        persona: DJPersona = .default,
        listenerName: String? = nil,
        config: Config = .default
    ) {
        self.coordinator = coordinator
        self.brain = brain
        self.voice = voice
        self.rssFetcher = rssFetcher
        self.feedbackStore = feedbackStore
        self.persona = persona
        self.listenerName = listenerName
        self.config = config
        self.recentHeadlineURLs = Self.loadRecentHeadlineURLs()
    }

    private static func loadRecentHeadlineURLs() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentHeadlineDefaultsKey) ?? []
    }

    private static func persistRecentHeadlineURLs(_ urls: [String]) {
        UserDefaults.standard.set(urls, forKey: recentHeadlineDefaultsKey)
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

    func updateVoice(_ identifier: String?) {
        voiceOverride = identifier
    }

    /// Hot-swap the persona. Applied on the next willAdvance — the currently
    /// playing or queued segment keeps the persona it was generated with.
    func updatePersona(_ newPersona: DJPersona) {
        persona = newPersona
    }

    private var currentVoiceIdentifier: String {
        if let v = voiceOverride { return v }
        return persona.voicePreset
    }

    /// Fetch the news desk for the next segment: a lead headline plus one
    /// follow-on story, or nil if news is disabled, the frequency roll fails,
    /// or the feed surfaces nothing usable. Errors are logged explicitly so a
    /// silent DNS/404/parser failure doesn't masquerade as "no news today."
    private func fetchNewsDeskIfEnabled() async -> (lead: NewsHeadline, secondary: [NewsHeadline])? {
        guard config.newsEnabled else { return nil }
        let frequency = config.newsFrequency
        guard Double.random(in: 0..<1) < frequency.probability else {
            Log.producer.debug("News frequency roll skipped this segment (\(String(describing: frequency), privacy: .public))")
            return nil
        }
        do {
            let headlines = try await rssFetcher.fetchHeadlines()
            guard !headlines.isEmpty else {
                Log.producer.info("News enabled but fetcher returned 0 headlines — check feed URLs")
                return nil
            }
            // Prefer unused stories; if the whole feed has been read recently,
            // fall back to the newest. Lead + one secondary keeps the break a
            // news desk rather than a bullet list.
            let recentSet = Set(recentHeadlineURLs)
            let fresh = headlines.filter { !recentSet.contains($0.url.absoluteString) }
            let pool = fresh.isEmpty ? headlines : fresh
            guard let lead = pool.first else { return nil }
            let secondary = Array(pool.dropFirst().prefix(1))
            for item in [lead] + secondary { recordRecentHeadline(item) }
            Log.producer.info("News desk ready: lead=\"\(lead.title, privacy: .public)\" (\(lead.source, privacy: .public)), secondary=\(secondary.count)")
            return (lead, secondary)
        } catch {
            Log.producer.error("News fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func recordRecentHeadline(_ headline: NewsHeadline) {
        let key = headline.url.absoluteString
        recentHeadlineURLs.removeAll { $0 == key }
        recentHeadlineURLs.append(key)
        if recentHeadlineURLs.count > Self.recentHeadlineCap {
            recentHeadlineURLs.removeFirst(recentHeadlineURLs.count - Self.recentHeadlineCap)
        }
        Self.persistRecentHeadlineURLs(recentHeadlineURLs)
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
        return await generateSegment(upcomingTrack: upcoming, placement: .betweenSongs)
    }

    func primeOpeningIntro() async {
        guard config.djEnabled else {
            Log.producer.info("DJ disabled — skipping opening intro")
            return
        }
        let queue = await coordinator.queue
        guard let firstTrack = queue.first, case .track(let upcoming) = firstTrack else { return }
        Log.producer.info("Priming opening intro for '\(upcoming.title, privacy: .public)'")
        guard let segment = await generateSegment(upcomingTrack: upcoming, placement: .opening) else { return }
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

        // Look ahead from event.nextTrackIndex until we find a playable track.
        // Drop any unplayable tracks from the queue as we go so the coordinator
        // doesn't try to play them later. Cap lookahead at 10 to avoid stalls.
        guard let upcomingTrack = await findNextPlayableTrack(from: event.nextTrackIndex) else {
            Log.producer.info("No playable track ahead — skipping intro")
            return
        }

        guard let segment = await primeSegment(upcomingTrack: upcomingTrack) else { return }

        // Verify the upcoming track is still at the slot after current before inserting.
        // If the coordinator advanced past it during generation, drop the segment.
        // Read both fields in a single actor turn — separate awaits could race
        // against an `advance()` and leave currentIdx one step ahead of the queue.
        let snapshot = await coordinator.queueSnapshot()
        let expectedIdx = snapshot.currentIndex + 1
        guard snapshot.queue.indices.contains(expectedIdx),
              case .track(let stillThere) = snapshot.queue[expectedIdx],
              stillThere.id == upcomingTrack.id else {
            Log.producer.info("Upcoming track moved/gone — dropping segment")
            return
        }

        await coordinator.insertAfterCurrent(.djSegment(segment))
    }

    /// Scans the queue at `startIndex`, removing unplayable tracks one at a time,
    /// and returns the first playable track found. `startIndex` is fixed across
    /// iterations on purpose — `coordinator.removeItem(at: startIndex)` slides
    /// the next item into that slot, so re-reading `queue[startIndex]` walks
    /// forward naturally. Bails after 10 consecutive unplayable tracks.
    private func findNextPlayableTrack(from startIndex: Int) async -> Patter.Track? {
        let maxLookahead = 10
        var attempts = 0
        while attempts < maxLookahead {
            let queue = await coordinator.queue
            guard startIndex < queue.count else { return nil }
            let item = queue[startIndex]
            guard case .track(let candidate) = item else {
                // Not a track (shouldn't happen here but be defensive)
                return nil
            }
            // Check coordinator's musicService via the existing hook
            if await coordinatorIsTrackPlayable(candidate) {
                return candidate
            }
            Log.producer.info("Track '\(candidate.title, privacy: .public)' is unplayable — removing from queue")
            await coordinator.removeItem(at: startIndex)
            attempts += 1
        }
        return nil
    }

    private func coordinatorIsTrackPlayable(_ track: Patter.Track) async -> Bool {
        await coordinator.isPlayable(track)
    }

    private func shouldGenerate() -> Bool {
        guard config.djEnabled else { return false }
        if !hasGivenIntro {
            hasGivenIntro = true
            tracksSinceLastSegment = 0
            return true
        }
        let frequency = config.djFrequency
        if tracksSinceLastSegment >= frequency.maxGap {
            tracksSinceLastSegment = 0
            return true
        }
        if frequency.randomChance > 0, Double.random(in: 0..<1) < frequency.randomChance {
            tracksSinceLastSegment = 0
            return true
        }
        tracksSinceLastSegment += 1
        return false
    }

    private func primeSegment(upcomingTrack: Patter.Track) async -> DJSegment? {
        guard shouldGenerate() else {
            Log.producer.debug("Skipping DJ for this transition (tracksSinceLast=\(self.tracksSinceLastSegment))")
            return nil
        }
        return await generateSegment(upcomingTrack: upcomingTrack, placement: .betweenSongs)
    }

    private func generateSegment(upcomingTrack: Patter.Track, placement: DJContext.Placement) async -> DJSegment? {
        let newsDesk = await fetchNewsDeskIfEnabled()
        let headline = newsDesk?.lead
        let secondaryHeadlines = newsDesk?.secondary ?? []

        let feedbackSummary: FeedbackSummary?
        if let store = feedbackStore {
            let s = await store.summary()
            feedbackSummary = s.isEmpty ? nil : s
        } else {
            feedbackSummary = nil
        }

        let flow = DJFlowReader.read(previous: recentTracks.last, next: upcomingTrack)
        let context = DJContext(
            placement: placement,
            persona: persona,
            upcomingTrack: upcomingTrack,
            recentTracks: recentTracks,
            timeOfDay: .current(),
            currentTimeString: DJContext.currentClockString(),
            newsHeadline: headline,
            listenerName: listenerName,
            feedback: feedbackSummary,
            secondaryHeadlines: secondaryHeadlines,
            flow: flow,
            avoidOpenings: recentOpenings
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
            let audioURL = try await voice.renderToFile(script: script, voiceIdentifier: currentVoiceIdentifier)
            Log.voice.debug("DJVoice rendered to \(audioURL.lastPathComponent, privacy: .public)")
            recordOpening(of: script)
            return DJSegment(
                id: UUID(),
                kind: headline != nil ? .news : .announcement,
                script: script,
                audioFileURL: audioURL,
                duration: estimateDuration(script: script),
                overlapStart: talkOverSeconds(renderedURL: audioURL),
                sourceHeadline: headline
            )
        } catch {
            Log.producer.error("DJVoice failed: \(error.localizedDescription, privacy: .public) — skipping segment")
            return nil
        }
    }

    /// Seconds of next track allowed under the voice tail. Requires the real
    /// rendered length (estimate is wpm math, not audio): a talk-over needs at
    /// least ~4s of clean voice before the music can come up under it.
    private func talkOverSeconds(renderedURL: URL) -> TimeInterval? {
        let tail = config.talkOverTail
        guard tail > 0 else { return nil }
        guard let file = try? AVAudioFile(forReading: renderedURL),
              file.processingFormat.sampleRate > 0 else { return nil }
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        guard seconds >= 4 else { return nil }
        return min(tail, seconds * 0.4)
    }

    /// Remember how this break opened so the next one can't open the same way.
    private func recordOpening(of script: String) {
        let words = script.split(whereSeparator: \.isWhitespace).prefix(3).joined(separator: " ")
        guard !words.isEmpty else { return }
        recentOpenings.append(String(words))
        if recentOpenings.count > Self.openingMemoryCount { recentOpenings.removeFirst() }
    }

    private func estimateDuration(script: String) -> TimeInterval {
        let wpm = 130.0
        let words = script.split(separator: " ").count
        return max(1.0, Double(words) / wpm * 60.0)
    }
}
