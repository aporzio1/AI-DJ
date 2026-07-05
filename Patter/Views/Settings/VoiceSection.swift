import SwiftUI
import AVFoundation

struct VoiceSection: View {
    @Bindable var vm: SettingsViewModel
    let voicePreview: VoicePreviewPlayer
    let availableVoices: [VoiceOption]
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Picker("Provider", selection: $vm.ttsProvider) {
                ForEach(TTSProvider.available) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: vm.ttsProvider) { _, _ in vm.save() }

            if vm.ttsProvider == .system {
                systemVoiceRows
            } else if vm.ttsProvider == .openAI {
                openAIRows
            } else if vm.ttsProvider == .kokoro {
                KokoroSection(vm: vm, voicePreview: voicePreview)
            }
        } header: {
            Text("Voice")
        } footer: {
            voiceFooter
        }
    }

    @ViewBuilder
    private var systemVoiceRows: some View {
        Picker("Voice", selection: $vm.voiceIdentifier) {
            Text("Best Available Device Voice").tag("")
            ForEach(availableVoices) { voice in
                Text(voice.displayName).tag(voice.id)
            }
        }
        .onChange(of: vm.voiceIdentifier) { _, _ in vm.save() }

#if os(macOS)
        Button {
            openSpokenContentSettings()
        } label: {
            Label("Open System Settings — Spoken Content", systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.bordered)
#endif
    }

    @ViewBuilder
    private var openAIRows: some View {
        HStack {
            Text("API Key")
            Spacer(minLength: 16)
            SecureField("sk-…", text: $vm.openAIAPIKey)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 320)
                .onSubmit { vm.saveAPIKey() }
        }
        Button("Save API Key") { vm.saveAPIKey() }
            .buttonStyle(.bordered)
            .disabled(vm.openAIAPIKey.isEmpty)

        Picker("Model", selection: $vm.openAIModel) {
            ForEach(OpenAITTSModel.allCases) { model in
                Text(model.displayName).tag(model.rawValue)
            }
        }
        .onChange(of: vm.openAIModel) { _, _ in vm.save() }

        Picker("Voice", selection: $vm.openAIVoice) {
            ForEach(OpenAITTSVoice.allCases) { voice in
                Text(voice.displayName).tag(voice.rawValue)
            }
        }
        .onChange(of: vm.openAIVoice) { _, _ in vm.save() }
    }

    @ViewBuilder
    private var voiceFooter: some View {
        switch vm.ttsProvider {
        case .system:
            systemVoiceFooter
        case .openAI:
            Text("Runs in the cloud. Requires an OpenAI API key. Costs roughly ¢0.6 per DJ segment on the Standard model; HD is double. Paste your key above — it's stored in the Keychain (synced across your devices via iCloud Keychain), never in UserDefaults or logs.")
        case .kokoro:
            Text("Runs fully on-device on the Apple Neural Engine — no API key, no network at render time. The first DJ segment downloads a ~300 MB model; after that everything stays local. American English only.")
        }
    }

    @ViewBuilder
    private var systemVoiceFooter: some View {
#if os(macOS)
        VStack(alignment: .leading, spacing: 8) {
            Text("Premium voices sound much more natural. To download one:")
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Click the button above to open Spoken Content")
                Text("2. Click the **System Voice** pop-up menu")
                Text("3. Scroll to the bottom and choose **Manage Voices…** (or **Customize…**)")
                Text("4. Check a Premium English voice like **Ava**, **Zoe**, or **Evan** under English (United States)")
                Text("5. Wait for the download, then return here and pick it from the list")
            }
            .padding(.leading, 4)
        }
#else
        if hasPremiumEnglishVoice {
            Text("Pick the highest-quality option above. Premium voices sound the most natural; Enhanced are second-best. Add more from Settings → Accessibility → Spoken Content → Voices (or Accessibility → VoiceOver → Speech).")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Premium voices sound much more natural than the Compact defaults. To download one:")
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Open the **Settings** app")
                    Text("2. Go to **Accessibility → Spoken Content → Voices** (or **Accessibility → VoiceOver → Speech** if Spoken Content is hidden)")
                    Text("3. Tap **English**, pick any voice marked **Premium** (Ava, Zoe, Evan…)")
                    Text("4. Wait for the download, return here, and pick it from the list above")
                }
                .padding(.leading, 4)
            }
        }
#endif
    }

    private var hasPremiumEnglishVoice: Bool {
        availableVoices.contains { $0.quality == .premium }
    }

#if os(macOS)
    private func openSpokenContentSettings() {
        // Try the deep link to Spoken Content first; fall back to Accessibility root.
        let candidates = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Content_Speech",
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.universalaccess"
        ]
        for string in candidates {
            if let url = URL(string: string) {
                openURL(url)
                return
            }
        }
    }
#endif
}
