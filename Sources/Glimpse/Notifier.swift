import Foundation
import UserNotifications
import AppKit

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()

    func setup() {
        center.delegate = self
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // best-effort; macOS shows the prompt or silently denies for unsigned apps
        }
    }

    func notify(id: String, title: String, body: String, url: URL?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url = url {
            content.userInfo = ["url": url.absoluteString]
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request) { _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let str = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: str) {
            await Task { @MainActor in
                NSWorkspace.shared.open(url)
            }.value
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
