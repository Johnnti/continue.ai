import ContinueCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Control how Continue interprets local context and presents return checkpoints.")
                        .foregroundStyle(.secondary)
                }

                captureSection
                voiceSection
                privacySection

                Label(
                    "Hackathon build: these preferences remain in memory until the app quits.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ContinueTheme.canvas)
    }

    private var captureSection: some View {
        SettingsSection(
            title: "Activity context",
            subtitle: "Screenpipe local API is the primary source. macOS foreground-app events can provide supplemental return hints.",
            systemImage: "rectangle.on.rectangle"
        ) {
            Toggle(
                "Interpret Screenpipe summaries",
                isOn: Binding(
                    get: { model.preferences.interpretationEnabled },
                    set: { model.setInterpretationEnabled($0) }
                )
            )

            Stepper(
                "Create a checkpoint after \(model.preferences.idleThresholdMinutes) minutes away",
                value: Binding(
                    get: { model.preferences.idleThresholdMinutes },
                    set: { model.setIdleThreshold(minutes: $0) }
                ),
                in: 5...60,
                step: 5
            )

            HStack {
                Label("Capture service", systemImage: captureStatusIcon)
                Spacer()
                Text(captureStatusText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    private var voiceSection: some View {
        SettingsSection(
            title: "Voice",
            subtitle: "The waveform represents the live voice session. Continue does not store microphone samples for visualization.",
            systemImage: "waveform"
        ) {
            Toggle(
                "Enable spoken return briefings",
                isOn: Binding(
                    get: { model.preferences.voiceBriefingsEnabled },
                    set: { model.setVoiceBriefingsEnabled($0) }
                )
            )
        }
    }

    private var privacySection: some View {
        SettingsSection(
            title: "Privacy",
            subtitle: "Checkpoint retention applies to interpreted summaries only. Screenpipe controls its own raw-data retention.",
            systemImage: "lock.shield"
        ) {
            Picker(
                "Keep checkpoints",
                selection: Binding(
                    get: { model.preferences.checkpointRetentionDays },
                    set: { model.setCheckpointRetention(days: $0) }
                )
            ) {
                Text("1 day").tag(1)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)

            Label(
                "Resume actions always require a separate confirmation.",
                systemImage: "hand.raised"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var captureStatusIcon: String {
        switch model.runtime.captureStatus {
        case .checking:
            "arrow.triangle.2.circlepath"
        case .available:
            "checkmark.circle.fill"
        case .unavailable:
            "exclamationmark.circle.fill"
        }
    }

    private var captureStatusText: String {
        switch model.runtime.captureStatus {
        case .checking:
            "Checking"
        case .available:
            "Available"
        case let .unavailable(reason):
            reason
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(ContinueTheme.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
            content
        }
        .padding(20)
        .background(ContinueTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.primary.opacity(0.08))
        }
    }
}
