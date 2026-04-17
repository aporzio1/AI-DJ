import SwiftUI

@main
struct AIDJApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
#if os(macOS)
        .commands {
            CommandGroup(replacing: .appInfo) {}
        }
#endif
    }
}
