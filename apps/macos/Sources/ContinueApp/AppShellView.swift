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
                    .accessibilityIdentifier("navigation.\(destination.rawValue.lowercased())")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            destinationView
        }
        .navigationTitle(selection?.rawValue ?? "Continue")
        .task {
            model.startMonitoring()
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch selection ?? .now {
        case .now:
            NowView(model: model)
        case .history:
            HistoryView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }
}
