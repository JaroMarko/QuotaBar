import Foundation
import QuotaBarCore
import UserNotifications

actor NotificationService {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
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
