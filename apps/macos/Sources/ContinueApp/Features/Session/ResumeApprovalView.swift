import ContinueCore
import SwiftUI

struct ResumeApprovalView: View {
    @ObservedObject var model: AppModel
    let preview: ResumePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            targetList
            Divider()
            footer
        }
        .frame(width: 580, height: 520)
        .interactiveDismissDisabled(model.isResuming)
        .accessibilityIdentifier("resume.approval-sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.title2)
                    .foregroundStyle(ContinueTheme.accent)
                    .accessibilityHidden(true)

                Text("Reopen a missing item")
                    .font(.title2.weight(.semibold))
            }

            Text("Continue cannot tell whether every browser tab or file is still open. Nothing is selected, and nothing opens until you choose an item and confirm.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = model.resumeErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
    }

    private var targetList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(preview.targets) { target in
                    targetRow(target)
                }

                ForEach(model.resumeResults) { result in
                    resultRow(result)
                }
            }
            .padding(20)
        }
    }

    private func targetRow(_ target: ResumeTarget) -> some View {
        Toggle(
            isOn: Binding(
                get: { model.resumeSelection.contains(target.id) },
                set: { _ in model.toggleResumeTarget(target.id) }
            )
        ) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(for: target.kind))
                    .frame(width: 22)
                    .foregroundStyle(ContinueTheme.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.title)
                        .font(.body.weight(.medium))
                    Text(target.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(target.locator)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!model.resumeResults.isEmpty)
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resultRow(_ result: ResumeResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: resultIcon(result.outcome))
                .foregroundStyle(resultColor(result.outcome))
                .accessibilityHidden(true)
            Text(resultMessage(result))
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack {
            Label("Your current app stays in place", systemImage: "hand.raised")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if model.resumeResults.isEmpty {
                Button("Cancel") {
                    model.dismissResumeReview()
                }
                .disabled(model.isResuming)

                Button {
                    model.confirmResume()
                } label: {
                    if model.isResuming {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Open selected")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ContinueTheme.accent)
                .disabled(model.resumeSelection.selectedIDs.isEmpty || model.isResuming)
                .accessibilityIdentifier("resume.confirm")
            } else {
                Button("Done") {
                    model.dismissResumeReview()
                }
                .buttonStyle(.borderedProminent)
                .tint(ContinueTheme.accent)
            }
        }
        .padding(20)
    }

    private func icon(for kind: ResumeTargetKind) -> String {
        switch kind {
        case .application:
            "app.dashed"
        case .file:
            "doc"
        case .url:
            "safari"
        }
    }

    private func resultIcon(_ outcome: ResumeOutcome) -> String {
        switch outcome {
        case .opened:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        }
    }

    private func resultColor(_ outcome: ResumeOutcome) -> Color {
        switch outcome {
        case .opened:
            ContinueTheme.success
        case .failed:
            .red
        }
    }

    private func resultMessage(_ result: ResumeResult) -> String {
        switch result.outcome {
        case .opened:
            "Opened \(result.target.title)"
        case let .failed(message):
            "Could not open \(result.target.title): \(message)"
        }
    }
}
