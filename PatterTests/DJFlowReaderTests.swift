import Foundation
import Testing
@testable import Patter

@Suite("DJFlowReader")
struct DJFlowReaderTests {
    private func track(_ title: String, genres: [String] = [], duration: TimeInterval = 210) -> Track {
        Track(id: UUID().uuidString, title: title, artist: "Artist", album: "Album",
              artworkURL: nil, duration: duration, providerID: .appleMusic,
              genreNames: genres, releaseYear: nil)
    }

    @Test("high-energy next track reads as a step up")
    func stepUp() {
        let flow = DJFlowReader.read(
            previous: track("Slow Fade", genres: ["Singer/Songwriter"]),
            next: track("Neon Rush", genres: ["Dance/Electronic"])
        )
        #expect(flow.move == .stepUp)
        #expect(flow.spokenGuidance.contains("Neon Rush"))
    }

    @Test("same-family neighbors hold the lane")
    func hold() {
        let flow = DJFlowReader.read(
            previous: track("Blue Notes", genres: ["Jazz"]),
            next: track("Side Eyes", genres: ["Jazz"])
        )
        #expect(flow.move == .hold)
    }

    @Test("mellow follow-up reads as a step down")
    func stepDown() {
        let flow = DJFlowReader.read(
            previous: track("Full Throttle", genres: ["Rock"]),
            next: track("Weightless", genres: ["Ambient"])
        )
        #expect(flow.move == .stepDown)
    }

    @Test("no genre data still produces speakable, key-free guidance")
    func unknownGenresNeverClaimKeys() {
        let flow = DJFlowReader.read(previous: nil, next: track("Ghost Tapes"))
        let lowered = flow.spokenGuidance.lowercased()
        #expect(!lowered.contains("bpm"))
        #expect(!lowered.contains("minor") && !lowered.contains("major"))
        #expect(lowered.contains("ghost tapes"))
    }

    @Test("energy classes are bounded 1...5")
    func energyBounds() {
        for genres in [["Classical"], ["EDM"], ["Hip-Hop/Rap"], ["Weird Unheard-Of Genre"]] {
            let e = DJFlowReader.energy(of: track("X", genres: genres))
            #expect((1...5).contains(e))
        }
    }
}
