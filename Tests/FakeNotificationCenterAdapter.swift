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

    // Return a lightweight settings struct instead of calling real UNUserNotificationCenter
    public func getNotificationSettings() async -> UNNotificationSettings {
        lock.lock()
        let status = _authorizationStatus
        lock.unlock()

        // Create a mock settings object with our controlled authorization status
        return MockNotificationSettings(authorizationStatus: status)
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

// Mock UNNotificationSettings since it is not constructible directly.
private final class MockNotificationSettings: UNNotificationSettings {
    private let _authorizationStatus: UNAuthorizationStatus

    init(authorizationStatus: UNAuthorizationStatus) {
        self._authorizationStatus = authorizationStatus
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var authorizationStatus: UNAuthorizationStatus {
        _authorizationStatus
    }
}