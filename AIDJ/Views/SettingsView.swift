import SwiftUI
import AVFoundation

private struct VoiceOption: Identifiable, Hashable {
    let id: String           // AVSpeechSynthesisVoice identifier
    let name: String
    let quality: Quality

    enum Quality: Int, Comparable {
        case compact, enhanced, premium
        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
        var label: String {
            switch self {
            case .premium:  "Premium"
            case .enhanced: "Enhanced"
            case .compact:  "Compact"
            }
        }
    }

    var displayName: String { "\(name) — \(quality.label)" }

    static func installedEnglish() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map {
                let q: Quality
                switch $0.quality {
                case .premium:  q = .premium
                case .enhanced: q = .enhanced
                default:        q = .compact
                }
                return VoiceOption(id: $0.identifier, name: $0.name, quality: q)
            }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                return lhs.name < rhs.name
            }
    }
}

struct SettingsView: View {
    @State private var vm: SettingsViewModel
    @State private var newFeedURL = ""
    @State private var showingOPMLImporter = false
    @State private var availableVoices: [VoiceOption] = []
    @Environment(\.openURL) private var openURL

    init(vm: SettingsViewModel) {
        self._vm = State(initialValue: vm)
    }

    var body: some View {
        Form {
            djSection
            voiceSection
            newsSection
            if vm.djEnabled && vm.newsEnabled {
                feedsSection
#if os(macOS)
                opmlSection
#endif
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            availableVoices = VoiceOption.installedEnglish()
            // If the previously-saved voice isn't installed anymore, fall back to default
            // so the Picker doesn't show an "invalid selection" warning.
            if !vm.voiceIdentifier.isEmpty,
               !availableVoices.contains(where: { $0.id == vm.voiceIdentifier }) {
                vm.voiceIdentifier = ""
                vm.save()
            }
        }
#if os(macOS)
        .fileImporter(isPresented: $showingOPMLImporter,
                      allowedContentTypes: [.xml, .data],
                      onCompletion: importOPML)
#endif
    }

    // MARK: - DJ

    private var djSection: some View {
        Section {
            Toggle("Enable DJ", isOn: $vm.djEnabled)

            HStack {
                Text("Your Name")
                Spacer(minLength: 16)
                TextField("", text: $vm.listenerName)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 240)
                    .onChange(of: vm.listenerName) { _, _ in vm.save() }
            }

            LabeledContent("Persona") {
                Text(vm.persona.name).foregroundStyle(.secondary)
            }
        } header: {
            Text("DJ")
        } footer: {
            Text("The DJ introduces tracks and adds commentary between songs. Your name may be used occasionally to personalize greetings.")
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            Picker("Provider", selection: $vm.ttsProvider) {
                ForEach(TTSProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: vm.ttsProvider) { _, _ in vm.save() }

            if vm.ttsProvider == .system {
                systemVoiceRows
            } else if vm.ttsProvider == .openAI {
                openAIRows
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
            Text("System Default").tag("")
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
            Text("Runs in the cloud. Requires an OpenAI API key. Costs roughly ¢0.6 per DJ segment on the Standard model; HD is double. Paste your key above — it's stored in the macOS Keychain, not in UserDefaults or logs.")
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
        Text("Install higher-quality voices in the Settings app: Accessibility → Spoken Content → Voices → English → download any Premium voice.")
#endif
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

    // MARK: - News

    private var newsSection: some View {
        Section {
            Toggle("Include News Headlines", isOn: $vm.newsEnabled)
                .disabled(!vm.djEnabled)
        } header: {
            Text("News")
        } footer: {
            Text("When enabled, the DJ may reference recent headlines from your RSS feeds.")
        }
    }

    // MARK: - RSS Feeds

    private var feedsSection: some View {
        Section {
            if vm.feedURLStrings.isEmpty {
                ContentUnavailableView {
                    Label("No Feeds", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("Add a feed URL below to pull in recent headlines.")
                }
                .padding(.vertical, 12)
            } else {
                ForEach(vm.feedURLStrings, id: \.self) { url in
                    feedRow(url)
                }
                .onDelete { vm.removeFeed(at: $0) }
            }

            addFeedRow
        } header: {
            Text("RSS Feeds")
        } footer: {
            Text("Feeds are fetched periodically and the most recent headlines are offered to the DJ.")
        }
    }

    private func feedRow(_ urlString: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hostName(for: urlString))
                .font(.body)
            Text(urlString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }

    private var addFeedRow: some View {
        HStack(spacing: 12) {
            TextField("https://example.com/feed.xml", text: $newFeedURL)
                .textFieldStyle(.plain)
#if os(iOS)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { commitFeed() }
#endif
            Button("Add") { commitFeed() }
                .buttonStyle(.bordered)
                .disabled(!isValidURL(newFeedURL))
        }
    }

    private func commitFeed() {
        guard isValidURL(newFeedURL) else { return }
        vm.addFeed(urlString: newFeedURL)
        newFeedURL = ""
    }

    private func isValidURL(_ string: String) -> Bool {
        guard !string.isEmpty, let url = URL(string: string), url.scheme != nil else { return false }
        return true
    }

    private func hostName(for urlString: String) -> String {
        guard let host = URL(string: urlString)?.host else { return urlString }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - OPML (macOS only)

#if os(macOS)
    private var opmlSection: some View {
        Section {
            Button {
                showingOPMLImporter = true
            } label: {
                Label("Import OPML File…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
        } footer: {
            Text("Import multiple feeds at once from an OPML file exported by another RSS reader.")
        }
    }

    private func importOPML(_ result: Result<URL, Error>) {
        guard case .success(let url) = result,
              let data = try? Data(contentsOf: url) else { return }
        vm.importOPML(data: data)
    }
#endif
}
