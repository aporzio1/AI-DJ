import Foundation

/// Input context for DJ script generation.
struct DJContext: Sendable {
    let persona: DJPersona
    let upcomingTrack: Track
    let recentTracks: [Track]     // last N played, oldest-first
    let timeOfDay: TimeOfDay
    let newsHeadline: NewsHeadline?
    let listenerName: String?

    enum TimeOfDay: String, Sendable {
        case morning, afternoon, evening, lateNight

        static func current() -> TimeOfDay {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12:   return .morning
            case 12..<17:  return .afternoon
            case 17..<22:  return .evening
            default:       return .lateNight
            }
        }
    }
}

protocol DJBrainProtocol: AnyObject, Sendable {
    /// Returns a script string (≤ ~200 chars) for the DJ to speak.
    func generateScript(for context: DJContext) async throws -> String
}
