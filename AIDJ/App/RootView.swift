import SwiftUI

@MainActor
struct RootView: View {

    // Services — @State so they're created once and survive re-renders
    @State private var musicService = MusicKitService()
    @State private var audioGraph = AudioGraph()
    @State private var djBrain = DJBrain()
    @State private var djVoice = DJVoiceRouter()
    @State private var settings = SettingsViewModel()

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
                    .onChange(of: settings.newsEnabled) { _, _ in updateProducerConfig() }
                    .onChange(of: settings.voiceIdentifier) { _, newID in
                        if let p = producer {
                            Task { await p.updateVoice(newID.isEmpty ? nil : newID) }
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
                    OnboardingView(vm: vm, onReady: handleReady)
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            if onboardingVM == nil {
                Log.app.info("Creating OnboardingViewModel")
                onboardingVM = OnboardingViewModel(musicService: musicService)
            }
        }
    }

    private func handleReady() {
        Log.app.info("handleReady — wiring coordinator + producer (listener=\(settings.listenerName, privacy: .public))")
        let c = PlaybackCoordinator(musicService: musicService, audioGraph: audioGraph)
        let rss = RSSFetcher(feedURLs: settings.feedURLs)
        let p = Producer(
            coordinator: c,
            brain: djBrain,
            voice: djVoice,
            rssFetcher: rss,
            persona: settings.persona,
            listenerName: settings.listenerName.isEmpty ? nil : settings.listenerName,
            config: producerConfig()
        )
        coordinator = c
        producer = p
        let npVM = NowPlayingViewModel(coordinator: c, musicService: musicService, producer: p)
        npVM.startObserving()   // keep the mini-player state fresh for the whole session
        nowPlayingVM = npVM
        queueVM = QueueViewModel(coordinator: c)
        libraryVM = LibraryViewModel(musicService: musicService, coordinator: c, producer: p)
        Task { await p.start() }
        // Apply persisted voice + provider settings on boot
        djVoice.provider = settings.ttsProvider
        if let model = OpenAITTSModel(rawValue: settings.openAIModel) {
            djVoice.setOpenAIModel(model)
        }
        applyVoiceSelection()
        Task.detached(priority: .utility) { [djBrain] in await djBrain.warmUp() }
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
        Producer.Config(djEnabled: settings.djEnabled, newsEnabled: settings.newsEnabled)
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
                MiniPlayerBar(vm: nowPlaying) { showingNowPlaying = true }
            }
        }
#else
        TabView(selection: $selectedTab) {
            NavigationStack { LibraryView(vm: library) }
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(AppTab.library)
            NavigationStack { QueueView(vm: queue) }
                .tabItem { Label("Queue", systemImage: "list.bullet") }
                .tag(AppTab.queue)
            NavigationStack { SettingsView(vm: settings, djVoice: djVoice) }
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerBar(vm: nowPlaying) { showingNowPlaying = true }
        }
#endif
    }

    @ViewBuilder
    private func detailContent(nowPlaying: NowPlayingViewModel,
                               queue: QueueViewModel,
                               library: LibraryViewModel) -> some View {
        switch selectedTab {
        case .library:  NavigationStack { LibraryView(vm: library) }
        case .queue:    NavigationStack { QueueView(vm: queue) }
        case .settings: NavigationStack { SettingsView(vm: settings, djVoice: djVoice) }
        }
    }
}

private enum AppTab: Hashable {
    case library, queue, settings
}
