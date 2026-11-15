import Foundation

/// Абстракция над планировщиком уведомлений.
/// На Этапе 2 (до Этапа 5) используется заглушка, чтобы `TaskManager` мог дёргать
/// отмену/перепланирование без привязки к `UNUserNotificationCenter`.
public protocol NotificationScheduling: Sendable {
    func schedule(_ request: NotificationRequest) async throws
    func cancel(ids: [String]) async
    func cancelAll() async
    func pendingRequests() async -> [NotificationRequest]
}

/// Запрос уведомления, передаваемый планировщику.
public struct NotificationRequest: Sendable, Equatable {
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String
    public let generation: Int
    public let repeatIndex: Int

    public init(id: String, fireDate: Date, title: String, body: String, generation: Int, repeatIndex: Int) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.generation = generation
        self.repeatIndex = repeatIndex
    }
}

/// Заглушка, которая просто хранит запросы в памяти. Используется в тестах и по умолчанию.
public actor InMemoryNotificationScheduler: NotificationScheduling {
    private var store: [NotificationRequest] = []

    public init() {}

    public func schedule(_ request: NotificationRequest) async throws {
        store.append(request)
    }

    public func cancel(ids: [String]) async {
        store.removeAll { ids.contains($0.id) }
    }

    public func cancelAll() async {
        store.removeAll()
    }

    public func pendingRequests() async -> [NotificationRequest] {
        store
    }
}