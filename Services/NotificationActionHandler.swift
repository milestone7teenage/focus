import Foundation
import UserNotifications

/// Обработчик действий уведомлений: `UNUserNotificationCenterDelegate`.
/// Обрабатывает нажатие на тело уведомления и кнопку «Увидел».
/// Переводит задачу в `SEEN`, отменяет оставшиеся повторы, сохраняет состояние.
public final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let manager: TaskManager
    private let scheduler: NotificationScheduler

    public init(manager: TaskManager, scheduler: NotificationScheduler) {
        self.manager = manager
        self.scheduler = scheduler
        super.init()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Показывать баннер даже когда приложение на переднем плане.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Обработка нажатия на уведомление (тело или действие).
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await handleResponse(response)
            completionHandler()
        }
    }

    // MARK: - Private

    private func handleResponse(_ response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let idString = userInfo["id"] as? String,
              let generation = userInfo["generation"] as? Int else {
            return
        }

        let actionIdentifier = response.actionIdentifier

        // При dismiss — сразу выходим, задача не меняется
        if actionIdentifier == UNNotificationDismissActionIdentifier {
            return
        }

        // Нажатие на тело уведомления и кнопка «Увидел» — переводим в SEEN
        if actionIdentifier == UNNotificationDefaultActionIdentifier ||
           actionIdentifier == "SEEN_ACTION" {
            await processSeen(idString: idString, generation: generation)
        }
    }

    private func processSeen(idString: String, generation: Int) async {
        // Парсим ID: "ot_UUID_generation_repeatIndex" или "rt_UUID_dayKey_generation_repeatIndex"
        let parts = idString.split(separator: "_").map(String.init)
        guard parts.count >= 4 else { return }

        let typePrefix = parts[0]
        let uuidString = parts[1]
        guard let uuid = UUID(uuidString: uuidString) else { return }

        // Проверяем поколение — игнорируем устаревшие
        let currentGeneration: Int
        do {
            if typePrefix == "ot" {
                // One-time task
                if let task = try await manager.fetchAllOneTime().first(where: { $0.id == uuid }) {
                    currentGeneration = task.notificationGeneration
                } else {
                    // Задача удалена — игнорируем
                    return
                }
            } else {
                // Recurring task - need to find instance
                if let task = try await manager.fetchAllRegular().first(where: { $0.id == uuid }) {
                    let instances = try await manager.fetchActiveInstances(for: uuid)
                    if let instance = instances.first(where: { $0.dayKey == parts[2] }) {
                        currentGeneration = instance.notificationGeneration
                    } else {
                        return
                    }
                } else {
                    return
                }
            }
        } catch {
            return
        }

        // Игнорируем устаревшее поколение
        guard currentGeneration == generation else { return }

        // Переводим в SEEN и отменяем оставшиеся повторы
        do {
            if typePrefix == "ot" {
                try await manager.markOneTimeSeen(id: uuid)
            } else {
                let dayKey = String(parts[2])
                let instances = try await manager.fetchActiveInstances(for: uuid)
                if let instance = instances.first(where: { $0.dayKey == dayKey }) {
                    try await manager.markInstanceSeen(id: instance.id)
                }
            }

            // Отменяем оставшиеся уведомления этого поколения
            let pending = await scheduler.pendingRequests()
            let toCancel = pending
                .filter { $0.generation == generation }
                .map(\.id)
            await scheduler.cancel(ids: toCancel)

        } catch {
            // Игнорируем ошибки — задача могла быть уже удалена
        }
    }
}