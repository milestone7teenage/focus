import Foundation
import SwiftData
import XCTest
@testable import focus

@MainActor
final class TaskManagerTests: XCTestCase {
    private var container: ModelContainer!
    private var manager: TaskManager!
    private var scheduler: InMemoryNotificationScheduler!
    private var engine: ScheduleEngine!
    private var repository: TaskRepository!

    override func setUp() async throws {
        container = try TestContainer.make()
        let context = ModelContext(container)
        repository = TaskRepository(modelContext: context)
        scheduler = InMemoryNotificationScheduler()
        engine = ScheduleEngine()
        manager = TaskManager(repository: repository, scheduler: scheduler, engine: engine)
    }

    override func tearDown() async throws {
        container = nil
        manager = nil
        scheduler = nil
        engine = nil
    }

    // MARK: - Creation

    func testCreateOneTime() async throws {
        let scheduled = Date(timeIntervalSinceNow: 3600)
        let task = try await manager.createOneTime(title: "Взять кошку к ветеринару", scheduledAt: scheduled)

        XCTAssertEqual(task.title, "Взять кошку к ветеринару")
        XCTAssertEqual(task.state, .pending)
        XCTAssertEqual(task.notificationGeneration, 0)
        XCTAssertEqual(task.repeatCount, 0)
        XCTAssertTrue(scheduled.timeIntervalSince(task.scheduledAt) < 1.0)

        let all = try await manager.fetchAllOneTime()
        XCTAssertEqual(all.count, 1)
    }

    func testCreateOneTimeNormalizesPastTimeTodayToTomorrow() async throws {
        // Тест: сегодня прошедшее время -> завтра с тем же локальным временем.
        let pastToday = Date(timeIntervalSinceNow: -600) // 10 минут назад
        let task = try await manager.createOneTime(title: "Past today", scheduledAt: pastToday)

        let tomorrow = await engine.nextLocalDay(after: await engine.localDay())
        let expectedComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: pastToday)
        let expected = Calendar.current.date(bySettingHour: expectedComponents.hour ?? 0,
                                             minute: expectedComponents.minute ?? 0,
                                             second: expectedComponents.second ?? 0,
                                             of: tomorrow)!
        XCTAssertTrue(task.scheduledAt.timeIntervalSince(expected) < 60, "Дата перенесена на завтра с тем же временем")
    }

    func testCreateOneTimeDoesNotNormalizeFuture() async throws {
        let future = Date(timeIntervalSinceNow: 7200)
        let task = try await manager.createOneTime(title: "Future", scheduledAt: future)
        XCTAssertEqual(task.scheduledAt, future, "Будущее время не переносится")
    }

    func testCreateRegular() async throws {
        let template = try await manager.createRegular(title: "Зубная щетка", localHour: 8, localMinute: 30)

        XCTAssertEqual(template.title, "Зубная щетка")
        XCTAssertEqual(template.localHour, 8)
        XCTAssertEqual(template.localMinute, 30)
        XCTAssertTrue(template.isEnabled)

        let all = try await manager.fetchAllRegular()
        XCTAssertEqual(all.count, 1)

        // Первый экземпляр создан на текущий день.
        let instances = try await manager.fetchActiveInstances(for: template.id)
        let expectedKey = await engine.dayKey()
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances.first?.dayKey, expectedKey)
    }

    func testCreateMultipleTasks() async throws {
        _ = try await manager.createOneTime(title: "A", scheduledAt: Date(timeIntervalSinceNow: 600))
        _ = try await manager.createOneTime(title: "B", scheduledAt: Date(timeIntervalSinceNow: 1200))
        _ = try await manager.createOneTime(title: "C", scheduledAt: Date(timeIntervalSinceNow: 1800))
        _ = try await manager.createRegular(title: "R1", localHour: 9, localMinute: 0)
        _ = try await manager.createRegular(title: "R2", localHour: 21, localMinute: 0)

        let oneTime = try await manager.fetchAllOneTime()
        let regular = try await manager.fetchAllRegular()
        XCTAssertEqual(oneTime.count, 3)
        XCTAssertEqual(regular.count, 2)
    }

    // MARK: - Completion

    func testCompleteOneTimeRemovesTask() async throws {
        let task = try await manager.createOneTime(title: "Убрать квартиру", scheduledAt: Date(timeIntervalSinceNow: 1800))
        let id = task.id

        try await manager.completeOneTime(id: id)

        let remaining = try await manager.fetchAllOneTime()
        XCTAssertEqual(remaining.count, 0, "Задача должна быть удалена без истории")
    }

    func testCompleteOneTimeCancelsMatchingGeneration() async throws {
        let task = try await manager.createOneTime(title: "X", scheduledAt: Date(timeIntervalSinceNow: 600))
        let generation = task.notificationGeneration
        let id = task.id

        let request = NotificationRequest(
            id: "req-1",
            fireDate: task.scheduledAt,
            title: task.title,
            body: "",
            generation: generation,
            repeatIndex: 0
        )
        try await scheduler.schedule(request)

        try await manager.completeOneTime(id: id)

        let pending = await scheduler.pendingRequests()
        XCTAssertTrue(pending.isEmpty, "Отмена после выполнения")
    }

    func testCompleteInstanceKeepsTemplate() async throws {
        let template = try await manager.createRegular(title: "Йога", localHour: 7, localMinute: 0)
        let instanceID = try await manager.fetchActiveInstances(for: template.id).first!.id

        try await manager.completeInstance(id: instanceID)

        // Шаблон должен остаться.
        let templates = try await manager.fetchAllRegular()
        XCTAssertEqual(templates.count, 1, "Шаблон регулярной задачи не должен удаляться")
        XCTAssertEqual(templates.first?.id, template.id)

        // Дневной экземпляр должен быть удалён.
        let instances = try await manager.fetchActiveInstances(for: template.id)
        XCTAssertTrue(instances.isEmpty, "Дневной экземпляр должен быть удалён")
    }

    func testCompleteInstanceCancelsMatchingGeneration() async throws {
        let template = try await manager.createRegular(title: "Йога", localHour: 7, localMinute: 0)
        let instanceID = try await manager.fetchActiveInstances(for: template.id).first!.id
        let instance = try await manager.fetchActiveInstances(for: template.id).first!
        let generation = instance.notificationGeneration

        let request = NotificationRequest(
            id: "req-yoga",
            fireDate: .now,
            title: "Йога",
            body: "",
            generation: generation,
            repeatIndex: 0
        )
        try await scheduler.schedule(request)

        try await manager.completeInstance(id: instanceID)

        let pending = await scheduler.pendingRequests()
        XCTAssertTrue(pending.isEmpty, "Уведомления экземпляра отменены при выполнении")
    }

    // MARK: - Deletion + Undo

    func testDeleteOneTimeProducesSnapshot() async throws {
        let task = try await manager.createOneTime(title: "Удалить меня", scheduledAt: Date(timeIntervalSinceNow: 900))
        let id = task.id

        let snapshot = try await manager.deleteOneTime(id: id)

        guard case .oneTime(let s) = snapshot else {
            return XCTFail("Ожидался .oneTime снимок")
        }
        XCTAssertEqual(s.id, id)
        XCTAssertEqual(s.title, "Удалить меня")
        XCTAssertEqual(s.state, .pending)

        let remaining = try await manager.fetchAllOneTime()
        XCTAssertTrue(remaining.isEmpty, "Задача удалена из хранилища немедленно")
    }

    func testRestoreOneTimeSnapshot() async throws {
        let task = try await manager.createOneTime(title: "Undo me", scheduledAt: Date(timeIntervalSinceNow: 900))
        let id = task.id
        let snapshot = try await manager.deleteOneTime(id: id)

        try await manager.restore(snapshot: snapshot!)

        let restored = try await manager.fetchAllOneTime()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, id)
        XCTAssertEqual(restored.first?.title, "Undo me")
        XCTAssertEqual(restored.first?.state, .pending)
    }

    func testDeleteRegularRemovesTemplateAndInstance() async throws {
        let template = try await manager.createRegular(title: "Вечерняя растяжка", localHour: 22, localMinute: 0)
        let instanceID = try await manager.fetchActiveInstances(for: template.id).first!.id

        let snapshot = try await manager.deleteRegular(id: template.id)

        // Шаблон и экземпляр удалены.
        let templates = try await manager.fetchAllRegular()
        XCTAssertTrue(templates.isEmpty, "Шаблон удалён")

        let instances = try await manager.fetchActiveInstances(for: template.id)
        XCTAssertTrue(instances.isEmpty, "Дневной экземпляр удалён вместе с шаблоном")

        // Снимок содержит и шаблон, и экземпляр.
        guard case .recurring(let s) = snapshot else {
            return XCTFail("Ожидался .recurring снимок")
        }
        XCTAssertEqual(s.templateID, template.id)
        XCTAssertEqual(s.templateTitle, "Вечерняя растяжка")
        XCTAssertNotNil(s.instanceID)
        XCTAssertEqual(s.instanceID, instanceID)
    }

    func testRestoreRegularSnapshot() async throws {
        let template = try await manager.createRegular(title: "Undo regular", localHour: 6, localMinute: 15)
        let instanceID = try await manager.fetchActiveInstances(for: template.id).first!.id

        _ = try await manager.deleteRegular(id: template.id)

        let snapshot = TaskSnapshot.recurring(
            RecurringSnapshot(
                template: template,
                instance: DailyTaskInstance(
                    id: instanceID,
                    templateID: template.id,
                    template: nil,
                    dayKey: await engine.dayKey(),
                    state: .pending
                )
            )
        )

        try await manager.restore(snapshot: snapshot)

        let templates = try await manager.fetchAllRegular()
        XCTAssertEqual(templates.count, 1, "Шаблон восстановлен")
        let instances = try await manager.fetchActiveInstances(for: template.id)
        XCTAssertEqual(instances.count, 1, "Дневной экземпляр восстановлен")
        XCTAssertEqual(instances.first?.id, instanceID)
    }

    // MARK: - Snooze

    func testSnoozeOneTimeShiftsScheduledAtAndResetsState() async throws {
        let task = try await manager.createOneTime(title: "Snooze me", scheduledAt: Date(timeIntervalSinceNow: 600))
        let id = task.id

        // Переводим в seen, чтобы проверить сброс в pending.
        try await manager.markOneTimeSeen(id: id)
        let generationBefore = task.notificationGeneration

        try await manager.snoozeOneTime(id: id)

        let refetched = try await manager.fetchAllOneTime().first
        XCTAssertNotNil(refetched)
        XCTAssertEqual(refetched?.state, .pending, "Snooze сбрасывает state в pending")
        XCTAssertGreaterThanOrEqual(refetched?.notificationGeneration ?? 0, generationBefore + 1, "Поколение увеличено")

        let now = Date()
        let target = now.addingTimeInterval(30 * 60)
        XCTAssertGreaterThan(refetched!.scheduledAt, now, "scheduledAt > now")
        XCTAssertLessThanOrEqual(refetched!.scheduledAt, target.addingTimeInterval(60), "scheduledAt ≈ now + 30 мин")
    }

    func testSnoozeInstanceSetsSnoozedUntilOnly() async throws {
        let template = try await manager.createRegular(title: "Snooze regular", localHour: 10, localMinute: 0)
        let instanceID = try await manager.fetchActiveInstances(for: template.id).first!.id
        let originalHour = template.localHour
        let originalMinute = template.localMinute

        try await manager.snoozeInstance(id: instanceID)

        let instances = try await manager.fetchActiveInstances(for: template.id)
        let refetched = instances.first
        XCTAssertNotNil(refetched?.snoozedUntil, "snoozedUntil задан")
        XCTAssertEqual(refetched?.state, .pending, "Snooze сбрасывает state в pending")
        let now = Date()
        XCTAssertGreaterThan(refetched!.snoozedUntil!, now)
        XCTAssertLessThanOrEqual(refetched!.snoozedUntil!, now.addingTimeInterval(30 * 60 + 60))

        // Шаблон не изменён.
        let templates = try await manager.fetchAllRegular()
        XCTAssertEqual(templates.first?.localHour, originalHour, "localHour шаблона не меняется")
        XCTAssertEqual(templates.first?.localMinute, originalMinute, "localMinute шаблона не меняется")
    }

    // MARK: - SEEN

    func testMarkOneTimeSeenIsIdempotent() async throws {
        let task = try await manager.createOneTime(title: "Seen me", scheduledAt: Date(timeIntervalSinceNow: 1200))
        let id = task.id

        try await manager.markOneTimeSeen(id: id)
        try await manager.markOneTimeSeen(id: id)
        try await manager.markOneTimeSeen(id: id)

        let refetched = try await manager.fetchAllOneTime().first
        XCTAssertEqual(refetched?.state, .seen, "Повторная обработка SEEN идемпотентна")
    }

    func testMarkInstanceSeenIsIdempotent() async throws {
        let template = try await manager.createRegular(title: "Seen regular", localHour: 12, localMinute: 0)
        let instanceID = try await manager.fetchActiveInstances(for: template.id).first!.id

        try await manager.markInstanceSeen(id: instanceID)
        try await manager.markInstanceSeen(id: instanceID)

        let instances = try await manager.fetchActiveInstances(for: template.id)
        XCTAssertEqual(instances.first?.state, .seen)
    }

    func testSeenPersistsAcrossRestart() async throws {
        let task = try await manager.createOneTime(title: "Persist seen", scheduledAt: Date(timeIntervalSinceNow: 1800))
        let id = task.id
        try await manager.markOneTimeSeen(id: id)

        // Имитация перезапуска: новый репозиторий, та же in-memory схема.
        let repository2 = TaskRepository(modelContext: ModelContext(container))
        let refetched = try await repository2.fetchOneTime(id: id)
        XCTAssertEqual(refetched?.state, .seen, "Состояние SEEN сохраняется после перезапуска (in-memory)")
    }

    // MARK: - Daily reset

    func testRunDailyResetIdempotent() async throws {
        let template = try await manager.createRegular(title: "Reset me", localHour: 9, localMinute: 0)

        // Первый reset
        try await manager.runDailyReset()
        var instances = try await manager.fetchActiveInstances(for: template.id)
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances.first?.state, .pending)

        // Второй reset (идемпотентность)
        try await manager.runDailyReset()
        instances = try await manager.fetchActiveInstances(for: template.id)
        XCTAssertEqual(instances.count, 1, "Reset идемпотентен")
        XCTAssertEqual(instances.first?.state, .pending)
    }

    func testRunDailyResetRemovesStaleInstances() async throws {
        let template = try await manager.createRegular(title: "Stale", localHour: 9, localMinute: 0)

        // Создадим вчерашний экземпляр вручную.
        let context = ModelContext(container)
        let yesterday = await engine.dayKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let stale = DailyTaskInstance(
            templateID: template.id,
            template: template,
            dayKey: yesterday,
            state: .pending
        )
        context.insert(stale)
        try context.save()

        // Запускаем reset.
        try await manager.runDailyReset()

        // Вчерашний должен быть удалён, сегодняшний — PENDING.
        let instances = try await manager.fetchActiveInstances(for: template.id)
        let expectedKey = await engine.dayKey()
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances.first?.dayKey, expectedKey)
        XCTAssertEqual(instances.first?.state, .pending)
    }

    func testRunDailyResetKeepsOnlyOneInstancePerTemplate() async throws {
        let template = try await manager.createRegular(title: "Duplicates", localHour: 9, localMinute: 0)

        // Создадим дубль для того же шаблона на тот же день.
        let context = ModelContext(container)
        let today = await engine.dayKey()
        let dup = DailyTaskInstance(
            templateID: template.id,
            template: template,
            dayKey: today,
            state: .seen
        )
        context.insert(dup)
        try context.save()

        try await manager.runDailyReset()

        // Должен остаться ровно один экземпляр.
        let instances = try await manager.fetchActiveInstances(for: template.id)
        let expectedKey = await engine.dayKey()
        XCTAssertEqual(instances.count, 1, "Дубликаты удалены, остался один экземпляр на день")
        XCTAssertEqual(instances.first?.state, .pending, "Состояние сброшено в pending")
        XCTAssertEqual(instances.first?.dayKey, expectedKey)
    }

    func testRunDailyResetClearsSnoozePriority() async throws {
        let template = try await manager.createRegular(title: "Snooze reset", localHour: 23, localMinute: 30)

        // Создаём экземпляр с snooze на прошлый день (simulate snooze crossed midnight).
        let context = ModelContext(container)
        let yesterday = await engine.dayKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let snoozed = DailyTaskInstance(
            templateID: template.id,
            template: template,
            dayKey: yesterday,
            state: .pending,
            snoozedUntil: Date().addingTimeInterval(30 * 60)
        )
        context.insert(snoozed)
        try context.save()

        try await manager.runDailyReset()

        // Вчерашний экземпляр удалён, новый создан PENDING без snooze.
        let instances = try await manager.fetchActiveInstances(for: template.id)
        let expectedKey = await engine.dayKey()
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances.first?.dayKey, expectedKey)
        XCTAssertEqual(instances.first?.state, .pending)
        XCTAssertNil(instances.first?.snoozedUntil, "Snooze сгорел, не перенесся")
    }

    func testRunDailyResetDisabledTemplateSkipped() async throws {
        let template = try await manager.createRegular(title: "Disabled", localHour: 8, localMinute: 0)
        try await repository.updateRegular(template) // не удаляем, просто меняем isEnabled

        // Нужно отключить: прочитать, поменять, сохранить.
        var t = try await manager.fetchAllRegular().first!
        t.isEnabled = false
        try await repository.updateRegular(t)

        try await manager.runDailyReset()

        let instances = try await manager.fetchActiveInstances(for: t.id)
        XCTAssertTrue(instances.isEmpty, "Отключенные шаблоны не создают экземпляр")
    }
}