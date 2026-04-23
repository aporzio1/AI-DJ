import Testing
import Foundation
@testable import Patter

@Suite("Models")
struct ModelsTests {

    @Test func trackCodableRoundTrip() throws {
        let track = Track(
            id: "abc123",
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            artworkURL: URL(string: "https://example.com/art.jpg"),
            duration: 354.0,
            providerID: .appleMusic
        )
        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded == track)
    }

    @Test func djSegmentCodableRoundTrip() throws {
        let segment = DJSegment(
            id: UUID(),
            kind: .banter,
            script: "Up next, something absolutely fire.",
            audioFileURL: URL(filePath: "/tmp/test.caf"),
            duration: 4.2,
            overlapStart: nil
        )
        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(DJSegment.self, from: data)
        #expect(decoded.id == segment.id)
        #expect(decoded.kind == segment.kind)
        #expect(decoded.script == segment.script)
        #expect(decoded.overlapStart == nil)
    }

    @Test func djPersonaCodableRoundTrip() throws {
        let persona = DJPersona.default
        let data = try JSONEncoder().encode(persona)
        let decoded = try JSONDecoder().decode(DJPersona.self, from: data)
        #expect(decoded.id == persona.id)
        #expect(decoded.name == persona.name)
        #expect(decoded.styleDescriptor == persona.styleDescriptor)
    }

    @Test func newsHeadlineCodableRoundTrip() throws {
        let headline = NewsHeadline(
            id: UUID(),
            title: "Breaking: Swift 7 announced",
            source: "Swift.org",
            url: URL(string: "https://swift.org/blog")!,
            publishedAt: Date(timeIntervalSince1970: 1_000_000),
            summary: "Apple announces Swift 7 with even more macros."
        )
        let data = try JSONEncoder().encode(headline)
        let decoded = try JSONDecoder().decode(NewsHeadline.self, from: data)
        #expect(decoded.id == headline.id)
        #expect(decoded.title == headline.title)
        #expect(decoded.url == headline.url)
    }

    @Test func playableItemTrackIdentity() {
        let track = Track(
            id: "xyz",
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkURL: nil,
            duration: 180,
            providerID: .appleMusic
        )
        let item = PlayableItem.track(track)
        #expect(item.id == "track-appleMusic-xyz")
    }

    @Test func playableItemSegmentIdentity() {
        let segmentID = UUID()
        let segment = DJSegment(
            id: segmentID,
            kind: .announcement,
            script: "Hello",
            audioFileURL: URL(filePath: "/tmp/hello.caf"),
            duration: 2.0,
            overlapStart: nil
        )
        let item = PlayableItem.djSegment(segment)
        #expect(item.id == "segment-\(segmentID)")
    }
}
