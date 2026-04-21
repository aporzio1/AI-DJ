import SwiftUI

@main
struct AIDJApp: App {
    // Hoisted out of RootView so the macOS Settings scene can share the
    // same instances — otherwise Cmd+, would open a Settings window backed
    // by a different SettingsViewModel / DJVoiceRouter / MusicProviderRouter
    // than the one in the main window, and edits wouldn't be reflected.
    @State private var settings = SettingsViewModel()
    @State private var djVoice = DJVoiceRouter()
    @State private var musicProvider: MusicProviderRouter = {
        let spotifyAuth = SpotifyAuthCoordinator()
        let spotifyAPI = SpotifyAPIClient(auth: spotifyAuth)
        let spotifyService = SpotifyService(auth: spotifyAuth, api: spotifyAPI)
        return MusicProviderRouter(appleMusic: MusicKitService(), spotify: spotifyService)
    }()

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, djVoice: djVoice, musicProvider: musicProvider)
        }
#if os(macOS)
        Settings {
            SettingsView(vm: settings, djVoice: djVoice, musicProvider: musicProvider)
                .frame(minWidth: 520, minHeight: 520)
        }
#endif
    }
}
