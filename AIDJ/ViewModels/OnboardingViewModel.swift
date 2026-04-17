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
        print("[Onboarding] checkStatus called")

        if let reason = appleIntelligenceUnavailabilityReason() {
            print("[Onboarding] Apple Intelligence unavailable: \(reason)")
            status = .needsAppleIntelligence(reason: reason)
            return
        }

        let authStatus = musicService.authorizationStatus
        print("[Onboarding] MusicKit auth status: \(authStatus)")
        if authStatus != .authorized {
            status = .needsMusicKitAuth
            return
        }

        print("[Onboarding] All clear → status = .ready")
        status = .ready
    }

    func requestMusicAccess() async {
        _ = await musicService.requestAuthorization()
        await checkStatus()
    }
}
