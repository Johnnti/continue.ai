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
            SettingsView(model: model)
                .frame(width: 620, height: 580)
        }
    }
}
