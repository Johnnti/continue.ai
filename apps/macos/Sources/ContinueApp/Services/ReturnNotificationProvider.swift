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
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) == true
    }

    func notifyReturnSummaryReady() async {
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
}
