import Foundation
import SwiftData
import XCTest
@testable import focus

@MainActor
final class NotificationSchedulerTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: TaskRepository!
    private var engine: ScheduleEngine!
    private var fakeAdapter: FakeNotificationCenterAdapter!
    private var scheduler: NotificationScheduler!
    private var manager: TaskManager!

    override func setUp() async throws {
        container = try TestContainer.make()
        let context = ModelContext(container)
        repository = TaskRepository(modelContext: context)
        engine = ScheduleEngine()
        fakeAdapter = FakeNotificationCenterAdapter()
        fakeAdapter.setAuthorizationStatus(.authorized)

        scheduler = NotificationScheduler(
            adapter: fakeAdapter,
            repository: repository,
            engine: engine
        )

        manager = TaskManager(repository: repository, scheduler: scheduler, engine: engine)
    }

    override func tearDown() async throws {
        container = nil
        repository = nil
        engine = nil
        fakeAdapter = nil
        scheduler = nil
        manager = nil
    }

    // MARK: - Schedule cycle tests

    func testScheduleOneTimeCreatesFourNotifications() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        try await scheduler.reconcile()

        let pending = await fakeAdapter.pendingRequests()
        let taskRequests = pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }
        XCTAssertEqual(taskRequests.count, 4, "Должно быть 4 уведомления на цикл (T0, +10, +20, +30)")

        // Проверяем уникальные repeatIndex
        let repeatIndices = Set(taskRequests.compactMap { req -> Int? in
            req.content.userInfo["repeatIndex"] as? Int
        })
        XCTAssertEqual(repeatIndices, Set([0, 1, 2, 3]), "repeatIndex должен быть 0, 1, 2, 3")
    }

    func testScheduleRecurringCreatesFourNotifications() async throws {
        // Используем будущее время (23:00), чтобы fireDate гарантированно был в будущем
        let template = try await manager.createRegular(title: "Daily", localHour: 23, localMinute: 0)
        let instance = try await manager.fetchActiveInstances(for: template.id).first!

        try await scheduler.reconcile()

        let pending = await fakeAdapter.pendingRequests()
        let taskRequests = pending.filter { $0.identifier.hasPrefix("rt_\(instance.id.uuidString)") }
        XCTAssertEqual(taskRequests.count, 4, "Должно быть 4 уведомления на цикл для регулярной задачи")
    }

    func testNotificationIdsAreDeterministicAndContainMetadata() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        try await scheduler.reconcile()

        let pending = await fakeAdapter.pendingRequests()
        let req = pending.first { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }!

        // Сохраняем пустые подстроки (dayKey пустой для one-time -> двойное подчёркивание)
        let parts = req.identifier.split(separator: "_", omittingEmptySubsequences: false)
        // Формат: ot_UUID__generation_repeatIndex -> [ot, UUID, "", generation, repeatIndex]
        XCTAssertEqual(parts[0], "ot", "Префикс для one-time")
        XCTAssertEqual(String(parts[1]), task.id.uuidString, "UUID задачи")
        XCTAssertEqual(Int(parts[3]) ?? -1, task.notificationGeneration, "Поколение")
        XCTAssertEqual(Int(parts[4]) ?? -1, 0, "repeatIndex для первого уведомления")
    }

    func testUserInfoContainsGenerationAndRepeatIndex() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        try await scheduler.reconcile()

        let pending = await fakeAdapter.pendingRequests()
        let req = pending.first { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }!

        let userInfo = req.content.userInfo
        XCTAssertEqual(userInfo["generation"] as? Int, task.notificationGeneration)
        XCTAssertEqual(userInfo["repeatIndex"] as? Int, 0)
    }

    // MARK: - Cancel tests

    func testCompleteOneTimeCancelsAllRepeats() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )
        let generation = task.notificationGeneration

        try await scheduler.reconcile()
        var pending = await fakeAdapter.pendingRequests()
        XCTAssertEqual(pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }.count, 4)

        try await manager.completeOneTime(id: task.id)

        pending = await fakeAdapter.pendingRequests()
        let remaining = pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }
        XCTAssertTrue(remaining.isEmpty, "Все уведомления отменены после выполнения")
    }

    func testCompleteInstanceCancelsAllRepeats() async throws {
        // Используем будущее время (23:00), чтобы fireDate гарантированно был в будущем
        let template = try await manager.createRegular(title: "Daily", localHour: 23, localMinute: 0)
        let instance = try await manager.fetchActiveInstances(for: template.id).first!

        try await scheduler.reconcile()
        var pending = await fakeAdapter.pendingRequests()
        XCTAssertEqual(pending.filter { $0.identifier.hasPrefix("rt_\(instance.id.uuidString)") }.count, 4)

        try await manager.completeInstance(id: instance.id)

        pending = await fakeAdapter.pendingRequests()
        let remaining = pending.filter { $0.identifier.hasPrefix("rt_\(instance.id.uuidString)") }
        XCTAssertTrue(remaining.isEmpty, "Все уведомления экземпляра отменены после выполнения")
    }

    func testDeleteOneTimeCancelsNotifications() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        try await scheduler.reconcile()
        var pending = await fakeAdapter.pendingRequests()
        XCTAssertEqual(pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }.count, 4)

        _ = try await manager.deleteOneTime(id: task.id)

        pending = await fakeAdapter.pendingRequests()
        let remaining = pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }
        XCTAssertTrue(remaining.isEmpty, "Уведомления отменены при удалении")
    }

    func testSnoozeOneTimeCreatesNewCycleWithNewGeneration() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )
        let oldGeneration = task.notificationGeneration

        try await scheduler.reconcile()
        var pending = await fakeAdapter.pendingRequests()
        let oldIDs = Set(pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }.map(\.identifier))

        try await manager.snoozeOneTime(id: task.id)

        // Должен создать новый цикл с увеличенным поколением
        try await scheduler.reconcile()
        pending = await fakeAdapter.pendingRequests()
        let newIDs = Set(pending.filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }.map(\.identifier))

        // Старые отменены, новые добавлены
        XCTAssertTrue(oldIDs.isDisjoint(with: newIDs), "Новый цикл с новым поколением не пересекается со старым")

        let newGen = task.notificationGeneration
        XCTAssertGreaterThan(newGen, oldGeneration, "Поколение увеличено при snooze")
    }

    // MARK: - Budget tests

    func testBudgetLimit60Slots() async throws {
        // Создаём много задач
        for i in 0..<20 {
            _ = try await manager.createOneTime(
                title: "Task \(i)",
                scheduledAt: Date(timeIntervalSinceNow: TimeInterval(3600 + i * 300))
            )
        }

        try await scheduler.reconcile()

        let pending = await fakeAdapter.pendingRequests()
        XCTAssertLessThanOrEqual(pending.count, NotificationScheduler.maxPendingRequests, "Не более 60 ожидающих запросов")
    }

    func testBudgetPrioritizesNearestFireDate() async throws {
        // Создаём задачи: ближние и дальние
        let now = Date()
        for i in 0..<30 {
            let fireDate = now.addingTimeInterval(TimeInterval(1000 + i * 600))
            _ = try await manager.createOneTime(title: "Near \(i)", scheduledAt: fireDate)
        }

        for i in 0..<30 {
            let fireDate = now.addingTimeInterval(TimeInterval(50000 + i * 600))
            _ = try await manager.createOneTime(title: "Far \(i)", scheduledAt: fireDate)
        }

        try await scheduler.reconcile()

        let pending = await fakeAdapter.pendingRequests()
        XCTAssertLessThanOrEqual(pending.count, 60)

        // Ближайшие должны быть в очереди
        let nearFireDates = pending
            .filter { $0.identifier.contains("Near") }
            .compactMap { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval }
        let farFireDates = pending
            .filter { $0.identifier.contains("Far") }
            .compactMap { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval }

        if !nearFireDates.isEmpty && !farFireDates.isEmpty {
            let minNear = nearFireDates.min() ?? .infinity
            let minFar = farFireDates.min() ?? .infinity
            XCTAssertLessThan(minNear, minFar, "Ближайшие задачи имеют приоритет")
        }
    }

    // MARK: - Reconciliation idempotency

    func testReconcileIsIdempotent() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        try await scheduler.reconcile()
        let count1 = (await fakeAdapter.pendingRequests()).filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }.count

        try await scheduler.reconcile()
        let count2 = (await fakeAdapter.pendingRequests()).filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }.count

        XCTAssertEqual(count1, count2, "reconcile идемпотентен")
        XCTAssertEqual(count1, 4, "Ровно 4 уведомления")
    }

    func testReconcileRemovesStaleRequests() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )

        try await scheduler.reconcile()

        // Ручной симуляция удаления задачи без отмены уведомлений
        try await repository.deleteOneTime(id: task.id)

        try await scheduler.reconcile()

        let remaining = (await fakeAdapter.pendingRequests()).filter { $0.identifier.hasPrefix("ot_\(task.id.uuidString)") }
        XCTAssertTrue(remaining.isEmpty, "Устаревшие запросы удалены при reconcile")
    }

    // MARK: - Ignored outdated generation

    func testActionHandlerIgnoresOutdatedGeneration() async throws {
        let task = try await manager.createOneTime(
            title: "Test",
            scheduledAt: Date(timeIntervalSinceNow: 3600)
        )
        let generation = task.notificationGeneration

        try await scheduler.reconcile()

        // Создаём фейковое уведомление со старым поколением
        let oldID = "ot_\(task.id.uuidString)_\(generation)_0"
        let oldContent = UNMutableNotificationContent()
        oldContent.title = "Old"
        oldContent.userInfo = ["id": oldID, "generation": generation, "repeatIndex": 0]
        let oldTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let oldRequest = UNNotificationRequest(identifier: oldID, content: oldContent, trigger: oldTrigger)
        try await fakeAdapter.add(oldRequest)

        // Snooze увеличивает поколение
        try await manager.snoozeOneTime(id: task.id)
        let newGeneration = task.notificationGeneration
        XCTAssertGreaterThan(newGeneration, generation)

        // Запускаем reconcile — старый запрос должен быть удалён
        try await scheduler.reconcile()

        let pending = await fakeAdapter.pendingRequests()
        let hasOld = pending.contains { $0.identifier == oldID }
        XCTAssertFalse(hasOld, "Устаревшее поколение удалено при reconcile")
    }

    // MARK: - Category registration

    func testCategoryRegistered() async throws {
        let categories = await fakeAdapter.getNotificationCategories()
        let category = categories.first { $0.identifier == "TASK_REMINDER" }
        XCTAssertNotNil(category, "Категория TASK_REMINDER зарегистрирована")

        let seenAction = category?.actions.first { $0.identifier == "SEEN_ACTION" }
        XCTAssertNotNil(seenAction, "Действие SEEN_ACTION в категории")
        XCTAssertEqual(seenAction?.title, "Увидел")
    }
}