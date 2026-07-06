import Foundation

/// How much detail the DJ gives when covering a news story. The two upper
/// levels download the full article; Brief/Standard use only RSS data.
/// All per-level constants live here so Producer/DJPromptTemplate/Settings
/// can't drift on the numbers.
enum NewsVerbosity: String, Codable, CaseIterable, Identifiable, Sendable {
    case brief
    case standard
    case detailed
    case deepDive

    static let `default`: NewsVerbosity = .standard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brief:    "Brief"
        case .standard: "Standard"
        case .detailed: "Detailed"
        case .deepDive: "Deep Dive"
        }
    }

    /// Settings footer copy for the selected level.
    var settingsDescription: String {
        switch self {
        case .brief:    "A quick one-line mention of the headline."
        case .standard: "A few sentences of context from the feed summary."
        case .detailed: "Downloads the article and covers it in about a paragraph."
        case .deepDive: "Downloads the article and covers it in a few paragraphs. Segments take noticeably longer to generate."
        }
    }

    /// Whether Producer should download the article body before generation.
    var needsArticleFetch: Bool {
        self == .detailed || self == .deepDive
    }

    /// Max article-body characters fed to the on-device model (nil = no fetch).
    /// Caps keep the prompt well inside the ~4k-token Foundation Models window.
    var articleBodyCharCap: Int? {
        switch self {
        case .brief, .standard: nil
        case .detailed:         1500
        case .deepDive:         3500
        }
    }

    /// News-segment length guidance injected into the LLM instructions.
    var promptGuidance: String {
        switch self {
        case .brief:
            "Mention the news topic in at most 1–2 sentences as a quick aside. Do not go into story details even if a summary is present. Keep the whole break at 2 to 4 sentences, 30-70 words."
        case .standard:
            "aim for 4–5 sentences, 60–100 words."
        case .detailed:
            "cover the story in 6–8 sentences, 120–180 words, before bridging back to the next song."
        case .deepDive:
            "cover the story in depth: 2–3 short spoken paragraphs, 220–320 words total, before bridging back to the next song."
        }
    }

    /// Cap for DJBrain's sentence-boundary truncation of the final script.
    var scriptCharCap: Int {
        switch self {
        case .brief, .standard: 500
        case .detailed:         1200
        case .deepDive:         2200
        }
    }
}
