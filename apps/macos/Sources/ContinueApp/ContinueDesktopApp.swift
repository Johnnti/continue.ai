import AppKit
import ContinueCore
import SwiftUI

@main
struct ContinueDesktopApp: App {
    @StateObject private var model: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let configuration = ContinueIntegrationConfiguration()
        let runtimeProvider = SQLiteRuntimeProvider(
            databaseURL: configuration.memoryDatabaseURL
        )
        let checkpointProvider = SQLiteCheckpointProvider(
            databaseURL: configuration.memoryDatabaseURL
        )
        let voiceProvider = ElevenLabsVoiceProvider(
            configuration: configuration,
            checkpointProvider: checkpointProvider
        )
        _model = StateObject(
            wrappedValue: AppModel(
                runtimeProvider: runtimeProvider,
                runtimeController: runtimeProvider,
                checkpointProvider: checkpointProvider,
                voiceProvider: voiceProvider,
                resumeProvider: StoredCheckpointResumeProvider(
                    checkpointProvider: checkpointProvider
                ),
                returnNotifier: SystemReturnNotifier(),
                dataSourceLabel: "LIVE DATABASE + VOICE"
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
        .handlesExternalEvents(matching: ["continue://conversation"])

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
