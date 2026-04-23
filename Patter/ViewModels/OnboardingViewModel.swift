import Foundation
@preconcurrency import FoundationModels

@Observable
@MainActor
final class OnboardingViewModel {

    enum Status {
        case checking
        case ready
        case preferences       // gates + checks passed, user hasn't finished the first-launch wizard yet
        case needsMusicKitAuth
        case needsAppleIntelligence(reason: String)
    }

    private(set) var status: Status = .checking

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    static let onboardingCompletedKey = "onboardingCompleted"
    static let autoCompleteMigrationRanKey = "onboardingAutoCompleteMigrationRan"

    private let musicService: any MusicProviderService

    init(musicService: any MusicProviderService) {
        self.musicService = musicService
    }

    func checkStatus() async {
        Log.onboarding.info("checkStatus called")

        if let reason = appleIntelligenceUnavailabilityReason() {
            Log.onboarding.error("Apple Intelligence unavailable: \(reason, privacy: .public)")
            status = .needsAppleIntelligence(reason: reason)
            return
        }

        let authStatus = musicService.authorizationStatus
        Log.onboarding.info("MusicKit auth status: \(String(describing: authStatus), privacy: .public)")
        if authStatus != .authorized {
            status = .needsMusicKitAuth
            return
        }

        // Gates passed. Show the preferences wizard on first launch only.
        // Existing users who already have settings saved (from before the
        // wizard existed) are auto-graduated — see autoCompleteForExistingUsers.
        autoCompleteForExistingUsers()
        if UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) {
            Log.onboarding.info("Preferences wizard already complete → status = .ready")
            status = .ready
        } else {
            Log.onboarding.info("Gates passed → status = .preferences")
            status = .preferences
        }
    }

    /// One-shot migration: the VERY FIRST launch after the wizard ships,
    /// if the user already has preferences saved (any of listener name,
    /// feed list, or DJ frequency), mark onboarding complete so they're
    /// not bounced into a setup flow they don't need. Guarded by a
    /// separate sentinel (`autoCompleteMigrationRan`) so subsequent
    /// manual "Reset Onboarding" actions actually work — without this
    /// guard, the migration would re-flip the flag on every launch and
    /// silently defeat the reset.
    private func autoCompleteForExistingUsers() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.autoCompleteMigrationRanKey) { return }
        defaults.set(true, forKey: Self.autoCompleteMigrationRanKey)
        if defaults.bool(forKey: Self.onboardingCompletedKey) { return }
        let hasName = (defaults.string(forKey: "listenerName") ?? "").isEmpty == false
        let hasFeeds = (defaults.stringArray(forKey: "rssFeedURLs") ?? []).isEmpty == false
        let hasFrequency = defaults.string(forKey: "djFrequency") != nil
        if hasName || hasFeeds || hasFrequency {
            Log.onboarding.info("Existing settings detected — auto-completing onboarding (one-shot migration)")
            defaults.set(true, forKey: Self.onboardingCompletedKey)
        }
    }

    /// Called by PreferencesWizardView when the user taps "Start Listening".
    func completePreferences() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        Log.onboarding.info("Preferences wizard complete → status = .ready")
        status = .ready
    }

    /// Debug / settings "Reset Onboarding" hook. Clears the completed
    /// flag AND SETS the migration sentinel, because otherwise the
    /// auto-complete migration would see the user's existing settings
    /// on next launch and silently re-set `onboardingCompleted = true`,
    /// skipping the wizard the user just asked to see again.
    static func resetOnboardingFlag() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: onboardingCompletedKey)
        defaults.set(true, forKey: autoCompleteMigrationRanKey)
    }

    func requestMusicAccess() async {
        _ = await musicService.requestAuthorization()
        await checkStatus()
    }
}
