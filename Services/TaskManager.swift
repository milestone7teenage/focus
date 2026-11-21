import Foundation
import SwiftData
import UserNotifications

/// Центральный доменной сервис: CRUD, выполнение, удаление, Undo, Snooze, SEEN, календарный reset.
/// Чистый компонент: не знает о SwiftUI и не зовёт напрямую `UNUserNotificationCenter`.
/// Уведомления уходят через `NotificationScheduling` (заглушка на Этапе 2).
/// Календарная логика вынесена в `ScheduleEngine` (Этап 3).
public final class TaskManager: Sendable {
    private let repository: TaskRepository
    private let scheduler: any NotificationScheduling
    private let engine: ScheduleEngine

    public init(
        repository: TaskRepository,
        scheduler: any NotificationScheduling,
        engine: ScheduleEngine = ScheduleEngine()
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.engine = engine
    }

    // MARK: - Create

    /// Создание разовой задачи с валидацией даты через `ScheduleEngine`:
    /// если выбраны сегодняшняя дата и уже прошедшее время — дата переносится на завтра
    /// с тем же местным временем.
    public func createOneTime(title: String, scheduledAt: Date) async throws -> OneTimeTask {
        let normalized = await engine.normalizeOneTimeDate(scheduledAt)
        let task = OneTimeTask(title: title, scheduledAt: normalized)
        try await repository.createOneTime(task)
        return task
    }

    /// Создание регулярной задачи + первый дневной экземпляр на текущий локальный день.
    public func createRegular(title: String, localHour: Int, localMinute: Int) async throws -> RegularTaskTemplate {
        let template = RegularTaskTemplate(title: title, localHour: localHour, localMinute: localMinute)
        try await repository.createRegular(template)
        let dayKey = await engine.dayKey()
        let instance = DailyTaskInstance(
            templateID: template.id,
            template: template,
            dayKey: dayKey,
            state: .pending
        )
        try await repository.createInstance(instance)
        return template
    }

    // MARK: - Fetch

    public func fetchAllOneTime() async throws -> [OneTimeTask] {
        try await repository.fetchAllOneTime()
    }

    public func fetchAllRegular() async throws -> [RegularTaskTemplate] {
        try await repository.fetchAllRegular()
    }

    public func fetchActiveInstances(for templateID: UUID) async throws -> [DailyTaskInstance] {
        try await repository.fetchInstances(for: templateID)
    }

    // MARK: - Daily reset (ScheduleEngine)

    /// Идемпотентный ежедневный reset: запускается при запуске приложения и возврате в active.
    /// Удаляет устаревшие экземпляры, гарантирует ровно один PENDING-экземпляр на активный шаблон.
    /// Приоритет reset над вчерашним snooze: snooze сгорает и не переносится.
    public func runDailyReset() async throws {
        let templates = try await repository.fetchAllRegular()
        let instances = try await repository.fetchAllInstances()

        try await engine.performReset(
            templates: templates,
            instances: instances,
            deleteInstance: { id in
                try await self.repository.deleteInstance(id: id)
            },
            createInstance: { instance in
                try await self.repository.createInstance(instance)
            }
        )
        try await repository.save()
    }

    // MARK: - Complete

    /// Выполнение разовой задачи: удаляет задачу без истории. Уведомления отменяются.
    public func completeOneTime(id: UUID) async throws {
        guard let task = try await repository.fetchOneTime(id: id) else { return }
        let generation = task.notificationGeneration
        let pending = await scheduler.pendingRequests()
        let ids = pending.filter { $0.generation == generation }.map(\.id)
        await scheduler.cancel(ids: ids)
        try await repository.deleteOneTime(id: id)
    }

    /// Выполнение дневного экземпляра: удаляет только экземпляр дня, шаблон нетронут.
    public func completeInstance(id: UUID) async throws {
        guard let instance = try await repository.fetchInstance(id: id) else { return }
        let generation = instance.notificationGeneration
        let pending = await scheduler.pendingRequests()
        let ids = pending.filter { $0.generation == generation }.map(\.id)
        await scheduler.cancel(ids: ids)
        try await repository.deleteInstance(id: id)
    }

    // MARK: - Delete + Undo

    /// Удаление разовой задачи: немедленное удаление из SwiftData + снимок на 3 секунды.
    /// Отменяет все уведомления задачи.
    public func deleteOneTime(id: UUID) async throws -> TaskSnapshot? {
        guard let task = try await repository.fetchOneTime(id: id) else { return nil }
        let generation = task.notificationGeneration
        let pending = await scheduler.pendingRequests()
        let ids = pending.filter { $0.generation == generation }.map(\.id)
        await scheduler.cancel(ids: ids)
        let snapshot = TaskSnapshot.oneTime(OneTimeSnapshot(task))
        try await repository.deleteOneTime(id: id)
        return snapshot
    }

    /// Удаление регулярной задачи: удаляет шаблон и текущий экземпляр + снимок.
    /// Отменяет все уведомления текущего экземпляра.
    public func deleteRegular(id: UUID) async throws -> TaskSnapshot? {
        guard let template = try await repository.fetchRegular(id: id) else { return nil }
        let instances = try await repository.fetchInstances(for: id)
        let currentDay = await engine.dayKey()
        let currentInstance = instances.first { $0.dayKey == currentDay }
        let generation = currentInstance?.notificationGeneration
        let snapshot = TaskSnapshot.recurring(RecurringSnapshot(template: template, instance: currentInstance))
        if let generation = generation {
            let pending = await scheduler.pendingRequests()
            let ids = pending.filter { $0.generation == generation }.map(\.id)
            await scheduler.cancel(ids: ids)
        }
        try await repository.deleteRegular(id: id)
        return snapshot
    }

    /// Восстановление по снимку (Undo).
    public func restore(snapshot: TaskSnapshot) async throws {
        switch snapshot {
        case .oneTime(let s):
            let task = OneTimeTask(
                id: s.id,
                title: s.title,
                scheduledAt: s.scheduledAt,
                state: s.state,
                createdAt: s.createdAt,
                repeatCount: s.repeatCount,
                notificationGeneration: s.notificationGeneration
            )
            try await repository.createOneTime(task)
        case .recurring(let s):
            let template = RegularTaskTemplate(
                id: s.templateID,
                title: s.templateTitle,
                localHour: s.localHour,
                localMinute: s.localMinute,
                isEnabled: s.isEnabled,
                createdAt: s.createdAt,
                notificationGeneration: s.templateGeneration
            )
            try await repository.createRegular(template)
            if let instanceID = s.instanceID,
               let dayKey = s.instanceDayKey,
               let state = s.instanceState,
               let repeatCount = s.instanceRepeatCount,
               let generation = s.instanceGeneration {
                let instance = DailyTaskInstance(
                    id: instanceID,
                    templateID: s.templateID,
                    template: template,
                    dayKey: dayKey,
                    state: state,
                    repeatCount: repeatCount,
                    snoozedUntil: s.instanceSnoozedUntil,
                    notificationGeneration: generation
                )
                try await repository.createInstance(instance)
            }
        }
    }

    // MARK: - Snooze

    /// Snooze разовой задачи: сдвиг `scheduledAt = now + 30 мин`, увеличение поколения, сброс в `pending`.
    public func snoozeOneTime(id: UUID) async throws {
        guard let task = try await repository.fetchOneTime(id: id) else { return }
        task.scheduledAt = Date(timeIntervalSinceNow: 30 * 60)
        task.notificationGeneration += 1
        task.state = .pending
        try await repository.updateOneTime(task)
        try await scheduler.reconcile()
    }

    /// Snooze регулярной задачи: изменяется только текущий дневной экземпляр (`snoozedUntil`).
    public func snoozeInstance(id: UUID) async throws {
        guard let instance = try await repository.fetchInstance(id: id) else { return }
        instance.snoozedUntil = Date(timeIntervalSinceNow: 30 * 60)
        instance.notificationGeneration += 1
        instance.state = .pending
        try await repository.save()
        try await scheduler.reconcile()
    }

    // MARK: - SEEN

    /// Идемпотентный перевод активной задачи в `seen`.
    /// Отменяет оставшиеся повторы текущего цикла уведомлений.
    public func markOneTimeSeen(id: UUID) async throws {
        guard let task = try await repository.fetchOneTime(id: id) else { return }
        guard task.state != .seen else { return }
        let generation = task.notificationGeneration
        let pending = await scheduler.pendingRequests()
        let ids = pending.filter { $0.generation == generation }.map(\.id)
        await scheduler.cancel(ids: ids)
        task.state = .seen
        try await repository.updateOneTime(task)
    }

    public func markInstanceSeen(id: UUID) async throws {
        guard let instance = try await repository.fetchInstance(id: id) else { return }
        guard instance.state != .seen else { return }
        let generation = instance.notificationGeneration
        let pending = await scheduler.pendingRequests()
        let ids = pending.filter { $0.generation == generation }.map(\.id)
        await scheduler.cancel(ids: ids)
        instance.state = .seen
        try await repository.save()
    }
}