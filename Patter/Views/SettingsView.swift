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

    // Kokoro model management
    private let djVoice: DJVoiceRouter
    @State private var kokoroModelInstalled: Bool = false
    @State private var kokoroDownloading: Bool = false
    @State private var kokoroRemoving: Bool = false
    @State private var kokoroError: String?
    @State private var showingKokoroRemoveConfirm = false
    @State private var kokoroPreviewState: KokoroPreviewState = .idle
    @State private var kokoroPreviewPlayer: AVAudioPlayer?

    @State private var showingPersonaList = false
    @State private var feedPendingRemoval: String?
    @State private var showingResetOnboardingConfirm = false
    @State private var showingResetOnboardingDone = false

    private enum KokoroPreviewState: Equatable {
        case idle, rendering, playing
    }

    init(vm: SettingsViewModel, djVoice: DJVoiceRouter) {
        self._vm = State(initialValue: vm)
        self.djVoice = djVoice
    }

    var body: some View {
        Form {
            musicServicesSection
            djSection
            voiceSection
            newsSection
            if vm.djEnabled && vm.newsEnabled {
                feedsSection
                suggestedFeedsSection
#if os(macOS)
                opmlSection
#endif
            }
            iCloudSection
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
            kokoroModelInstalled = djVoice.isKokoroModelInstalled
        }
        .confirmationDialog(
            "Remove Kokoro model?",
            isPresented: $showingKokoroRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove Model", role: .destructive) {
                Task { await removeKokoroModel() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes ~300 MB of cached CoreML model files. The next DJ segment using Kokoro will re-download them.")
        }
#if os(macOS)
        .fileImporter(isPresented: $showingOPMLImporter,
                      allowedContentTypes: [.xml, .data],
                      onCompletion: importOPML)
#endif
    }

    // MARK: - Music Services

    private var musicServicesSection: some View {
        Section {
            LabeledContent("Apple Music") {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Authorized")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Music Services")
        } footer: {
            Text("Apple Music authorization is managed in the system Settings app.")
        }
    }

    // MARK: - DJ

    private var djSection: some View {
        Section {
            Toggle("Enable DJ", isOn: $vm.djEnabled)
                .onChange(of: vm.djEnabled) { _, _ in vm.save() }

            Picker("Frequency", selection: $vm.djFrequency) {
                ForEach(DJFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!vm.djEnabled)
            .onChange(of: vm.djFrequency) { _, _ in vm.save() }

            HStack {
                Text("Your Name")
                Spacer(minLength: 16)
                TextField("", text: $vm.listenerName)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 240)
                    .onChange(of: vm.listenerName) { _, _ in vm.save() }
            }

            Button {
                showingPersonaList = true
            } label: {
                HStack {
                    Text("Persona")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(vm.persona.name)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("DJ")
        } footer: {
            Text("The DJ introduces tracks and adds commentary between songs. Your name may be used occasionally to personalize greetings.")
        }
        .sheet(isPresented: $showingPersonaList) {
            PersonaListView(vm: vm)
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
            } else if vm.ttsProvider == .kokoro {
                kokoroRows
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
    private var kokoroRows: some View {
        Picker("Voice", selection: $vm.kokoroVoice) {
            ForEach(KokoroVoice.allCases) { voice in
                Text(voice.displayName).tag(voice.rawValue)
            }
        }
        .onChange(of: vm.kokoroVoice) { _, _ in
            vm.save()
            stopKokoroPreview()
        }

        Button {
            Task { await toggleKokoroPreview() }
        } label: {
            switch kokoroPreviewState {
            case .idle:
                Label("Preview Voice", systemImage: "play.circle")
            case .rendering:
                HStack(spacing: 8) {
                    ProgressView()
#if os(macOS)
                        .controlSize(.small)
#endif
                    Text("Rendering…")
                }
            case .playing:
                Label("Stop Preview", systemImage: "stop.circle")
            }
        }
        .buttonStyle(.bordered)
        .disabled(!kokoroModelInstalled || kokoroDownloading || kokoroRemoving || kokoroPreviewState == .rendering)

        LabeledContent("Model") {
            HStack(spacing: 8) {
                Image(systemName: kokoroModelInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(kokoroModelInstalled ? Color.green : Color.secondary)
                Text(kokoroModelInstalled ? "Installed" : "Not Installed")
                    .foregroundStyle(.secondary)
            }
        }

        if kokoroDownloading {
            HStack(spacing: 12) {
                ProgressView()
#if os(macOS)
                    .controlSize(.small)
#endif
                Text("Downloading model…").foregroundStyle(.secondary)
            }
            .frame(minHeight: 44, alignment: .leading)
        } else {
            Button {
                Task { await downloadKokoroModel() }
            } label: {
                Label(
                    kokoroModelInstalled ? "Re-download Model" : "Download Model",
                    systemImage: "arrow.down.circle"
                )
            }
            .buttonStyle(.bordered)
            .disabled(kokoroRemoving)
        }

        Button(role: .destructive) {
            showingKokoroRemoveConfirm = true
        } label: {
            Label("Remove Model", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(!kokoroModelInstalled || kokoroDownloading || kokoroRemoving)

        if let err = kokoroError {
            Text(err)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func downloadKokoroModel() async {
        kokoroDownloading = true
        kokoroError = nil
        do {
            try await djVoice.prepareKokoroModel()
            kokoroModelInstalled = djVoice.isKokoroModelInstalled
        } catch {
            kokoroError = error.localizedDescription
        }
        kokoroDownloading = false
    }

    private func removeKokoroModel() async {
        kokoroRemoving = true
        kokoroError = nil
        stopKokoroPreview()
        do {
            try await djVoice.removeKokoroModel()
            kokoroModelInstalled = djVoice.isKokoroModelInstalled
        } catch {
            kokoroError = error.localizedDescription
        }
        kokoroRemoving = false
    }

    private func toggleKokoroPreview() async {
        switch kokoroPreviewState {
        case .idle:      await startKokoroPreview()
        case .rendering: return
        case .playing:   stopKokoroPreview()
        }
    }

    private func startKokoroPreview() async {
        kokoroPreviewState = .rendering
        kokoroError = nil
        let sample = "Hey, this is your DJ checking in. Coming up next, another great track."
        do {
            let url = try await djVoice.renderKokoroSample(
                script: sample,
                voiceIdentifier: vm.kokoroVoice
            )
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            kokoroPreviewPlayer = player
            kokoroPreviewState = .playing
            player.play()
            let duration = player.duration
            try? await Task.sleep(for: .seconds(duration + 0.15))
            // Only reset state if this preview is still the active one.
            if kokoroPreviewPlayer === player {
                kokoroPreviewPlayer = nil
                kokoroPreviewState = .idle
            }
        } catch {
            kokoroError = error.localizedDescription
            kokoroPreviewPlayer = nil
            kokoroPreviewState = .idle
        }
    }

    private func stopKokoroPreview() {
        kokoroPreviewPlayer?.stop()
        kokoroPreviewPlayer = nil
        if kokoroPreviewState == .playing {
            kokoroPreviewState = .idle
        }
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
            Text("Pick the highest-quality option above. Premium voices sound the most natural; Enhanced are second-best. Add more from Settings → Accessibility → Spoken Content → Voices.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Premium voices sound much more natural than the Compact defaults. To download one:")
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Open the **Settings** app")
                    Text("2. Go to **Accessibility → Spoken Content → Voices**")
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

    // MARK: - iCloud

    private var iCloudSection: some View {
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

    // MARK: - News

    private var newsSection: some View {
        Section {
            Toggle("Include News Headlines", isOn: $vm.newsEnabled)
                .disabled(!vm.djEnabled)
                .onChange(of: vm.newsEnabled) { _, _ in vm.save() }

            Picker("Frequency", selection: $vm.newsFrequency) {
                ForEach(NewsFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!vm.djEnabled || !vm.newsEnabled)
            .onChange(of: vm.newsFrequency) { _, _ in vm.save() }
        } header: {
            Text("News")
        } footer: {
            Text("When enabled, the DJ will reference a recent headline from your RSS feeds. Frequency controls how often a headline is injected into a DJ segment.")
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

    private var suggestedFeedsSection: some View {
        Section {
            ForEach(SuggestedRSSFeeds.all) { feed in
                suggestedFeedRow(feed)
            }
        } header: {
            Text("Suggested Feeds")
        } footer: {
            Text("Tap to add a curated feed. Tap again to remove.")
        }
    }

    private func suggestedFeedRow(_ feed: SuggestedRSSFeed) -> some View {
        let isAdded = vm.feedURLStrings.contains(feed.url)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name).font(.body)
                Text(feed.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button {
                if isAdded {
                    vm.feedURLStrings.removeAll { $0 == feed.url }
                    vm.save()
                } else {
                    vm.addFeed(urlString: feed.url)
                }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isAdded ? Color.accentColor : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdded ? "Remove \(feed.name)" : "Add \(feed.name)")
        }
        .padding(.vertical, 4)
    }

    private func feedRow(_ urlString: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hostName(for: urlString))
                    .font(.body)
                Text(urlString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                feedPendingRemoval = urlString
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove feed")
        }
        .confirmationDialog(
            "Remove this feed?",
            isPresented: Binding(
                get: { feedPendingRemoval == urlString },
                set: { if !$0 { feedPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                deleteFeed(urlString: urlString)
                feedPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                feedPendingRemoval = nil
            }
        } message: {
            Text(hostName(for: urlString))
        }
        .padding(.vertical, 4)
    }

    private func deleteFeed(urlString: String) {
        if let idx = vm.feedURLStrings.firstIndex(of: urlString) {
            vm.removeFeed(at: IndexSet(integer: idx))
        }
    }

    private var addFeedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Feed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField(
                    "",
                    text: $newFeedURL,
                    prompt: Text(verbatim: "https://example.com/feed.xml")
                )
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { commitFeed() }
#endif
                Button("Add") { commitFeed() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidURL(newFeedURL))
            }
        }
        .padding(.vertical, 4)
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
