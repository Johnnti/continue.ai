import ContinueCore
import SwiftUI

struct NowView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isEditingNextStep = false
    @State private var editedNextStep = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appHeader
                CaptureStatusStrip(
                    snapshot: model.runtime,
                    summariesEnabled: model.preferences.interpretationEnabled
                )
                VoiceConversationPanel(model: model)
                content
                PrivacyNotice()
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ContinueTheme.canvas)
        .accessibilityIdentifier("now.screen")
        .sheet(
            isPresented: Binding(
                get: { model.resumePreview != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissResumeReview()
                    }
                }
            )
        ) {
            if let preview = model.resumePreview {
                ResumeApprovalView(model: model, preview: preview)
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    model.retry()
                }
                .disabled(model.isLoading)
                .help("Refresh the latest checkpoint")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private var appHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            IridescenceView(
                level: 0.22,
                tint: SIMD3<Float>(0.30, 0.62, 1.0),
                isAnimated: true
            )
            .frame(width: 36, height: 36)
            .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Continue")
                    .font(.headline)
                Text("Local-first context resume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("PREVIEW DATA")
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.secondary.opacity(0.10), in: Capsule())
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading, model.checkpoint == nil {
            loadingState
        } else if let errorMessage = model.errorMessage {
            errorState(errorMessage)
        } else if let checkpoint = model.checkpoint {
            CheckpointCard(
                checkpoint: checkpoint,
                isPreparingResume: model.isPreparingResume,
                resumeErrorMessage: model.resumeErrorMessage,
                onDone: {
                    model.stopVoiceConversation()
                    dismissWindow(id: "main")
                },
                onEditNextStep: {
                    editedNextStep = checkpoint.nextSteps.first ?? ""
                    isEditingNextStep = true
                },
                onDismiss: model.dismissCheckpoint,
                onReopenMissingItem: model.prepareResume
            )
        } else {
            emptyState
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your latest checkpoint…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("now.capture-status")
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Checkpoint unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") {
                model.retry()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No checkpoint yet",
            systemImage: "moon.zzz",
            description: Text("Continue will prepare a checkpoint after it detects a meaningful work session and time away.")
        )
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

private struct VoiceConversationPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 20) {
            WaveformView(
                state: displayState,
                levels: model.voice.levels
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Voice conversation")
                    .font(.subheadline.weight(.semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = model.voiceErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            Button(buttonTitle, systemImage: buttonIcon) {
                if isActive {
                    model.stopVoiceConversation()
                } else {
                    model.startVoiceConversation()
                }
            }
            .buttonStyle(.bordered)
            .disabled(
                !model.preferences.voiceBriefingsEnabled
                    || model.isVoiceTransitioning
                    || (!isActive && model.checkpoint == nil)
            )
            .accessibilityIdentifier("voice.toggle-conversation")
        }
    }

    private var isActive: Bool {
        switch displayState {
        case .connecting, .listening, .thinking, .speaking:
            true
        case .disconnected, .muted, .failed:
            false
        }
    }

    private var buttonTitle: String {
        guard model.preferences.voiceBriefingsEnabled else { return "Disabled" }
        return isActive ? "End" : "Start conversation"
    }

    private var buttonIcon: String {
        guard model.preferences.voiceBriefingsEnabled else { return "speaker.slash" }
        return isActive ? "stop.fill" : "play.fill"
    }

    private var statusText: String {
        guard model.preferences.voiceBriefingsEnabled else {
            return "Disabled in Settings"
        }

        return switch displayState {
        case .disconnected:
            "Ask what you were doing or what comes next"
        case .connecting:
            "Connecting…"
        case .listening:
            "Listening"
        case .thinking:
            "Thinking"
        case .speaking:
            "Responding"
        case .muted:
            "Microphone muted"
        case let .failed(message):
            message
        }
    }

    private var displayState: VoiceState {
        model.preferences.voiceBriefingsEnabled ? model.voice.state : .muted
    }
}

private struct CaptureStatusStrip: View {
    let snapshot: RuntimeSnapshot
    let summariesEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 18) {
                Label("Screenpipe recording: \(captureLabel)", systemImage: statusIcon)
                    .foregroundStyle(statusColor)

                Divider()
                    .frame(height: 16)

                Label(
                    "Continue summaries: \(summariesEnabled ? "On" : "Paused")",
                    systemImage: summariesEnabled ? "sparkles" : "pause.circle"
                )
                .foregroundStyle(summariesEnabled ? ContinueTheme.accent : .secondary)

                Spacer()

                Text(phaseLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))

            Text(snapshot.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.primary.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch snapshot.captureStatus {
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

    private var statusColor: Color {
        switch snapshot.captureStatus {
        case .checking:
            .secondary
        case .recording:
            ContinueTheme.success
        case .paused:
            .secondary
        case .unavailable:
            .orange
        }
    }

    private var captureLabel: String {
        switch snapshot.captureStatus {
        case .checking:
            "Checking"
        case .recording:
            "On"
        case .paused:
            "Paused"
        case .unavailable:
            "Off"
        }
    }

    private var phaseLabel: String {
        switch snapshot.phase {
        case .booting:
            "Starting"
        case .observing:
            "Observing"
        case .away:
            "Away"
        case .returning:
            "Welcome back"
        }
    }
}

private struct CheckpointCard: View {
    let checkpoint: Checkpoint
    let isPreparingResume: Bool
    let resumeErrorMessage: String?
    let onDone: () -> Void
    let onEditNextStep: () -> Void
    let onDismiss: () -> Void
    let onReopenMissingItem: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("WELCOME BACK")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(ContinueTheme.accent)

                Text(checkpoint.headline)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .textSelection(.enabled)

                Text("You were away for \(checkpoint.awayDurationMinutes) minutes · saved \(checkpoint.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(checkpoint.summary)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(4)
                .textSelection(.enabled)

            Divider()

            HStack(alignment: .top, spacing: 28) {
                CheckpointList(
                    title: "Completed",
                    systemImage: "checkmark.circle",
                    items: checkpoint.completed
                )

                CheckpointList(
                    title: "Next",
                    systemImage: "arrow.right.circle",
                    items: checkpoint.nextSteps
                )
            }

            if let evidence = checkpoint.evidence.first {
                Label(
                    "Based on \(evidence.sourceLabel) · \(checkpoint.confidence.rawValue.capitalized) confidence",
                    systemImage: "doc.text.magnifyingglass"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "Source: \(evidence.sourceLabel). \(checkpoint.confidence.rawValue) confidence."
                )
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Continue leaves your current app and windows unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done", systemImage: "checkmark") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(ContinueTheme.accent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("checkpoint.done")
            }

            HStack(spacing: 10) {
                Button("Edit next step", systemImage: "pencil") {
                    onEditNextStep()
                }
                .buttonStyle(.bordered)

                Button {
                    onReopenMissingItem()
                } label: {
                    if isPreparingResume {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Something closed?", systemImage: "plus.square.on.square")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isPreparingResume || checkpoint.resumeTargets.isEmpty)
                .accessibilityLabel(
                    isPreparingResume ? "Preparing missing-item review" : "Reopen a missing item"
                )
                .accessibilityIdentifier("resume.review")

                Spacer()

                Button("Dismiss summary", systemImage: "xmark") {
                    onDismiss()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if let resumeErrorMessage {
                Label(resumeErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(28)
        .background(ContinueTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.primary.opacity(0.09))
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct EditNextStepView: View {
    @Binding var nextStep: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Correct the next step")
                    .font(.title2.weight(.semibold))
                Text("Use the action you actually want to resume. This correction stays in the local app session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $nextStep)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.primary.opacity(0.10))
                }
                .frame(minHeight: 110)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(ContinueTheme.accent)
                .disabled(nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 270)
    }
}

private struct CheckpointList: View {
    let title: String
    let systemImage: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(ContinueTheme.accent.opacity(0.75))
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrivacyNotice: View {
    var body: some View {
        Label(
            "Screenpipe keeps raw activity local. Continue stores interpreted checkpoints, not screenshots or microphone audio.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
