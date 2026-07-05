import Testing
import Foundation
@testable import Patter

@Suite("DJVoiceRouter")
struct DJVoiceRouterTests {

    private func makeRouter(
        system: FakeDJVoice = FakeDJVoice(),
        openAI: FakeDJVoice = FakeDJVoice(),
        kokoro: FakeKokoroDJVoice = FakeKokoroDJVoice()
    ) -> (router: DJVoiceRouter, system: FakeDJVoice, openAI: FakeDJVoice, kokoro: FakeKokoroDJVoice) {
        let router = DJVoiceRouter(system: system, openAI: openAI, kokoro: kokoro)
        return (router, system, openAI, kokoro)
    }

    // MARK: - Routing

    @Test func systemProviderRoutesToSystem() async throws {
        let fixture = makeRouter()
        fixture.router.provider = .system
        _ = try await fixture.router.renderToFile(script: "hi", voiceIdentifier: "v1")

        #expect(fixture.system.renderCallCount == 1)
        #expect(fixture.openAI.renderCallCount == 0)
        #expect(fixture.kokoro.renderCallCount == 0)
    }

    @Test func openAIProviderRoutesToOpenAI() async throws {
        let fixture = makeRouter()
        fixture.router.provider = .openAI
        _ = try await fixture.router.renderToFile(script: "hi", voiceIdentifier: "v1")

        #expect(fixture.openAI.renderCallCount == 1)
        #expect(fixture.system.renderCallCount == 0)
    }

    @Test func kokoroProviderRoutesToKokoro() async throws {
        let fixture = makeRouter()
        fixture.router.provider = .kokoro
        _ = try await fixture.router.renderToFile(script: "hi", voiceIdentifier: "v1")

        #expect(fixture.kokoro.renderCallCount == 1)
        #expect(fixture.system.renderCallCount == 0)
    }

    @Test func switchingProviderChangesRoutingForSubsequentRenders() async throws {
        let fixture = makeRouter()
        fixture.router.provider = .system
        _ = try await fixture.router.renderToFile(script: "one", voiceIdentifier: "v")

        fixture.router.provider = .openAI
        _ = try await fixture.router.renderToFile(script: "two", voiceIdentifier: "v")

        #expect(fixture.system.renderCallCount == 1)
        #expect(fixture.openAI.renderCallCount == 1)
    }

    // MARK: - Fallback

    @Test func openAIFailureFallsBackToSystemWithEmptyVoiceID() async throws {
        let openAI = FakeDJVoice()
        openAI.shouldThrow = true
        let fixture = makeRouter(openAI: openAI)
        fixture.router.provider = .openAI

        let url = try await fixture.router.renderToFile(script: "hi", voiceIdentifier: "custom-voice")

        #expect(url == fixture.system.fakeURL)
        #expect(fixture.system.renderCallCount == 1)
        // The OpenAI voice identifier isn't a valid AVSpeech ID — fallback
        // must pass "" so SystemDJVoice picks its own default.
        #expect(fixture.system.lastVoiceIdentifier == "")
    }

    @Test func kokoroFailureFallsBackToSystem() async throws {
        let kokoro = FakeKokoroDJVoice()
        kokoro.shouldThrow = true
        let fixture = makeRouter(kokoro: kokoro)
        fixture.router.provider = .kokoro

        let url = try await fixture.router.renderToFile(script: "hi", voiceIdentifier: "custom-voice")

        #expect(url == fixture.system.fakeURL)
        #expect(fixture.system.renderCallCount == 1)
        #expect(fixture.system.lastVoiceIdentifier == "")
    }

    @Test func systemFailurePropagatesWithoutFallback() async throws {
        let system = FakeDJVoice()
        system.shouldThrow = true
        let fixture = makeRouter(system: system)
        fixture.router.provider = .system

        await #expect(throws: FakeError.self) {
            _ = try await fixture.router.renderToFile(script: "hi", voiceIdentifier: "v")
        }
    }

    // MARK: - Kokoro model management proxy

    @Test func prepareKokoroModelDelegatesToInjectedKokoro() async throws {
        let fixture = makeRouter()
        try await fixture.router.prepareKokoroModel()
        #expect(fixture.kokoro.prepareModelCallCount == 1)
    }

    @Test func removeKokoroModelDelegatesToInjectedKokoro() async throws {
        let fixture = makeRouter()
        try await fixture.router.removeKokoroModel()
        #expect(fixture.kokoro.removeModelCallCount == 1)
    }

    // MARK: - setOpenAIModel

    @Test func setOpenAIModelIsNoOpForNonOpenAIProvider() {
        // The router's designated init accepts `any DJVoiceProtocol` for
        // openAI — with a fake injected, the concrete-type downcast in
        // setOpenAIModel finds nothing and it's a safe no-op.
        let fixture = makeRouter()
        fixture.router.setOpenAIModel(.tts_1_hd)
    }

    // MARK: - warmUpSystemVoice proxy (K35)

    @Test func warmUpSystemVoiceDelegatesToInjectedSystemProvider() async {
        let fixture = makeRouter()
        await fixture.router.warmUpSystemVoice(voiceIdentifier: "v1")
        // FakeDJVoice has no dedicated warmUp override, so this exercises the
        // DJVoiceProtocol extension's no-op default — just confirms the
        // proxy call compiles and completes without touching render state.
        #expect(fixture.system.renderCallCount == 0)
    }
}
