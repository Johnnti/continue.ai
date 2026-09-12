import ContinueCore
import SwiftUI

@main
struct ContinueDesktopApp: App {
    @StateObject private var model = AppModel(
        runtimeProvider: PreviewRuntimeProvider(),
        checkpointProvider: PreviewCheckpointProvider(),
        voiceProvider: PreviewVoiceProvider(),
        resumeProvider: PreviewResumeProvider()
    )

    var body: some Scene {
        WindowGroup {
            AppShellView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 960, height: 640)
        .windowStyle(.hiddenTitleBar)

        Settings {
            Text("Continue settings are available in the main window.")
                .frame(width: 420, height: 240)
        }
    }
}
