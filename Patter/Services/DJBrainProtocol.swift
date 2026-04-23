import Foundation

/// Input context for DJ script generation.
struct DJContext: Sendable {
    let placement: Placement
    let persona: DJPersona
    let upcomingTrack: Track
    let recentTracks: [Track]     // last N played, oldest-first
    let timeOfDay: TimeOfDay
    let currentTimeString: String   // e.g. "2:11 PM" — real clock time in the device's locale
    let newsHeadline: NewsHeadline?
    let listenerName: String?
    let feedback: FeedbackSummary?

    enum Placement: String, Sendable {
        case opening
        case betweenSongs
    }

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

    /// Format the current wall-clock time for the DJ prompt. Locale-aware
    /// h:mm (a/p) so US English reads "2:11 PM" and 24-hour locales get
    /// "14:11" naturally.
    static func currentClockString(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: now)
    }
}

protocol DJBrainProtocol: AnyObject, Sendable {
    /// Returns a script string (≤ ~200 chars) for the DJ to speak.
    func generateScript(for context: DJContext) async throws -> String
}
