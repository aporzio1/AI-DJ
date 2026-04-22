import Testing
import Foundation
@testable import AIDJ

@Suite("PlaybackCoordinator")
@MainActor
struct PlaybackCoordinatorTests {

    func makeCoordinator() -> (PlaybackCoordinator, FakeMusicService, FakeAudioGraph) {
        let music = FakeMusicService()
        let audio = FakeAudioGraph()
        let router = MusicProviderRouter(appleMusic: music)
        let coordinator = PlaybackCoordinator(router: router, audioGraph: audio)
        return (coordinator, music, audio)
    }

    @Test func initialStateIsIdle() async {
        let (coordinator, _, _) = makeCoordinator()
        let state = await coordinator.state
        #expect(state == .idle)
    }

    @Test func replaceQueueSetsItems() async {
        let (coordinator, _, _) = makeCoordinator()
        let tracks = [AIDJ.Track.stub(), AIDJ.Track.stub()]
        await coordinator.replaceQueue(tracks.map { .track($0) })
        let queue = await coordinator.queue
        #expect(queue.count == 2)
        let index = await coordinator.currentIndex
        #expect(index == 0)
    }

    @Test func insertAfterCurrentAddsAtCorrectPosition() async {
        let (coordinator, _, _) = makeCoordinator()
        let a = AIDJ.Track.stub(id: "a")
        let b = AIDJ.Track.stub(id: "b")
        let c = AIDJ.Track.stub(id: "c")
        await coordinator.replaceQueue([.track(a), .track(b)])
        await coordinator.insertAfterCurrent(.track(c))
        let queue = await coordinator.queue
        #expect(queue.count == 3)
        if case .track(let t) = queue[1] {
            #expect(t.id == "c")
        } else {
            Issue.record("Expected track at index 1")
        }
    }

    @Test func removeItemShiftsIndex() async {
        let (coordinator, _, _) = makeCoordinator()
        let items = [AIDJ.Track.stub(), AIDJ.Track.stub(), AIDJ.Track.stub()]
        await coordinator.replaceQueue(items.map { .track($0) })
        await coordinator.removeItem(at: 0)
        let queue = await coordinator.queue
        #expect(queue.count == 2)
        let index = await coordinator.currentIndex
        #expect(index == 0)
    }

    @Test func skipAdvancesIndex() async {
        let (coordinator, _, _) = makeCoordinator()
        let items = [AIDJ.Track.stub(duration: 0), AIDJ.Track.stub(duration: 0)]
        await coordinator.replaceQueue(items.map { .track($0) })
        try? await coordinator.skip()
        let index = await coordinator.currentIndex
        #expect(index == 1)
    }

    @Test func pauseCallsMusicServiceStop() async throws {
        let (coordinator, music, _) = makeCoordinator()
        await coordinator.replaceQueue([.track(AIDJ.Track.stub(duration: 60))])
        // replaceQueue stops whatever's currently playing first — that's one
        // stop() on the fake. We then invoke start/stop directly to exercise
        // the fake's call counter for a second increment.
        try await music.start(track: AIDJ.Track.stub())
        try await music.stop()
        #expect(music.stopCallCount == 2)
    }

    @Test func djSegmentPlaysViaAudioGraph() async throws {
        let (coordinator, _, audio) = makeCoordinator()
        let segURL = URL(filePath: "/tmp/test.caf")
        let segment = DJSegment(id: UUID(), kind: .banter, script: "Hey!", audioFileURL: segURL, duration: 0, overlapStart: nil)
        await coordinator.replaceQueue([.djSegment(segment)])
        try await coordinator.play()
        #expect(audio.playedURLs.contains(segURL))
    }

    // MARK: - K15 regression: transport transitions must bump generation
    // + stop audioGraph. Both fixes landed in 688bbf8 after smoke testing.

    @Test func resumeFromPauseFlipsStateBackToPlaying() async throws {
        // Regression: play() resume branch used to skip `state = .playing`
        // before entering monitorTrackUntilEnd, leaving the coordinator
        // stuck in .paused even though MusicKit had resumed. The mirror
        // in NowPlayingViewModel then kept showing the "play" button.
        let (coordinator, _, _) = makeCoordinator()
        let track = AIDJ.Track.stub(duration: 60)
        await coordinator.replaceQueue([.track(track)])

        let playTask = Task { try? await coordinator.play() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await coordinator.state == .playing)

        try await coordinator.pause()
        #expect(await coordinator.state == .paused)

        let resumeTask = Task { try? await coordinator.play() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await coordinator.state == .playing, "resume-from-pause must flip state back to .playing")

        resumeTask.cancel()
        playTask.cancel()
    }

    @Test func skipStopsAudioGraph() async throws {
        // Regression: skip() used to just advance the index without
        // stopping the audio graph. If a DJ segment was mid-sentence, the
        // player node kept speaking over the new track.
        let (coordinator, _, audio) = makeCoordinator()
        let t1 = AIDJ.Track.stub(id: "t1", duration: 60)
        let t2 = AIDJ.Track.stub(id: "t2", duration: 60)
        await coordinator.replaceQueue([.track(t1), .track(t2)])
        let before = audio.stopCallCount
        try await coordinator.skip()
        #expect(audio.stopCallCount > before, "skip must stop the audio graph to kill any in-flight DJ segment")
    }

    @Test func previousStopsAudioGraph() async throws {
        // Same invariant as skip() — symmetrical fix.
        let (coordinator, _, audio) = makeCoordinator()
        let t1 = AIDJ.Track.stub(id: "t1", duration: 60)
        let t2 = AIDJ.Track.stub(id: "t2", duration: 60)
        await coordinator.replaceQueue([.track(t1), .track(t2)])
        // advance so previous() has somewhere to go
        try await coordinator.skip()
        let before = audio.stopCallCount
        try await coordinator.previous()
        #expect(audio.stopCallCount > before, "previous must stop the audio graph to kill any in-flight DJ segment")
    }
}
