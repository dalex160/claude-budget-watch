import Foundation
import UserNotifications
import BudgetGuardCore

/// Posts the threshold alerts. Every call is a no-op when running unbundled (`swift run`),
/// where UNUserNotificationCenter would throw.
final class Notifier {
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Explicit user action only (« Activer les alertes »); never called automatically.
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus? {
        guard let center else { return nil }
        return await center.notificationSettings().authorizationStatus
    }

    func isAuthorized() async -> Bool {
        let status = await authorizationStatus()
        return status == .authorized || status == .provisional
    }

    func post(threshold: Int, percent: Int) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Budget Guard"
        content.body = Copy.alertBody(threshold: threshold, percent: percent)
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "alert.\(threshold)", content: content, trigger: nil))
    }
}
