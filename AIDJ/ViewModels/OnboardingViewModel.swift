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
    private let musicService: any MusicKitServiceProtocol

    init(musicService: any MusicKitServiceProtocol) {
        self.musicService = musicService
    }

    func checkStatus() async {
        // Check Apple Intelligence first (device capability)
        if let reason = appleIntelligenceUnavailabilityReason() {
            status = .needsAppleIntelligence(reason: reason)
            return
        }

        // Check MusicKit authorization
        let authStatus = musicService.authorizationStatus
        if authStatus != .authorized {
            status = .needsMusicKitAuth
            return
        }

        status = .ready
    }

    func requestMusicAccess() async {
        _ = await musicService.requestAuthorization()
        await checkStatus()
    }
}
