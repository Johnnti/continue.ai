import ContinueCore
import SwiftUI

struct NowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appHeader
                CaptureStatusStrip(snapshot: model.runtime)
                content
                PrivacyNotice()
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ContinueTheme.canvas)
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    model.retry()
                }
                .disabled(model.isLoading)
                .help("Refresh the latest checkpoint")
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
            CheckpointCard(checkpoint: checkpoint)
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
