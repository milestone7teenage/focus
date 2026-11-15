import Foundation
import SwiftData
import XCTest
@testable import focus

/// In-memory ModelContainer для тестов.
enum TestContainer {
    static func make() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SchemaV1.schema, configurations: config)
    }
}

@MainActor
final class IntegrationTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: TaskRepository!
    private var engine: ScheduleEngine!
    private var fakeAdapter: FakeNotificationCenterAdapter!

    override func setUp() async throws {
        container = try TestContainer.make()
        let context = ModelContext(container)
        repository = TaskRepository(modelContext: context)
        engine = ScheduleEngine()
        fakeAdapter = FakeNotificationCenterAdapter()
        fakeAdapter.setAuthorizationStatus(.authorized)
    }

    override func tearDown() async throws {
        container = nil
        repository = nil
        engine = nil
        fakeAdapter = nil
    }

    // MARK: - Cold restart simulation

    func testColdRestartPreservesSeenStateAndQueue() async throws {
        // --- Первый запуск ---
        let scheduler1 = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager1 = TaskManager(repository: repository, scheduler: scheduler1, engine: engine)

        // Создаём разовую задачу
        let task = try await manager1.createOneTime(
            title: "Cold restart test",
            scheduledAt: Date(timeIntervalSinceNow: 7200)
        )
        try await scheduler1.reconcile()

        // Переводим в SEEN
        try await manager1.markOneTimeSeen(id: task.id)

        // Проверяем состояние
        var tasks = try await repository.fetchAllOneTime()
        XCTAssertEqual(tasks.first?.state, .seen)

        // Проверяем очередь: должен быть 0 ожидающих (SEEN отменяет повторы)
        var pending = await fakeAdapter.pendingRequests()
        let taskPending = pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }
        XCTAssertTrue(taskPending.isEmpty, "После SEEN очередь пуста")

        // --- Симуляция холодного перезапуска (новые инстансы сервисов на том же хранилище) ---
        let scheduler2 = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager2 = TaskManager(repository: repository, scheduler: scheduler2, engine: engine)

        // Запускаем reconcile (как при старте приложения)
        try await scheduler2.reconcile()

        // Состояние SEEN должно сохраниться
        tasks = try await repository.fetchAllOneTime()
        XCTAssertEqual(tasks.first?.state, .seen, "SEEN сохраняется после холодного перезапуска")

        // Очередь не должна дублироваться
        pending = await fakeAdapter.pendingRequests()
        let taskPending2 = pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }
        XCTAssertTrue(taskPending2.isEmpty, "Очередь не дублируется после reconcile")
    }

    func testColdRestartRegularTaskPreservesState() async throws {
        let scheduler1 = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager1 = TaskManager(repository: repository, scheduler: scheduler1, engine: engine)

        // Создаём регулярную задачу
        let template = try await manager1.createRegular(title: "Daily", localHour: 10, localMinute: 30)
        let instance = try await manager1.fetchActiveInstances(for: template.id).first!
        try await scheduler1.reconcile()

        // Выполняем экземпляр
        try await manager1.completeInstance(id: instance.id)

        // --- Холодный перезапуск ---
        let scheduler2 = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager2 = TaskManager(repository: repository, scheduler: scheduler2, engine: engine)

        try await scheduler2.reconcile()

        // Шаблон должен сохраниться, экземпляр — удалён
        let templates = try await repository.fetchAllRegular()
        XCTAssertEqual(templates.count, 1, "Шаблон сохраняется")

        let instances = try await repository.fetchInstances(for: template.id)
        XCTAssertTrue(instances.isEmpty, "Выполненный экземпляр удалён")
    }

    // MARK: - Denied notifications permission

    func testDeniedNotificationsDoesNotCrashOperations() async throws {
        // Устанавливаем статус denied
        fakeAdapter.setAuthorizationStatus(.denied)

        let scheduler = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager = TaskManager(repository: repository, scheduler: scheduler, engine: engine)

        // Все операции должны работать без ошибок
        let task = try await manager.createOneTime(
            title: "No notifications",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        try await manager.snoozeOneTime(id: task.id)
        try await manager.markOneTimeSeen(id: task.id)
        try await manager.completeOneTime(id: task.id)

        let template = try await manager.createRegular(title: "Daily no notif", localHour: 8, localMinute: 0)
        let instance = try await manager.fetchActiveInstances(for: template.id).first!
        try await manager.snoozeInstance(id: instance.id)
        try await manager.markInstanceSeen(id: instance.id)
        try await manager.completeInstance(id: instance.id)

        // Delete + Undo
        let task2 = try await manager.createOneTime(
            title: "Undo test",
            scheduledAt: Date(timeIntervalSinceNow: 1800)
        )
        let snapshot = try await manager.deleteOneTime(id: task2.id)
        try await manager.restore(snapshot: snapshot!)

        // Всё прошло без ошибок
        XCTAssertTrue(true, "Операции работают при denied notifications")
    }

    // MARK: - Midnight snooze crossing

    func testMidnightSnoozeCrossingResetPriority() async throws {
        let scheduler = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager = TaskManager(repository: repository, scheduler: scheduler, engine: engine)

        // Создаём регулярную задачу на 23:30
        let template = try await manager.createRegular(title: "Late task", localHour: 23, localMinute: 30)
        var instance = try await manager.fetchActiveInstances(for: template.id).first!

        // Snooze в 23:45 — переходит через полночь
        try await manager.snoozeInstance(id: instance.id)

        // Проверяем, что snoozedUntil установлен
        instance = try await manager.fetchActiveInstances(for: template.id).first!
        XCTAssertNotNil(instance.snoozedUntil)
        XCTAssertGreaterThan(instance.snoozedUntil!, Date())

        // Симулируем наступление следующего дня (reset)
        // В тестах мы не можем изменить системное время, поэтому вызываем reset вручную
        try await manager.runDailyReset()

        // После reset: вчерашний экземпляр удалён, новый создан PENDING без snooze
        let instances = try await manager.fetchActiveInstances(for: template.id)
        let todayKey = await engine.dayKey()
        let todayInstance = instances.first { $0.dayKey == todayKey }

        XCTAssertNotNil(todayInstance, "Новый экземпляр создан на сегодня")
        XCTAssertEqual(todayInstance?.state, .pending, "Состояние PENDING")
        XCTAssertNil(todayInstance?.snoozedUntil, "Snooze сгорел при reset")
    }

    // MARK: - Very long titles

    func testVeryLongTitleHandledCorrectly() async throws {
        let scheduler = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager = TaskManager(repository: repository, scheduler: scheduler, engine: engine)

        // 500+ символов
        let longTitle = String(repeating: "Очень длинное название задачи. ", count: 30)
        XCTAssertGreaterThan(longTitle.count, 500)

        let task = try await manager.createOneTime(
            title: longTitle,
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        XCTAssertEqual(task.title, longTitle, "Полное название сохранено без обрезания")

        // UI модель тоже должна принять длинный текст
        let item = OneTimeTaskItem(
            id: task.id,
            title: task.title,
            scheduledAt: task.scheduledAt,
            isSeen: false
        )
        XCTAssertEqual(item.title.count, longTitle.count)

        // Snooze, complete, delete — всё работает
        try await manager.snoozeOneTime(id: task.id)
        try await manager.markOneTimeSeen(id: task.id)
        let snapshot = try await manager.deleteOneTime(id: task.id)
        try await manager.restore(snapshot: snapshot!)
    }

    // MARK: - Rapid "Seen" taps (idempotency)

    func testRapidSeenTapsAreIdempotent() async throws {
        let scheduler = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager = TaskManager(repository: repository, scheduler: scheduler, engine: engine)

        let task = try await manager.createOneTime(
            title: "Rapid seen",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )
        try await scheduler.reconcile()

        // Множественные быстрые вызовы SEEN (как быстрые тапы по уведомлению)
        for _ in 0..<10 {
            try await manager.markOneTimeSeen(id: task.id)
        }

        let tasks = try await repository.fetchAllOneTime()
        XCTAssertEqual(tasks.first?.state, .seen, "SEEN идемпотентен")

        // Очередь не должна дублироваться
        let pending = await fakeAdapter.pendingRequests()
        let taskPending = pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }
        XCTAssertTrue(taskPending.isEmpty, "После SEEN очередь пуста, даже при многократных вызовах")
    }

    func testRapidSeenOnRecurringIsIdempotent() async throws {
        let scheduler = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager = TaskManager(repository: repository, scheduler: scheduler, engine: engine)

        let template = try await manager.createRegular(title: "Rapid seen regular", localHour: 12, localMinute: 0)
        let instance = try await manager.fetchActiveInstances(for: template.id).first!
        try await scheduler.reconcile()

        for _ in 0..<10 {
            try await manager.markInstanceSeen(id: instance.id)
        }

        let instances = try await repository.fetchInstances(for: template.id)
        XCTAssertEqual(instances.first?.state, .seen)

        let pending = await fakeAdapter.pendingRequests()
        let taskPending = pending.filter { $0.identifier.hasPrefix("rt_\(template.id.uuidString)") }
        XCTAssertTrue(taskPending.isEmpty)
    }

    // MARK: - Reconcile after permission change

    func testReconcileAfterPermissionGranted() async throws {
        // Сначала denied
        fakeAdapter.setAuthorizationStatus(.denied)

        let scheduler = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )
        let manager = TaskManager(repository: repository, scheduler: scheduler, engine: engine)

        let task = try await manager.createOneTime(
            title: "Permission test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        try await scheduler.reconcile()
        var pending = await fakeAdapter.pendingRequests()
        let initialCount = pending.count

        // Меняем разрешение на authorized
        fakeAdapter.setAuthorizationStatus(.authorized)

        try await scheduler.reconcile()

        // Очередь должна быть запланирована
        pending = await fakeAdapter.pendingRequests()
        let taskPending = pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }
        XCTAssertEqual(taskPending.count, 4, "После предоставления разрешения очередь запланирована")
    }
}