import ContinueCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Checkpoint history")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Return summaries are ordered from newest to oldest.")
                        .foregroundStyle(.secondary)
                }

                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ContinueTheme.canvas)
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.historyErrorMessage {
            ContentUnavailableView {
                Label("History unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") {
                    model.retry()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if model.isLoading, model.history.isEmpty {
            ProgressView("Loading checkpoint history…")
                .frame(maxWidth: .infinity, minHeight: 280)
        } else if model.history.isEmpty {
            ContentUnavailableView(
                "No history yet",
                systemImage: "clock",
                description: Text("Completed work sessions will appear here after the first return checkpoint.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(model.history) { checkpoint in
                    HistoryCard(checkpoint: checkpoint)
                }
            }
        }
    }
}

private struct HistoryCard: View {
    let checkpoint: Checkpoint

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(ContinueTheme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(checkpoint.headline)
                        .font(.headline)
                    Spacer()
                    Text(checkpoint.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(checkpoint.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 14) {
                    Label("\(checkpoint.awayDurationMinutes) min away", systemImage: "moon.zzz")
                    Label("\(checkpoint.nextSteps.count) next", systemImage: "arrow.right.circle")
                    Text("\(checkpoint.confidence.rawValue.capitalized) confidence")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(ContinueTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(.primary.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
    }
}
