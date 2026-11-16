@preconcurrency import Foundation
@preconcurrency import UserNotifications

/// Продакшен-адаптер над `UNUserNotificationCenter.current()`.
public final class RealNotificationCenterAdapter: NotificationCenterAdapter, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeAllPendingNotificationRequests() {
        center.removeAllPendingNotificationRequests()
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    public func getNotificationCategories() async -> Set<UNNotificationCategory> {
        await withCheckedContinuation { continuation in
            center.getNotificationCategories { categories in
                continuation.resume(returning: categories)
            }
        }
    }
}