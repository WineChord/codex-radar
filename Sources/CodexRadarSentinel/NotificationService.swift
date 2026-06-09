import CodexRadarCore
import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
    }

    func requestAuthorization() {
        guard let center = notificationCenter else {
            return
        }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ event: NotificationEvent, soundEnabled: Bool) {
        guard let center = notificationCenter else {
            return
        }
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
        center.add(request)
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

    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }
}
