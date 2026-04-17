import Foundation
import MusicKit
@preconcurrency import FoundationModels

@Observable
@MainActor
final class OnboardingViewModel {

    enum Status {
        case checking
        case ready
        case needsMusicKitAuth
        case needsAppleIntelligence(reason: String)
    }

    private(set) var status: Status = .checking

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }
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

        Log.onboarding.info("All clear → status = .ready")
        status = .ready
    }

    func requestMusicAccess() async {
        _ = await musicService.requestAuthorization()
        await checkStatus()
    }
}
