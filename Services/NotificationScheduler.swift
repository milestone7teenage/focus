import Foundation
@preconcurrency import UserNotifications

/// Реальный планировщик уведомлений поверх `UNUserNotificationCenter`.
/// Реализует `NotificationScheduling` (интерфейс из Этапа 2).
public final class NotificationScheduler: NotificationScheduling {
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await adapter.authorizationStatus()
    }
    // MARK: - Constants

    /// Безопасный лимит ожидающих запросов (из 64 системных слотов).
    /// Internal, чтобы тесты могли проверить соблюдение бюджета.
    static let maxPendingRequests = 60

    // MARK: - Properties

    private let adapter: NotificationCenterAdapter
    private let repository: TaskRepository
    private let engine: ScheduleEngine

    // MARK: - Init

    public init(
        adapter: NotificationCenterAdapter,
        repository: TaskRepository,
        engine: ScheduleEngine
    ) {
        self.adapter = adapter
        self.repository = repository
        self.engine = engine

        // Регистрация категории с действием «Увидел»
        Task { await registerCategory() }
    }

    // MARK: - NotificationScheduling

    /// Планирует один цикл уведомлений для задачи (T0, T+10, T+20, T+30).
    /// `generation` — поколение расписания (инкрементируется при snooze/reschedule).
    /// `repeatIndex` — 0..3 (0 = T0, 1 = T+10, 2 = T+20, 3 = T+30).
    public func schedule(_ request: NotificationRequest) async throws {
        let unRequest = makeUNNotificationRequest(from: request)
        try await adapter.add(unRequest)
    }

    /// Отменяет уведомления по идентификаторам.
    public func cancel(ids: [String]) async {
        adapter.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Отменяет все уведомления.
    public func cancelAll() async {
        adapter.removeAllPendingNotificationRequests()
    }

    /// Возвращает все ожидающие запросы.
    public func pendingRequests() async -> [NotificationRequest] {
        let unRequests = await adapter.pendingNotificationRequests()
        return unRequests.compactMap(parseNotificationRequest)
    }

    // MARK: - Public API

    /// Полная сверка очереди: удаление устаревших, допланирование недостающих.
    /// Вызывается при запуске, возврате в active, изменении задач.
    public func reconcile() async throws {
        // 1. Получаем все активные напоминания из БД
        let oneTime = try await repository.fetchAllOneTime()
        let regularTemplates = try await repository.fetchAllRegular()

        var allTasks: [SchedulableTask] = []

        // One-time задачи
        for task in oneTime where task.state == .pending && task.scheduledAt > .now {
            allTasks.append(SchedulableTask(
                id: task.id,
                title: task.title,
                fireDate: task.scheduledAt,
                type: .oneTime,
                dayKey: nil,
                generation: task.notificationGeneration
            ))
        }

        // Regular задачи: текущий дневной экземпляр
        let todayKey = await engine.dayKey()
        for template in regularTemplates where template.isEnabled {
            let instances = try await repository.fetchInstances(for: template.id)
            if let todayInstance = instances.first(where: { $0.dayKey == todayKey }),
               todayInstance.state == .pending {
                // Вычисляем время срабатывания на сегодня
                let fireDate = makeFireDateForToday(hour: template.localHour, minute: template.localMinute)
                // Если время уже прошло сегодня — пропускаем (reset создаст новый завтра)
                guard fireDate > .now else { continue }

                allTasks.append(SchedulableTask(
                    id: todayInstance.id,
                    title: template.title,
                    fireDate: fireDate,
                    type: .recurring,
                    dayKey: todayKey,
                    generation: todayInstance.notificationGeneration
                ))
            }
        }

        // 2. Сортируем по ближайшему времени срабатывания
        allTasks.sort { $0.fireDate < $1.fireDate }

        // 3. Получаем текущие ожидающие запросы
        let currentRequests = await pendingRequests()
        let currentIDs = Set(currentRequests.map(\.id))

        // 4. Планируем до бюджета
        var scheduledCount = 0
        var neededIDs: Set<String> = []

        for task in allTasks {
            if scheduledCount >= Self.maxPendingRequests { break }

            // Генерируем 4 запроса на цикл
            for repeatIndex in 0..<4 {
                if scheduledCount >= Self.maxPendingRequests { break }

                let fireDate = task.fireDate.addingTimeInterval(TimeInterval(repeatIndex * 10 * 60))
                let id = makeNotificationID(
                    type: task.type,
                    uuid: task.id,
                    dayKey: task.dayKey,
                    generation: task.generation,
                    repeatIndex: repeatIndex
                )

                let req = NotificationRequest(
                    id: id,
                    fireDate: fireDate,
                    title: task.title,
                    body: "",
                    generation: task.generation,
                    repeatIndex: repeatIndex
                )

                // Проверяем, не запланирован ли уже
                if !currentIDs.contains(id) {
                    try await schedule(req)
                }
                neededIDs.insert(id)
                scheduledCount += 1
            }
        }

        // 5. Удаляем устаревшие/лишние (сиротские) запросы
        let toRemove = currentIDs.subtracting(neededIDs)
        if !toRemove.isEmpty {
            await cancel(ids: Array(toRemove))
        }
    }

    /// Проверка авторизации и показ предупреждения при необходимости.
    public func checkAuthorization() async -> Bool {
        let status = await adapter.authorizationStatus()
        return status == .authorized
    }

    /// Запрос разрешения на уведомления.
    public func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        do {
            let granted = try await adapter.requestAuthorization(options: options)
            if granted {
                await registerCategory()
            }
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func registerCategory() async {
        let seenAction = UNNotificationAction(
            identifier: "SEEN_ACTION",
            title: "Увидел",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "TASK_REMINDER",
            actions: [seenAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        adapter.setNotificationCategories([category])
    }

    private func makeFireDateForToday(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? now
    }

    private func makeNotificationID(
        type: TaskType,
        uuid: UUID,
        dayKey: String?,
        generation: Int,
        repeatIndex: Int
    ) -> String {
        let typePrefix = type == .oneTime ? "ot" : "rt"
        let dayPart = dayKey?.replacingOccurrences(of: "-", with: "") ?? ""
        return "\(typePrefix)_\(uuid.uuidString)_\(dayPart)_\(generation)_\(repeatIndex)"
    }

    private func makeUNNotificationRequest(from request: NotificationRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body.isEmpty ? "Напоминание" : request.body
        content.sound = .default
        content.categoryIdentifier = "TASK_REMINDER"
        content.userInfo = [
            "id": request.id,
            "generation": request.generation,
            "repeatIndex": request.repeatIndex
        ]

        let trigger: UNNotificationTrigger
        let interval = request.fireDate.timeIntervalSinceNow
        if interval <= 0 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        }

        return UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)
    }

    private func parseNotificationRequest(_ unRequest: UNNotificationRequest) -> NotificationRequest? {
        let userInfo = unRequest.content.userInfo
        guard let generation = userInfo["generation"] as? Int,
              let repeatIndex = userInfo["repeatIndex"] as? Int else {
            return nil
        }
        // Извлекаем fireDate из триггера
        let fireDate: Date
        if let trigger = unRequest.trigger as? UNTimeIntervalNotificationTrigger {
            fireDate = Date().addingTimeInterval(trigger.timeInterval)
        } else {
            fireDate = Date()
        }
        return NotificationRequest(
            id: unRequest.identifier,
            fireDate: fireDate,
            title: unRequest.content.title,
            body: unRequest.content.body,
            generation: generation,
            repeatIndex: repeatIndex
        )
    }
}

// MARK: - Supporting Types

private enum TaskType {
    case oneTime
    case recurring
}

private struct SchedulableTask {
    let id: UUID
    let title: String
    let fireDate: Date
    let type: TaskType
    let dayKey: String?
    let generation: Int
}