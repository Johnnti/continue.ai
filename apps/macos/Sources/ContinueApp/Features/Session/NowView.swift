import ContinueCore
import SwiftUI

struct NowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appHeader
                CaptureStatusStrip(snapshot: model.runtime)
                VoiceBriefingPanel(model: model)
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
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(ContinueTheme.accent)
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
                onReviewResume: model.prepareResume
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

private struct VoiceBriefingPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 20) {
            WaveformView(
                state: displayState,
                levels: model.voice.levels
            )
            .frame(maxWidth: 300)

            VStack(alignment: .leading, spacing: 5) {
                Text("Voice briefing")
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
                    model.stopVoiceBriefing()
                } else {
                    model.startVoiceBriefing()
                }
            }
            .buttonStyle(.bordered)
            .disabled(
                !model.preferences.voiceBriefingsEnabled
                    || model.isVoiceTransitioning
                    || model.checkpoint == nil
            )
            .accessibilityIdentifier("voice.toggle-briefing")
        }
        .padding(16)
        .background(ContinueTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.primary.opacity(0.08))
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
        return isActive ? "Stop" : "Hear briefing"
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
            "Ready when you are"
        case .connecting:
            "Connecting…"
        case .listening:
            "Listening"
        case .thinking:
            "Preparing a response"
        case .speaking:
            "Speaking your checkpoint"
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            Text(snapshot.statusMessage)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(phaseLabel)
                .font(.caption.weight(.semibold))
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
        case .available:
            "checkmark.circle.fill"
        case .unavailable:
            "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch snapshot.captureStatus {
        case .checking:
            .secondary
        case .available:
            ContinueTheme.success
        case .unavailable:
            .orange
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
    let onReviewResume: () -> Void

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

            HStack {
                Text("Nothing opens until you review and confirm it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onReviewResume()
                } label: {
                    if isPreparingResume {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Review & resume", systemImage: "arrow.up.forward.app")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ContinueTheme.accent)
                .disabled(isPreparingResume || checkpoint.resumeTargets.isEmpty)
                .accessibilityLabel(isPreparingResume ? "Preparing resume review" : "Review and resume")
                .accessibilityIdentifier("resume.review")
                .keyboardShortcut("r", modifiers: [.command, .shift])
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
