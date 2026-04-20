import Foundation
import MusicKit
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

    private let musicService: any MusicKitServiceProtocol

    init(musicService: any MusicKitServiceProtocol) {
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

    /// If the user already has preferences saved from before the wizard
    /// existed (any of listener name, feed list, or DJ frequency), mark
    /// onboarding complete so they're not bounced into a setup flow they
    /// don't need.
    private func autoCompleteForExistingUsers() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.onboardingCompletedKey) { return }
        let hasName = (defaults.string(forKey: "listenerName") ?? "").isEmpty == false
        let hasFeeds = (defaults.stringArray(forKey: "rssFeedURLs") ?? []).isEmpty == false
        let hasFrequency = defaults.string(forKey: "djFrequency") != nil
        if hasName || hasFeeds || hasFrequency {
            Log.onboarding.info("Existing settings detected — auto-completing onboarding")
            defaults.set(true, forKey: Self.onboardingCompletedKey)
        }
    }

    /// Called by PreferencesWizardView when the user taps "Start Listening".
    func completePreferences() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        Log.onboarding.info("Preferences wizard complete → status = .ready")
        status = .ready
    }

    /// Debug / settings "Reset Onboarding" hook.
    static func resetOnboardingFlag() {
        UserDefaults.standard.removeObject(forKey: onboardingCompletedKey)
    }

    func requestMusicAccess() async {
        _ = await musicService.requestAuthorization()
        await checkStatus()
    }
}
