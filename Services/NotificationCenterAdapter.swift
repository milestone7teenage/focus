import Foundation
import UserNotifications

/// Протокол-адаптер над `UNUserNotificationCenter` для тестируемости.
/// Реализация для продакшена оборачивает `UNUserNotificationCenter.current()`,
/// для тестов — `FakeNotificationCenterAdapter`.
public protocol NotificationCenterAdapter: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func getNotificationCategories() async -> Set<UNNotificationCategory>
}