import SwiftUI

struct ICloudSection: View {
    @Bindable var vm: SettingsViewModel
    @State private var showingResetOnboardingConfirm = false
    @State private var showingResetOnboardingDone = false

    var body: some View {
        Section {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { vm.iCloudSyncEnabled },
                set: { vm.setiCloudSyncEnabled($0) }
            ))

            Button("Reset Onboarding") {
                showingResetOnboardingConfirm = true
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Relaunch the app to see the first-launch wizard again.")
        } header: {
            Text("iCloud")
        } footer: {
            Text("Syncs your preferences — DJ and news settings, feed URLs, personas, voice selection — across devices signed in to the same iCloud account. Your OpenAI API key stays on this device. \"Reset Onboarding\" takes effect next launch.")
        }
        .confirmationDialog(
            "Reset onboarding?",
            isPresented: $showingResetOnboardingConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                OnboardingViewModel.resetOnboardingFlag()
                showingResetOnboardingDone = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The first-launch wizard will run the next time you open the app. Your existing settings will not be erased.")
        }
        .alert("Onboarding Reset", isPresented: $showingResetOnboardingDone) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Quit and reopen Patter to see the first-launch wizard.")
        }
    }
}
