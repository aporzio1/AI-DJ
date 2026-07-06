import Foundation

/// Shared UserDefaults key registry for settings/onboarding state. Centralized
/// so `SettingsViewModel` and `OnboardingViewModel` can't silently drift on
/// the string literal for a key they both read (e.g. onboarding's
/// existing-user migration check needs the exact same keys `SettingsViewModel`
/// writes to).
enum SettingsKeys {
    static let feeds = "rssFeedURLs"
    static let djEnabled = "djEnabled"
    static let djFrequency = "djFrequency"
    static let newsEnabled = "newsEnabled"
    static let newsFrequency = "newsFrequency"
    static let newsVerbosity = "newsVerbosity"
    static let newsVerbosityDeepDiveWarned = "newsVerbosityDeepDiveWarned"  // device-local sentinel; one-shot
    static let listenerName = "listenerName"
    static let voiceIdentifier = "voiceIdentifier"
    static let ttsProvider = "ttsProvider"
    static let openAIVoice = "openAIVoice"
    static let openAIModel = "openAIModel"
    static let kokoroVoice = "kokoroVoice"
    static let legacyPersona = "djPersona"               // Phase 1 single-persona storage
    static let customPersonas = "djCustomPersonas"
    static let activePersonaID = "djActivePersonaID"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"    // device-local, NOT synced
    static let kokoroDowngradedFromIOS26 = "kokoroAutoDowngradedFromIOS26"  // device-local sentinel; one-shot
    static let openAIKeychainMigrated = "openAIKeychainMigratedToSynchronizable"  // device-local sentinel; one-shot
}
