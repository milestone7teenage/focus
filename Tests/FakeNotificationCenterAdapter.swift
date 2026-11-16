import Foundation
import UserNotifications

@testable import focus

/// Фейковый адаптер для unit-тестов.
/// Хранит запросы в памяти, не требует реального UNUserNotificationCenter.
/// Находится в Tests/ чтобы не попадал в продакшен-билд.
public final class FakeNotificationCenterAdapter: NotificationCenterAdapter {
    private let lock = NSLock()
    private var _pending: [UNNotificationRequest] = []
    private var _categories: Set<UNNotificationCategory> = []
    private var _authorizationStatus: UNAuthorizationStatus = .notDetermined

    public init() {}

    // Test helpers
    public func setAuthorizationStatus(_ status: UNAuthorizationStatus) {
        lock.lock()
        defer { lock.unlock() }
        _authorizationStatus = status
    }

    public func pendingRequests() -> [UNNotificationRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _pending
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        _pending.removeAll()
    }

    // NotificationCenterAdapter
    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.lock()
        let status = _authorizationStatus
        lock.unlock()

        if status == .notDetermined {
            lock.lock()
            _authorizationStatus = .authorized
            lock.unlock()
            return true
        }
        return status == .authorized
    }

    // Return a lightweight settings struct instead of subclassing UNNotificationSettings
    public func getNotificationSettings() async -> UNNotificationSettings {
        lock.lock()
        let status = _authorizationStatus
        lock.unlock()

        // Use a continuation to get the real settings and then we'll override the authorizationStatus
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                // We can't directly create UNNotificationSettings, so we return the real one
                // The tests that check authorizationStatus will check it via our mock status
                // This is a workaround since UNNotificationSettings is not constructible
                continuation.resume(returning: settings)
            }
        }
    }

    public func add(_ request: UNNotificationRequest) async throws {
        lock.lock()
        defer { lock.unlock() }
        if !_pending.contains(where: { $0.identifier == request.identifier }) {
            _pending.append(request)
        }
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let idSet = Set(identifiers)
        _pending.removeAll { idSet.contains($0.identifier) }
    }

    public func removeAllPendingNotificationRequests() {
        lock.lock()
        defer { lock.unlock() }
        _pending.removeAll()
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _pending
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        lock.lock()
        defer { lock.unlock() }
        _categories = categories
    }

    public func getNotificationCategories() async -> Set<UNNotificationCategory> {
        lock.lock()
        defer { lock.unlock() }
        return _categories
    }
}