import AppKit
import ContinueCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(captureStatusText, systemImage: captureStatusIcon)
        Label(
            model.preferences.interpretationEnabled
                ? "Continue summaries: On"
                : "Continue summaries: Paused",
            systemImage: model.preferences.interpretationEnabled
                ? "sparkles"
                : "pause.circle"
        )

        Divider()

        Button(captureButtonTitle, systemImage: captureButtonIcon) {
            model.toggleCapture()
        }
        .disabled(model.isUpdatingCapture || model.runtime.captureStatus == .checking)

        Button("I'm stepping away", systemImage: "figure.walk.departure") {
            model.markSteppingAway()
        }
        .disabled(
            !model.preferences.interpretationEnabled
                || model.runtime.phase == .away
                || model.isUpdatingRuntime
        )

        Button(
            model.preferences.interpretationEnabled
                ? "Pause Continue summaries"
                : "Resume Continue summaries",
            systemImage: model.preferences.interpretationEnabled
                ? "pause.fill"
                : "play.fill"
        ) {
            model.setInterpretationEnabled(!model.preferences.interpretationEnabled)
        }

        Divider()

        Button("Open Continue", systemImage: "macwindow") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }

        Divider()

        Button("Quit Continue") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var captureStatusIcon: String {
        switch model.runtime.captureStatus {
        case .checking:
            "arrow.triangle.2.circlepath"
        case .recording:
            "record.circle.fill"
        case .paused:
            "pause.circle"
        case .unavailable:
            "exclamationmark.circle.fill"
        }
    }

    private var captureStatusText: String {
        switch model.runtime.captureStatus {
        case .checking:
            "Screenpipe recording: Checking"
        case .recording:
            "Screenpipe recording: On"
        case .paused:
            "Screenpipe recording: Paused"
        case let .unavailable(reason):
            "Screenpipe recording: Off (\(reason))"
        }
    }

    private var captureButtonTitle: String {
        if model.isUpdatingCapture {
            return model.runtime.captureStatus == .recording ? "Stopping recording…" : "Starting recording…"
        }
        if case .recording = model.runtime.captureStatus {
            return "Stop recording"
        }
        return "Start recording"
    }

    private var captureButtonIcon: String {
        if case .recording = model.runtime.captureStatus, !model.isUpdatingCapture {
            return "stop.fill"
        }
        return "record.circle"
    }
}
