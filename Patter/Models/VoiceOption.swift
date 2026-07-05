import AVFoundation

/// Installed system (AVSpeechSynthesizer) voice, filtered to English and
/// ranked by quality. Shared by SettingsView and PreferencesWizardView so
/// the two voice pickers can't drift on filtering/sorting/display rules.
struct VoiceOption: Identifiable, Hashable {
    let id: String           // AVSpeechSynthesisVoice identifier
    let name: String
    let quality: Quality

    enum Quality: Int, Comparable {
        case compact, enhanced, premium
        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
        var label: String {
            switch self {
            case .premium:  "Premium"
            case .enhanced: "Enhanced"
            case .compact:  "Compact"
            }
        }
    }

    var displayName: String { "\(name) — \(quality.label)" }

    static func installedEnglish() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map {
                let q: Quality
                switch $0.quality {
                case .premium:  q = .premium
                case .enhanced: q = .enhanced
                default:        q = .compact
                }
                return VoiceOption(id: $0.identifier, name: $0.name, quality: q)
            }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                return lhs.name < rhs.name
            }
    }
}
