import SwiftUI

struct OnboardingView: View {
    @State private var vm: OnboardingViewModel
    let onReady: () -> Void

    init(vm: OnboardingViewModel, onReady: @escaping () -> Void) {
        self._vm = State(initialValue: vm)
        self.onReady = onReady
    }

    var body: some View {
        Group {
            switch vm.status {
            case .checking:
                ProgressView("Checking requirements…")
            case .ready:
                ProgressView("Starting…")
            case .needsMusicKitAuth:
                blockedView(
                    icon: "music.note",
                    title: "Apple Music Access Required",
                    message: "AI DJ needs access to your Apple Music library to play music.",
                    actionTitle: "Grant Access"
                ) {
                    Task { await vm.requestMusicAccess() }
                }
            case .needsAppleIntelligence(let reason):
                blockedView(
                    icon: "brain",
                    title: "Apple Intelligence Required",
                    message: reason,
                    actionTitle: "Open Settings"
                ) {
#if os(iOS)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
#endif
                }
            }
        }
        .task { await vm.checkStatus() }
        .onChange(of: vm.isReady) { _, ready in
            if ready {
                Log.onboarding.info("isReady fired → calling onReady()")
                onReady()
            }
        }
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
