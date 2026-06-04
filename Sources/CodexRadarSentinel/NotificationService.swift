import CodexRadarCore
import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ event: NotificationEvent, soundEnabled: Bool) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = soundEnabled && event.severity != .passive ? .default : nil
        if #available(macOS 12.0, *) {
            switch event.severity {
            case .passive:
                content.interruptionLevel = .passive
            case .active:
                content.interruptionLevel = .active
            case .urgent:
                content.interruptionLevel = .timeSensitive
            }
        }
        let request = UNNotificationRequest(
            identifier: event.identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.sound == nil {
            return [.banner]
        }
        return [.banner, .sound]
    }
}
