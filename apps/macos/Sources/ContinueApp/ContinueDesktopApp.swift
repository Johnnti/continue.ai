import AppKit
import ContinueCore
import SwiftUI

@main
struct ContinueDesktopApp: App {
    @StateObject private var model: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let runtimeProvider = BackendRuntimeProvider()
        let checkpointProvider = BackendCheckpointProvider()
        _model = StateObject(
            wrappedValue: AppModel(
                runtimeProvider: runtimeProvider,
                runtimeController: runtimeProvider,
                captureController: runtimeProvider,
                checkpointProvider: checkpointProvider,
                summaryGenerator: checkpointProvider,
                voiceProvider: ElevenLabsVoiceProvider(),
                resumeProvider: PreviewResumeProvider(),
                returnNotifier: SystemReturnNotifier()
            )
        )
    }

    var body: some Scene {
        Window("Continue", id: "main") {
            AppShellView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 960, height: 640)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(model: model)
                .frame(width: 620, height: 580)
        }

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label("Continue", systemImage: "waveform.circle.fill")
                .task {
                    model.startMonitoring()
                }
        }
        .menuBarExtraStyle(.menu)
    }
}
