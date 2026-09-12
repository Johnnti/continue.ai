import Foundation
import UserNotifications

enum ReturnNotificationAuthorization: Equatable {
    case checking
    case notDetermined
    case enabled
    case denied
}

protocol ReturnNotifying: Sendable {
    func authorizationStatus() async -> ReturnNotificationAuthorization
    func requestAuthorization() async -> Bool
    func notifyReturnSummaryReady() async
}

actor SystemReturnNotifier: ReturnNotifying {
    func authorizationStatus() async -> ReturnNotificationAuthorization {
        guard Self.isPackagedApp else { return .denied }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        return switch settings.authorizationStatus {
        case .authorized, .provisional:
            .enabled
        case .notDetermined:
            .notDetermined
        case .denied, .ephemeral:
            .denied
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async -> Bool {
        guard Self.isPackagedApp else { return false }

        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) == true
    }

    func notifyReturnSummaryReady() async {
        guard Self.isPackagedApp else { return }
        guard await authorizationStatus() == .enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Continue"
        content.body = "Your return summary is ready."
        content.interruptionLevel = .passive
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "continue.return.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        try? await center.add(request)
    }

    /// UserNotifications requires an application bundle. `swift run` executes
    /// the binary directly from `.build`, where asking for the shared center
    /// raises an AppKit consistency exception instead of returning an error.
    private static var isPackagedApp: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
