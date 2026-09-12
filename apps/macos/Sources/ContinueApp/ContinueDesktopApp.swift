import SwiftUI

@main
struct ContinueDesktopApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 960, height: 640)
        .windowStyle(.hiddenTitleBar)

        Settings {
            Text("Continue settings")
                .frame(width: 420, height: 240)
        }
    }
}
