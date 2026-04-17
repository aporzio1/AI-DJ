import SwiftUI

@MainActor
struct RootView: View {

    // Services — @State so they're created once and survive re-renders
    @State private var musicService = MusicKitService()
    @State private var audioGraph = AudioGraph()
    @State private var djBrain = DJBrain()
    @State private var djVoice = DJVoice()
    @State private var settings = SettingsViewModel()

    // Post-onboarding actors
    @State private var coordinator: PlaybackCoordinator?
    @State private var producer: Producer?
    @State private var isReady = false

    // Stable ViewModels created once after onboarding
    @State private var nowPlayingVM: NowPlayingViewModel?
    @State private var queueVM: QueueViewModel?
    @State private var libraryVM: LibraryViewModel?

    // Onboarding VM — also stable
    @State private var onboardingVM: OnboardingViewModel?

    // macOS sidebar selection
    @State private var selectedTab: AppTab = .nowPlaying

    var body: some View {
        Group {
            if isReady, let nowPlaying = nowPlayingVM, let queue = queueVM, let library = libraryVM {
                mainContent(nowPlaying: nowPlaying, queue: queue, library: library)
                    .onAppear { print("[RootView] Main content appeared") }
                    .onChange(of: settings.listenerName) { _, newName in
                        if let p = producer {
                            Task { await p.updateListenerName(newName.isEmpty ? nil : newName) }
                        }
                    }
                    .onChange(of: settings.djEnabled) { _, _ in updateProducerConfig() }
                    .onChange(of: settings.newsEnabled) { _, _ in updateProducerConfig() }
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
                print("[RootView] Creating OnboardingViewModel")
                onboardingVM = OnboardingViewModel(musicService: musicService)
            }
        }
    }

    private func handleReady() {
        print("[RootView] handleReady called — wiring coordinator + producer (listener=\(settings.listenerName))")
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
        nowPlayingVM = NowPlayingViewModel(coordinator: c, musicService: musicService, producer: p)
        queueVM = QueueViewModel(coordinator: c)
        libraryVM = LibraryViewModel(musicService: musicService, coordinator: c, producer: p)
        Task { await p.start() }
        Task.detached(priority: .utility) { [djBrain] in await djBrain.warmUp() }
        isReady = true
        print("[RootView] isReady = true")
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

    @ViewBuilder
    private func mainContent(nowPlaying: NowPlayingViewModel, queue: QueueViewModel, library: LibraryViewModel) -> some View {
#if os(macOS)
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Now Playing", systemImage: "music.note").tag(AppTab.nowPlaying)
                Label("Queue",       systemImage: "list.bullet").tag(AppTab.queue)
                Label("Library",     systemImage: "music.note.list").tag(AppTab.library)
                Label("Settings",    systemImage: "gear").tag(AppTab.settings)
            }
            .navigationTitle("AI DJ")
        } detail: {
            switch selectedTab {
            case .nowPlaying: NowPlayingView(vm: nowPlaying)
            case .queue:      QueueView(vm: queue)
            case .library:    LibraryView(vm: library)
            case .settings:   SettingsView(vm: settings)
            }
        }
#else
        TabView {
            NowPlayingView(vm: nowPlaying)
                .tabItem { Label("Now Playing", systemImage: "music.note") }
            NavigationStack { QueueView(vm: queue) }
                .tabItem { Label("Queue", systemImage: "list.bullet") }
            NavigationStack { LibraryView(vm: library) }
                .tabItem { Label("Library", systemImage: "music.note.list") }
            NavigationStack { SettingsView(vm: settings) }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
#endif
    }
}

private enum AppTab { case nowPlaying, queue, library, settings }
