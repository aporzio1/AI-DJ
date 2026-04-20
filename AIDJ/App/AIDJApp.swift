import SwiftUI

@main
struct AIDJApp: App {
    // Hoisted out of RootView so the macOS Settings scene can share the
    // same instances — otherwise Cmd+, would open a Settings window backed
    // by a different SettingsViewModel / DJVoiceRouter than the one in the
    // main window, and edits wouldn't be reflected.
    @State private var settings = SettingsViewModel()
    @State private var djVoice = DJVoiceRouter()

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, djVoice: djVoice)
        }
#if os(macOS)
        Settings {
            SettingsView(vm: settings, djVoice: djVoice)
                .frame(minWidth: 520, minHeight: 520)
        }
#endif
    }
}
