import SwiftUI

struct OnboardingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: OnboardingViewModel
    @Bindable var settings: SettingsViewModel
    let onReady: () -> Void

    init(vm: OnboardingViewModel, settings: SettingsViewModel, onReady: @escaping () -> Void) {
        self._vm = State(initialValue: vm)
        self.settings = settings
        self.onReady = onReady
    }

    var body: some View {
        Group {
            switch vm.status {
            case .checking:
                ProgressView("Checking requirements…")
            case .ready:
                ProgressView("Starting…")
            case .preferences:
                PreferencesWizardView(settings: settings) {
                    vm.completePreferences()
                }
            case .needsMusicKitAuth:
                blockedView(
                    icon: "music.note",
                    title: "Apple Music Access Required",
                    message: "Patter needs access to your Apple Music library to play music.",
                    actionTitle: "Grant Access"
                ) {
                    Task { await vm.requestMusicAccess() }
                }
            case .musicKitAuthDenied:
                blockedView(
                    icon: "music.note",
                    title: "Apple Music Access Required",
                    message: "Apple Music access is currently turned off. Open Settings → Privacy & Security → Media & Apple Music → Patter, then return here.",
                    actionTitle: "Open Settings"
                ) {
                    openAppSettings()
                }
            case .needsAppleIntelligence(let reason):
                blockedView(
                    icon: "brain",
                    title: "Apple Intelligence Required",
                    message: reason,
                    actionTitle: "Open Settings"
                ) {
                    openAppSettings()
                }
            }
        }
        .task { await vm.checkStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await vm.checkStatus() }
        }
        .onChange(of: vm.isReady) { _, ready in
            if ready {
                Log.onboarding.info("isReady fired → calling onReady()")
                onReady()
            }
        }
    }

    private func openAppSettings() {
#if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
#endif
    }

    private func blockedView(icon: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
