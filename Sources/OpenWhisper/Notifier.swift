import Foundation
import UserNotifications

@MainActor
protocol NotificationDispatching: AnyObject {
    func ensureAuthorization()
    func notify(title: String, body: String)
}

@MainActor
final class Notifier: NotificationDispatching {
    private var didRequestAuthorization = false

    func ensureAuthorization() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
