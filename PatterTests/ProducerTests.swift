import Testing
import Foundation
@testable import Patter

@Suite("Producer")
@MainActor
struct ProducerTests {

    func makeStack() -> (Producer, PlaybackCoordinator, FakeDJBrain, FakeDJVoice, FakeRSSFetcher) {
        let music = FakeMusicService()
        let audio = FakeAudioGraph()
        let router = MusicProviderRouter(appleMusic: music)
        let coordinator = PlaybackCoordinator(router: router, audioGraph: audio)
        let brain = FakeDJBrain()
        let voice = FakeDJVoice()
        let rss = FakeRSSFetcher()
        let producer = Producer(coordinator: coordinator, brain: brain, voice: voice, rssFetcher: rss)
        return (producer, coordinator, brain, voice, rss)
    }

    @Test func primeSegmentInsertsAfterCurrentTrack() async {
        let (producer, coordinator, brain, _, _) = makeStack()
        let t1 = Patter.Track.stub(id: "t1", duration: 0.1)
        let t2 = Patter.Track.stub(id: "t2")
        await coordinator.replaceQueue([.track(t1), .track(t2)])
        await producer.start()

        // Simulate willAdvance from coordinator
        // Allow a moment for the async handler to fire
        let event = WillAdvanceEvent(currentTrack: t1, nextTrackIndex: 1)
        await producer.handleWillAdvanceForTesting(event)

        let queue = await coordinator.queue
        // A segment should now be inserted between t1 and t2
        #expect(queue.count == 3)
        if case .djSegment(_) = queue[1] {
            // OK
        } else {
            Issue.record("Expected djSegment at index 1, got \(queue[1])")
        }
        #expect(brain.generateCallCount == 1)
    }

    @Test func brainFailureFallsBackToCannedScript() async {
        let (producer, coordinator, brain, voice, _) = makeStack()
        brain.shouldThrow = true
        let t1 = Patter.Track.stub(id: "t1")
        let t2 = Patter.Track.stub(id: "t2", title: "My Song")
        await coordinator.replaceQueue([.track(t1), .track(t2)])

        let event = WillAdvanceEvent(currentTrack: t1, nextTrackIndex: 1)
        await producer.handleWillAdvanceForTesting(event)

        // Voice should be called even after brain failure (with canned script)
        #expect(voice.renderCallCount == 1)
        // Canned script contains track title
        let lastScript = voice.lastScript
        #expect(lastScript?.contains("My Song") == true)
    }

    @Test func voiceFailureSkipsSegmentEntirely() async {
        let (producer, coordinator, _, voice, _) = makeStack()
        voice.shouldThrow = true
        let t1 = Patter.Track.stub(id: "t1")
        let t2 = Patter.Track.stub(id: "t2")
        await coordinator.replaceQueue([.track(t1), .track(t2)])

        let event = WillAdvanceEvent(currentTrack: t1, nextTrackIndex: 1)
        await producer.handleWillAdvanceForTesting(event)

        let queue = await coordinator.queue
        // No segment inserted — queue stays at 2
        #expect(queue.count == 2)
    }

    @Test func noSegmentPrimedForNonTrackNextItem() async {
        let (producer, coordinator, brain, _, _) = makeStack()
        let t1 = Patter.Track.stub(id: "t1")
        let seg = DJSegment.stub()
        await coordinator.replaceQueue([.track(t1), .djSegment(seg)])

        let event = WillAdvanceEvent(currentTrack: t1, nextTrackIndex: 1)
        await producer.handleWillAdvanceForTesting(event)

        // Brain should NOT be called — next item is already a segment
        #expect(brain.generateCallCount == 0)
        let queue = await coordinator.queue
        #expect(queue.count == 2)
    }
}
