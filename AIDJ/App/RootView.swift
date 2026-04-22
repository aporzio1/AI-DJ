import SwiftUI

@MainActor
struct RootView: View {

    // Owned by AIDJApp so the macOS Settings scene shares the same instances.
    let settings: SettingsViewModel
    let djVoice: DJVoiceRouter
    let musicProvider: MusicProviderRouter

    @State private var audioGraph = AudioGraph()
    @State private var djBrain = DJBrain()
    @State private var feedbackStore = TrackFeedbackStore()
    @State private var rssFetcher = RSSFetcher(feedURLs: [])
    @State private var kokoroDownload = KokoroDownloadState.shared

    // Post-onboarding actors
    @State private var coordinator: PlaybackCoordinator?
    @State private var producer: Producer?
    @State private var isReady = false

    // Stable ViewModels created once after onboarding
    @State private var nowPlayingVM: NowPlayingViewModel?
    @State private var queueVM: QueueViewModel?
    @State private var libraryVM: LibraryViewModel?
    @State private var onboardingVM: OnboardingViewModel?

    // Top-level nav
    @State private var selectedTab: AppTab = .library
    @State private var showingNowPlaying = false

    var body: some View {
        Group {
            if isReady, let nowPlaying = nowPlayingVM, let queue = queueVM, let library = libraryVM {
                mainContent(nowPlaying: nowPlaying, queue: queue, library: library)
                    .onAppear { Log.app.info("Main content appeared") }
                    .onChange(of: settings.listenerName) { _, newName in
                        if let p = producer {
                            Task { await p.updateListenerName(newName.isEmpty ? nil : newName) }
                        }
                    }
                    .onChange(of: settings.djEnabled) { _, _ in updateProducerConfig() }
                    .onChange(of: settings.djFrequency) { _, _ in updateProducerConfig() }
                    .onChange(of: settings.newsEnabled) { _, _ in updateProducerConfig() }
                    .onChange(of: settings.newsFrequency) { _, _ in updateProducerConfig() }
                    .onChange(of: settings.feedURLStrings) { _, _ in
                        rssFetcher.updateFeeds(settings.feedURLs)
                    }
                    .onChange(of: settings.voiceIdentifier) { _, newID in
                        if let p = producer {
                            Task { await p.updateVoice(newID.isEmpty ? nil : newID) }
                        }
                    }
                    .onChange(of: settings.persona) { _, newPersona in
                        if let p = producer {
                            Task { await p.updatePersona(newPersona) }
                        }
                    }
                    .onChange(of: settings.ttsProvider) { _, newProvider in
                        djVoice.provider = newProvider
                        applyVoiceSelection()
                    }
                    .onChange(of: settings.openAIVoice) { _, _ in applyVoiceSelection() }
                    .onChange(of: settings.kokoroVoice) { _, _ in applyVoiceSelection() }
                    .onChange(of: settings.openAIModel) { _, newRaw in
                        if let model = OpenAITTSModel(rawValue: newRaw) {
                            djVoice.setOpenAIModel(model)
                        }
                    }
                    .sheet(isPresented: $showingNowPlaying) {
                        NavigationStack {
                            NowPlayingView(vm: nowPlaying)
                                .navigationTitle("Now Playing")
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { showingNowPlaying = false }
                                    }
                                }
                        }
#if os(macOS)
                        .frame(minWidth: 440, minHeight: 600)
#endif
                    }
            } else {
                if let vm = onboardingVM {
                    OnboardingView(vm: vm, settings: settings, onReady: handleReady)
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            if onboardingVM == nil {
                Log.app.info("Creating OnboardingViewModel")
                onboardingVM = OnboardingViewModel(musicService: musicProvider.appleMusic)
            }
        }
    }

    private func handleReady() {
        Log.app.info("handleReady — wiring coordinator + producer (listener=\(settings.listenerName, privacy: .public))")
        let c = PlaybackCoordinator(router: musicProvider, audioGraph: audioGraph)
        rssFetcher.updateFeeds(settings.feedURLs)
        let p = Producer(
            coordinator: c,
            brain: djBrain,
            voice: djVoice,
            rssFetcher: rssFetcher,
            feedbackStore: feedbackStore,
            persona: settings.persona,
            listenerName: settings.listenerName.isEmpty ? nil : settings.listenerName,
            config: producerConfig()
        )
        coordinator = c
        producer = p
        let npVM = NowPlayingViewModel(coordinator: c, router: musicProvider, producer: p, feedbackStore: feedbackStore)
        npVM.startObserving()   // keep the mini-player state fresh for the whole session
        nowPlayingVM = npVM
        queueVM = QueueViewModel(coordinator: c)
        libraryVM = LibraryViewModel(router: musicProvider, coordinator: c, producer: p, initialProvider: settings.browseProvider)
        Task { await p.start() }
        // Apply persisted voice + provider settings on boot
        djVoice.provider = settings.ttsProvider
        if let model = OpenAITTSModel(rawValue: settings.openAIModel) {
            djVoice.setOpenAIModel(model)
        }
        applyVoiceSelection()
        Task.detached(priority: .utility) { [djBrain] in await djBrain.warmUp() }
        // If Kokoro is the active provider AND the DJ is enabled, warm it
        // up now (in the background, fire-and-forget) so the first DJ
        // segment doesn't eat the CoreML compile + warm-up stall. Skipping
        // this when the DJ is off — there's no point paying the compile
        // cost (and surfacing the "Loading DJ voice…" indicator) if no
        // segment will ever be rendered. The KokoroDownloadState overlay
        // in MiniPlayerBar shows during this window if the user notices.
        if settings.djEnabled && settings.ttsProvider == .kokoro {
            Task.detached(priority: .utility) { [djVoice] in
                try? await djVoice.prepareKokoroModel()
            }
        }
        isReady = true
        Log.app.info("isReady = true")
    }

    /// Pick the right voice identifier for the current provider and push it to Producer.
    private func applyVoiceSelection() {
        guard let p = producer else { return }
        let id: String
        switch settings.ttsProvider {
        case .system:  id = settings.voiceIdentifier
        case .openAI:  id = settings.openAIVoice
        case .kokoro:  id = settings.kokoroVoice
        }
        Task { await p.updateVoice(id.isEmpty ? nil : id) }
    }

    private func producerConfig() -> Producer.Config {
        Producer.Config(
            djEnabled: settings.djEnabled,
            newsEnabled: settings.newsEnabled,
            djFrequency: settings.djFrequency,
            newsFrequency: settings.newsFrequency
        )
    }

    private func updateProducerConfig() {
        let cfg = producerConfig()
        if let p = producer {
            Task { await p.updateConfig(cfg) }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func mainContent(nowPlaying: NowPlayingViewModel,
                             queue: QueueViewModel,
                             library: LibraryViewModel) -> some View {
#if os(macOS)
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Library",  systemImage: "music.note.list").tag(AppTab.library)
                Label("Queue",    systemImage: "list.bullet").tag(AppTab.queue)
                Label("Settings", systemImage: "gear").tag(AppTab.settings)
            }
            .navigationTitle("AI DJ")
        } detail: {
            VStack(spacing: 0) {
                detailContent(nowPlaying: nowPlaying, queue: queue, library: library)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MiniPlayerBar(vm: nowPlaying, download: kokoroDownload) { showingNowPlaying = true }
            }
        }
#else
        TabView(selection: $selectedTab) {
            NavigationStack { LibraryView(vm: library, settings: settings) }
                .miniPlayerBarOverlay(vm: nowPlaying, download: kokoroDownload, onTap: { showingNowPlaying = true })
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(AppTab.library)
            NavigationStack { QueueView(vm: queue) }
                .miniPlayerBarOverlay(vm: nowPlaying, download: kokoroDownload, onTap: { showingNowPlaying = true })
                .tabItem { Label("Queue", systemImage: "list.bullet") }
                .tag(AppTab.queue)
            NavigationStack { SettingsView(vm: settings, djVoice: djVoice, musicProvider: musicProvider) }
                .miniPlayerBarOverlay(vm: nowPlaying, download: kokoroDownload, onTap: { showingNowPlaying = true })
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
        }
#endif
    }

    @ViewBuilder
    private func detailContent(nowPlaying: NowPlayingViewModel,
                               queue: QueueViewModel,
                               library: LibraryViewModel) -> some View {
        switch selectedTab {
        case .library:  NavigationStack { LibraryView(vm: library, settings: settings) }
        case .queue:    NavigationStack { QueueView(vm: queue) }
        case .settings: NavigationStack { SettingsView(vm: settings, djVoice: djVoice, musicProvider: musicProvider) }
        }
    }
}

private enum AppTab: Hashable {
    case library, queue, settings
}

private extension View {
    /// Inserts a MiniPlayerBar above the tab bar when there's something to
    /// show — an active queue item OR an in-flight Kokoro model download
    /// (so the user sees the "Downloading DJ voice…" indicator even on a
    /// fresh app where no track has played yet). Applied per-tab so the
    /// system tab bar chrome is never obscured at app launch.
    ///
    /// Takes the KokoroDownloadState as an explicit parameter (rather than
    /// reading the singleton here) so SwiftUI's @Observable tracking is
    /// rooted at the caller's body — without this, re-renders on
    /// isDownloading changes didn't fire and the indicator stayed hidden.
    @MainActor
    func miniPlayerBarOverlay(
        vm: NowPlayingViewModel,
        download: KokoroDownloadState,
        onTap: @escaping () -> Void
    ) -> some View {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            // Show the bar when there's a queue item (normal playback) OR
            // Kokoro is doing anything (download, load, warm-up) so the
            // indicator is visible even on a fresh app with no queue yet.
            if vm.currentItem != nil || download.isActive {
                MiniPlayerBar(vm: vm, download: download, onTap: onTap)
            }
        }
    }
}
