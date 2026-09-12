import ContinueCore
import SwiftUI

struct CheckpointSidebar: View {
    @ObservedObject var model: AppModel
    @Binding var selection: AppDestination?
    @Binding var isHistoryExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Button {
                        selection = .now
                    } label: {
                        Label("Conversation", systemImage: "waveform.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .listRowBackground(selection == .now ? ContinueTheme.accent.opacity(0.14) : .clear)
                    .accessibilityIdentifier("navigation.conversation")
                }

                Section {
                    DisclosureGroup(isExpanded: $isHistoryExpanded) {
                        if model.history.isEmpty {
                            Text("No checkpoints yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(model.history.prefix(7)) { checkpoint in
                                Button {
                                    selection = .history
                                } label: {
                                    SidebarCheckpointRow(checkpoint: checkpoint)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .listRowSeparator(.hidden)
                                .accessibilityIdentifier("navigation.checkpoint.\(checkpoint.id)")
                            }

                            if model.history.count > 7 {
                                Button {
                                    selection = .history
                                } label: {
                                    Label("See all checkpoints", systemImage: "arrow.up.right")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier("navigation.all-checkpoints")
                            }
                        }
                    } label: {
                        Label("Checkpoint history", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("navigation.checkpoint-history")
                }
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SidebarStatusRow(
                    title: "Screenpipe",
                    value: captureValue,
                    systemImage: captureIcon,
                    tint: captureTint
                )
                SidebarStatusRow(
                    title: "Continue summaries",
                    value: model.preferences.interpretationEnabled ? "On" : "Paused",
                    systemImage: model.preferences.interpretationEnabled ? "sparkles" : "pause.circle",
                    tint: model.preferences.interpretationEnabled ? ContinueTheme.accent : .secondary
                )

                Button {
                    selection = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("navigation.settings")
            }
            .padding(12)
        }
        .accessibilityIdentifier("navigation.sidebar")
    }

    private var captureValue: String {
        switch model.runtime.captureStatus {
        case .checking:
            "Checking"
        case .recording:
            "Recording"
        case .paused:
            "Paused"
        case .unavailable:
            "Unavailable"
        }
    }

    private var captureIcon: String {
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

    private var captureTint: Color {
        switch model.runtime.captureStatus {
        case .checking, .paused:
            .secondary
        case .recording:
            ContinueTheme.success
        case .unavailable:
            .orange
        }
    }
}

private struct SidebarCheckpointRow: View {
    let checkpoint: Checkpoint

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(confidenceTint)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(checkpoint.headline)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(checkpoint.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checkpoint: \(checkpoint.headline)")
        .accessibilityValue(checkpoint.createdAt.formatted(date: .abbreviated, time: .omitted))
    }

    private var confidenceTint: Color {
        switch checkpoint.confidence {
        case .high:
            ContinueTheme.success
        case .medium:
            .orange
        case .low:
            .secondary
        }
    }
}

private struct SidebarStatusRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 15)
                .accessibilityHidden(true)

            Text(title)
                .font(.caption)

            Spacer(minLength: 4)

            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
