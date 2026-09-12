import ContinueCore
import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable {
    case now = "Now"
    case history = "History"
    case settings = "Settings"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .now:
            "sparkles"
        case .history:
            "clock.arrow.circlepath"
        case .settings:
            "gearshape"
        }
    }
}

struct AppShellView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppDestination? = .now

    var body: some View {
        NavigationSplitView {
            List(AppDestination.allCases, selection: $selection) { destination in
                Label(destination.rawValue, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            destinationView
        }
        .navigationTitle(selection?.rawValue ?? "Continue")
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch selection ?? .now {
        case .now:
            NowView(model: model)
        case .history:
            PlaceholderView(
                title: "History",
                message: "Past work checkpoints will appear here.",
                systemImage: "clock.arrow.circlepath"
            )
        case .settings:
            PlaceholderView(
                title: "Settings",
                message: "Capture, voice, and privacy controls will appear here.",
                systemImage: "gearshape"
            )
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(message)
        )
    }
}
