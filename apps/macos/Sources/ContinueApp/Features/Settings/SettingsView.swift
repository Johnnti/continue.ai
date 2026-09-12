import ContinueCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var newExcludedApplication = ""

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
                notificationSection
                voiceSection
                privacySection

                Label(
                    "Preferences are saved on this Mac and restored the next time Continue opens.",
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
        .accessibilityIdentifier("settings.screen")
    }

    private var captureSection: some View {
        SettingsSection(
            title: "Activity context",
            subtitle: "Screenpipe records local activity while enabled. Continue creates summaries only at an away checkpoint.",
            systemImage: "rectangle.on.rectangle"
        ) {
            Toggle(
                "Record activity with Screenpipe",
                isOn: Binding(
                    get: { model.preferences.captureEnabled },
                    set: { model.setCaptureEnabled($0) }
                )
            )
            .accessibilityIdentifier("settings.capture")

            Toggle(
                "Create return summaries from Screenpipe",
                isOn: Binding(
                    get: { model.preferences.interpretationEnabled },
                    set: { model.setInterpretationEnabled($0) }
                )
            )
            .accessibilityIdentifier("settings.interpretation")

            Stepper(
                "Create a checkpoint after \(model.preferences.idleThresholdMinutes) minutes away",
                value: Binding(
                    get: { model.preferences.idleThresholdMinutes },
                    set: { model.setIdleThreshold(minutes: $0) }
                ),
                in: 1...60,
                step: 1
            )

            Picker(
                "Create checkpoints",
                selection: Binding(
                    get: { model.preferences.checkpointTrigger },
                    set: { model.setCheckpointTrigger($0) }
                )
            ) {
                ForEach(CheckpointTrigger.allCases, id: \.self) { trigger in
                    Text(trigger.title).tag(trigger)
                }
            }
            .accessibilityIdentifier("settings.checkpoint-trigger")

            Text(model.preferences.checkpointTrigger.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "Limit Screenpipe capture to a schedule",
                isOn: Binding(
                    get: { model.preferences.trackingSchedule.isEnabled },
                    set: { model.setTrackingScheduleEnabled($0) }
                )
            )
            .accessibilityIdentifier("settings.tracking-schedule")

            if model.preferences.trackingSchedule.isEnabled {
                HStack {
                    Picker(
                        "Start",
                        selection: Binding(
                            get: { model.preferences.trackingSchedule.startHour },
                            set: { model.setTrackingScheduleStart(hour: $0) }
                        )
                    ) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(TrackingSchedule.hourLabel(hour)).tag(hour)
                        }
                    }

                    Picker(
                        "End",
                        selection: Binding(
                            get: { model.preferences.trackingSchedule.endHour },
                            set: { model.setTrackingScheduleEnd(hour: $0) }
                        )
                    ) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(TrackingSchedule.hourLabel(hour)).tag(hour)
                        }
                    }
                }

                Text("Continue tracks activity between \(model.preferences.trackingSchedule.displayRange).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(
                "Observation window",
                selection: Binding(
                    get: { model.preferences.observationWindowMinutes },
                    set: { model.setObservationWindow(minutes: $0) }
                )
            ) {
                ForEach(AppPreferences.observationWindowOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.observation-window")

            HStack {
                Label("Screenpipe recording", systemImage: captureStatusIcon)
                Spacer()
                Text(captureStatusText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            HStack {
                Label(
                    "Continue summaries",
                    systemImage: model.preferences.interpretationEnabled ? "sparkles" : "pause.circle"
                )
                Spacer()
                Text(model.preferences.interpretationEnabled ? "On" : "Paused")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Label(
                "Pausing Continue summaries does not stop Screenpipe recording.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var voiceSection: some View {
        SettingsSection(
            title: "Voice",
            subtitle: "Start a two-way voice conversation when you want one. The waveform represents the live session; the microphone does not start automatically.",
            systemImage: "waveform"
        ) {
            Toggle(
                "Enable voice conversations",
                isOn: Binding(
                    get: { model.preferences.voiceBriefingsEnabled },
                    set: { model.setVoiceBriefingsEnabled($0) }
                )
            )
            .accessibilityIdentifier("settings.voice-briefings")
        }
    }

    private var notificationSection: some View {
        SettingsSection(
            title: "Return notifications",
            subtitle: "Continue posts a passive, generic notification when a new return summary is ready. Delivery never opens or focuses Continue automatically.",
            systemImage: "bell"
        ) {
            HStack {
                Label("Notification permission", systemImage: notificationStatusIcon)
                Spacer()
                Text(notificationStatusText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if model.notificationAuthorization == .notDetermined {
                Button("Enable return notifications") {
                    model.requestNotificationAuthorization()
                }
                .disabled(model.isRequestingNotificationAuthorization)
            } else if model.notificationAuthorization == .denied {
                Label(
                    "Notifications are disabled in macOS System Settings.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(
            title: "Privacy",
            subtitle: "Checkpoint retention applies to interpreted summaries. The current streaming helper does not retain raw frames.",
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
            .accessibilityIdentifier("settings.checkpoint-retention")

            Picker(
                "Keep Screenpipe raw data",
                selection: Binding(
                    get: { model.preferences.screenpipeRetentionDays },
                    set: { model.setScreenpipeRetention(days: $0) }
                )
            ) {
                Text("Screenpipe manages").tag(0)
                Text("1 day").tag(1)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
            }
            .disabled(true)
            .accessibilityIdentifier("settings.screenpipe-retention")

            Label(
                "Raw-retention choices are reserved for a future persistent Screenpipe adapter. Continue currently stores no raw screen or audio data.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Excluded applications")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    TextField("Application name", text: $newExcludedApplication)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addExcludedApplication)

                    Button("Add", action: addExcludedApplication)
                        .disabled(
                            newExcludedApplication
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                }

                if model.preferences.excludedApplications.isEmpty {
                    Text("No applications are excluded from summaries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.preferences.excludedApplications, id: \.self) { application in
                        HStack {
                            Label(application, systemImage: "app.dashed")
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") {
                                model.removeExcludedApplication(application)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .accessibilityIdentifier("settings.excluded-applications")

            Label(
                "Continue never switches apps or reopens items automatically.",
                systemImage: "hand.raised"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func addExcludedApplication() {
        model.addExcludedApplication(newExcludedApplication)
        newExcludedApplication = ""
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
            "Checking"
        case .recording:
            "On"
        case .paused:
            "Paused"
        case let .unavailable(reason):
            "Off · \(reason)"
        }
    }

    private var notificationStatusIcon: String {
        switch model.notificationAuthorization {
        case .checking:
            "arrow.triangle.2.circlepath"
        case .notDetermined:
            "bell.badge"
        case .enabled:
            "checkmark.circle.fill"
        case .denied:
            "bell.slash"
        }
    }

    private var notificationStatusText: String {
        switch model.notificationAuthorization {
        case .checking:
            "Checking"
        case .notDetermined:
            "Not enabled"
        case .enabled:
            "Enabled"
        case .denied:
            "Disabled"
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
