import Foundation
import QuillCore
import UserNotifications

@MainActor
final class SystemNotifier: Notifier {
    var onNeedsAPIKey: @MainActor () -> Void = {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(_ notice: Notice) {
        if notice == .needsAPIKey {
            onNeedsAPIKey()
        }
        let content = UNMutableNotificationContent()
        content.title = "Quill"
        content.body = notice.message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
