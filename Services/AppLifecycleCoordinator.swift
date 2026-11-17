import Foundation
import UserNotifications

/// Координатор жизненного цикла приложения.
/// Выполняет полную инициализацию/сверку при запуске и возврате в `.active`:
/// - загрузка данных
/// - определение локального дня
/// - `runDailyReset()`
/// - проверка разрешений на уведомления
/// - полная сверка очереди уведомлений (`NotificationScheduler.reconcile()`)
/// - обновление UI (через колбэк)
public final class AppLifecycleCoordinator: Sendable {
    private let manager: TaskManager
    private let scheduler: NotificationScheduler
    private let engine: ScheduleEngine
    private let onUIUpdate: @Sendable () async -> Void

    public init(
        manager: TaskManager,
        scheduler: NotificationScheduler,
        engine: ScheduleEngine,
        onUIUpdate: @escaping @Sendable () async -> Void
    ) {
        self.manager = manager
        self.scheduler = scheduler
        self.engine = engine
        self.onUIUpdate = onUIUpdate
    }

    /// Выполнять при запуске приложения и возврате в `.active`.
    public func onAppActive() async {
        // 1. Загрузка данных (TaskManager уже имеет доступ к репозиторию)

        // 2. Определение локального дня и reset
        try? await manager.runDailyReset()

        // 3. Проверка разрешений на уведомления
        let authorized = await scheduler.checkAuthorization()
        if !authorized {
            // UI предупреждение покажет ViewModel при необходимости
        }

        // 4. Полная сверка очереди уведомлений
        try? await scheduler.reconcile()

        // 5. Обновление UI
        await onUIUpdate()
    }

    /// Выполнять при уходе в background/inactive (если нужно).
    public func onAppInactive() async {
        // Здесь можно добавить логику, например, отмену ненужных запросов
    }
}