import SwiftUI

@main
struct AIDJApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
#if os(macOS)
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Skip DJ Segment") {
                    // Handled via notification or environment object in a future pass
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
#endif
    }
}
