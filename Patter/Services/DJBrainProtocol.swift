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
    /// Follow-on stories for a news-desk delivery (read after the lead, one
    /// short line each). Empty when news is off or the feed had nothing fresh.
    let secondaryHeadlines: [NewsHeadline]
    /// Energy read of previous→upcoming from `DJFlowReader`. The DJ's
    /// transition spine. nil only when flow reading was skipped.
    let flow: DJFlowRead?
    /// First words of the last few breaks, so the DJ doesn't open every break
    /// with the same greeting.
    let avoidOpenings: [String]

    init(placement: Placement, persona: DJPersona, upcomingTrack: Track,
         recentTracks: [Track], timeOfDay: TimeOfDay, currentTimeString: String,
         newsHeadline: NewsHeadline?, listenerName: String?, feedback: FeedbackSummary?,
         secondaryHeadlines: [NewsHeadline] = [],
         flow: DJFlowRead? = nil, avoidOpenings: [String] = []) {
        self.placement = placement
        self.persona = persona
        self.upcomingTrack = upcomingTrack
        self.recentTracks = recentTracks
        self.timeOfDay = timeOfDay
        self.currentTimeString = currentTimeString
        self.newsHeadline = newsHeadline
        self.listenerName = listenerName
        self.feedback = feedback
        self.secondaryHeadlines = secondaryHeadlines
        self.flow = flow
        self.avoidOpenings = avoidOpenings
    }

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
    /// Pre-pays the Foundation Models cold start (K25).
    func warmUp() async
    /// True once the brain has answered at least once this session — cold
    /// brains mean a slow first segment, which drives the play-first choice.
    func isWarmed() async -> Bool
}
