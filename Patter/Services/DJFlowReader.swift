import Foundation

/// Deterministic "read the room" layer for the DJ. Real DJs don't announce
/// tracks cold — they read the energy of what just played and steer the room
/// toward what's next. MusicKit exposes no key/BPM for catalog tracks, so this
/// is intentionally an energy/mood heuristic built from genre family, era, and
/// length. It never claims a musical key or BPM; the spoken guidance it emits
/// is the transition spine for DJBrain, phrased in energy terms only.
struct DJFlowRead: Sendable, Codable, Equatable {
    enum Move: String, Sendable, Codable {
        case stepUp, hold, stepDown, shift
    }

    let move: Move
    /// One speakable sentence describing the transition in energy terms.
    /// Injected into the prompt as the DJ's transition spine.
    let spokenGuidance: String
}

enum DJFlowReader {
    /// Energy classes 1...5 (mellow → explosive) keyed on genre family tokens.
    /// Unknown families land at 3 ("mid") which reads as "hold the room."
    private static let energyTable: [(tokens: [String], energy: Int)] = [
        (["ambient", "new age", "meditation", "sleep", "chill"], 1),
        (["singer-songwriter", "acoustic", "folk", "country", "americana"], 2),
        (["jazz", "blues", "soul", "r&b", "neo soul", "bossa", "lounge"], 2),
        (["classical", "orchestral", "piano", "soundtrack", "film"], 2),
        (["indie", "alternative", "dream pop", "shoegaze", "trip-hop"], 3),
        (["pop", "synth-pop", "k-pop", "latin", "reggaeton", "afrobeats"], 4),
        (["hip hop", "rap", "trap", "funk", "disco", "motown"], 4),
        (["rock", "punk", "metal", "grunge"], 5),
        (["edm", "house", "techno", "trance", "drum", "dance", "electronic"], 5),
    ]

    /// Reads the flow from `previous` → `next`. Either side may be nil
    /// (first break of the session) — guidance degrades to open-room language.
    static func read(previous: Track?, next: Track) -> DJFlowRead {
        let prevEnergy = previous.map(energy(of:)) ?? 3
        let nextEnergy = energy(of: next)
        let move: DJFlowRead.Move
        switch nextEnergy - prevEnergy {
        case let d where d >= 2: move = .stepUp
        case 1:                  move = .stepUp
        case -1:                 move = .stepDown
        case let d where d <= -2: move = .stepDown
        default:                 move = prevFamily(previous) == nextFamily(next) ? .hold : .shift
        }
        return DJFlowRead(move: move, spokenGuidance: guidance(move: move, previous: previous, next: next))
    }

    static func energy(of track: Track) -> Int {
        let hay = (track.genreNames.map { $0.lowercased() }.joined(separator: " ")
            + " " + track.title.lowercased())
        var best: (tokens: [String], energy: Int)?
        for entry in energyTable where entry.tokens.contains(where: { hay.contains($0) }) {
            // First match wins in table order; deeper families are more specific.
            if best == nil { best = entry }
        }
        if let best { return best.energy }
        // No genre data: let the shape of the track read the room. Very short
        // tracks skew radio-single bright; epics skew mellow.
        if track.duration > 420 { return 2 }
        if track.duration > 0, track.duration < 150 { return 4 }
        return 3
    }

    private static func nextFamily(_ track: Track?) -> String? {
        guard let track, let first = track.genreNames.first?.lowercased() else { return nil }
        return String(first.prefix(12))
    }

    private static func prevFamily(_ track: Track?) -> String? { nextFamily(track) }

    private static func guidance(move: DJFlowRead.Move, previous: Track?, next: Track) -> String {
        let nextName = clean(next.title)
        switch move {
        case .stepUp:
            return "The room is climbing: '\(nextName)' hits harder than what came before. Lean into the lift — momentum, not a reset."
        case .hold:
            return "Staying in the same lane — '\(nextName)' keeps the room exactly where it is. Smooth handoff, no gear change."
        case .stepDown:
            return "Bringing it down a notch: '\(nextName)' lands softer than what just played. Let the room breathe out."
        case .shift:
            return "Changing color, not altitude: '\(nextName)' shifts the mood sideways while keeping the same energy in the room."
        }
    }

    private static func clean(_ title: String) -> String {
        if let parenIndex = title.firstIndex(of: "(") {
            return String(title[..<parenIndex]).trimmingCharacters(in: .whitespaces)
        }
        return title
    }
}
