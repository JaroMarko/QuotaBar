import Foundation
import QuotaBarCore
import UserNotifications

actor NotificationService {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func testRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "QuotaBar test notification"
        content.body = "This is a preview. Your usage limits have not changed."
        content.sound = .default
        return UNNotificationRequest(identifier: "test-" + UUID().uuidString, content: content, trigger: nil)
    }

    func sendTest() async -> String {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                return "Notifications are disabled. Enable QuotaBar in System Settings → Notifications."
            }
            try await center.add(Self.testRequest())
            return "Sent to macOS. If no banner appears, check Notifications and Focus settings."
        } catch {
            return "Test notification failed: \(error.localizedDescription)"
        }
    }

    func send(_ alert: UsageAlert) async {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch alert.kind {
        case .threshold:
            let threshold = alert.threshold ?? 0
            content.title = "\(alert.provider.displayName) usage reached \(threshold)%"
            content.body = "\(alert.windowName) has \(100 - threshold)% remaining."
        case .reset:
            content.title = "\(alert.provider.displayName) usage reset"
            content.body = "\(alert.windowName) is available again."
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
