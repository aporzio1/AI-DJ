import SwiftUI

@MainActor
struct RootView: View {
    @State private var isReady = false

    // Services
    private let musicService = MusicKitService()
    private let audioGraph = AudioGraph()
    private let djBrain = DJBrain()
    private let djVoice = DJVoice()

    @State private var settings = SettingsViewModel()

    // Core actors (lazy init after onboarding completes)
    @State private var coordinator: PlaybackCoordinator?
    @State private var producer: Producer?

    var body: some View {
        if isReady, let coordinator {
            mainContent(coordinator: coordinator)
        } else {
            OnboardingView(vm: OnboardingViewModel(musicService: musicService)) {
                let c = PlaybackCoordinator(musicService: musicService, audioGraph: audioGraph)
                let p = Producer(
                    coordinator: c,
                    brain: djBrain,
                    voice: djVoice,
                    rssFetcher: RSSFetcher(feedURLs: settings.feedURLs),
                    persona: settings.persona
                )
                coordinator = c
                producer = p
                Task { await p.start() }
                isReady = true
            }
        }
    }

    @ViewBuilder
    private func mainContent(coordinator: PlaybackCoordinator) -> some View {
        let nowPlayingVM = NowPlayingViewModel(coordinator: coordinator)
        let queueVM = QueueViewModel(coordinator: coordinator)
        let libraryVM = LibraryViewModel(musicService: musicService, coordinator: coordinator)

#if os(macOS)
        NavigationSplitView {
            List {
                NavigationLink("Now Playing", value: AppTab.nowPlaying)
                NavigationLink("Queue", value: AppTab.queue)
                NavigationLink("Library", value: AppTab.library)
                NavigationLink("Settings", value: AppTab.settings)
            }
        } detail: {
            NavigationStack {
                NowPlayingView(vm: nowPlayingVM)
            }
        }
#else
        TabView {
            NowPlayingView(vm: nowPlayingVM)
                .tabItem { Label("Now Playing", systemImage: "music.note") }
            NavigationStack {
                QueueView(vm: queueVM)
            }
            .tabItem { Label("Queue", systemImage: "list.bullet") }
            NavigationStack {
                LibraryView(vm: libraryVM)
            }
            .tabItem { Label("Library", systemImage: "music.note.list") }
            NavigationStack {
                SettingsView(vm: settings)
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
#endif
    }
}

private enum AppTab: Hashable {
    case nowPlaying, queue, library, settings
}
