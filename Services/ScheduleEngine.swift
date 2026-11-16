import Foundation
import SwiftData

/// Чистый доменный компонент без SwiftUI, SwiftData и UserNotifications.
/// Отвечает за локальный день, `dayKey`, ежедaily reset, DST, смену часового пояса
/// и перенос прошедшего сегодняшнего времени на завтра.
public actor ScheduleEngine {
    public init() {}

    // MARK: - dayKey

    /// Строка формата `YYYY-MM-DD` в локальном часовом поясе устройства.
    /// Вычисляется строго через `Calendar.current`.
    public func dayKey(for date: Date = .now) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = components.year, let m = components.month, let d = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Текущий локальный календарный день (Device local time).
    public func localDay() -> Date {
        Calendar.current.startOfDay(for: .now)
    }

    /// Начало локального календарного дня для заданной даты.
    public func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Следующий локальный календарный день.
    public func nextLocalDay(after date: Date) -> Date {
        let start = startOfDay(date)
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            return start.addingTimeInterval(86400)
        }
        return next
    }

    // MARK: - One-time task scheduling

    /// Проверяет и корректирует дату разовой задачи:
    /// - Если выбрана сегодняшняя дата и уже прошедшее время — дата переносится на завтра с тем же местным временем.
    /// - Будущее время не переносится.
    /// - Прошедшее время сегодня корректируется; завтрашняя дата не трогается.
    public func normalizeOneTimeDate(_ date: Date) -> Date {
        let today = startOfDay(.now)
        let tomorrow = nextLocalDay(after: today)
        let startOfTomorrow = startOfDay(tomorrow)

        let dateStart = startOfDay(date)

        // Завтра и позже — не трогаем.
        if dateStart >= startOfTomorrow {
            return date
        }

        // Прошлая дата (вчера и раньше) — не трогаем (DatePicker исключает выбор).
        if dateStart < today {
            return date
        }

        // Сегодня: проверим, прошло ли время.
        if date <= .now {
            // Переносим на завтра с тем же местным временем.
            let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            guard let next = Calendar.current.date(bySettingHour: components.hour ?? 0,
                                                  minute: components.minute ?? 0,
                                                  second: components.second ?? 0,
                                                  of: tomorrow) else {
                return date
            }
            return next
        }

        return date
    }

    // MARK: - Daily reset

    /// Идемпотентный ежедневный reset регулярных задач.
    /// - Находит устаревшие дневные экземпляры (dayKey != текущего локального дня).
    /// - Удаляет их без истории.
    /// - Обеспечивает ровно один актуальный PENDING-экземпляр для каждого активного шаблона (isEnabled == true).
    /// - Для отключённых шаблонов удаляет экземпляр на сегодня (если есть).
    /// - Приоритет reset над вчерашним snooze: snooze не переносится.
    /// - Не прибавляет 86 400 секунд для перехода на следующий календарный день.
    public func performReset(
        templates: [RegularTaskTemplate],
        instances: [DailyTaskInstance],
        deleteInstance: @Sendable (UUID) async throws -> Void,
        createInstance: @Sendable (DailyTaskInstance) async throws -> Void
    ) async throws {
        let currentDay = dayKey()

        // 1. Удаляем устаревшие экземпляры (dayKey != текущего локального дня).
        for instance in instances where instance.dayKey != currentDay {
            try await deleteInstance(instance.id)
        }

        // 2. Для каждого шаблона обрабатываем экземпляры на сегодня.
        for template in templates {
            let todayInstances = instances.filter { $0.templateID == template.id && $0.dayKey == currentDay }

            // Удаляем все экземпляры на сегодня для этого шаблона (включая дубликаты и экземпляры отключённых шаблонов)
            for instance in todayInstances {
                try await deleteInstance(instance.id)
            }

            // 3. Если шаблон включен — создаём новый PENDING-экземпляр.
            if template.isEnabled {
                let instance = DailyTaskInstance(
                    templateID: template.id,
                    template: template,
                    dayKey: currentDay,
                    state: .pending,
                    repeatCount: 0,
                    snoozedUntil: nil,
                    notificationGeneration: template.notificationGeneration
                )
                try await createInstance(instance)
            }
            // Если шаблон отключен — экземпляр на сегодня уже удалён, новый не создаём.
        }
    }
}

// MARK: - DST and timezone

extension ScheduleEngine {
    /// Проверяет, что локальный календарь корректно отражает переход DST.
    /// Возвращает true, если два соседних дня отличаются ровно на 24 часа (в локальном времени).
    public func isDSTTransitionConsistent() -> Bool {
        let today = startOfDay(.now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let diff = Calendar.current.dateComponents([.hour], from: yesterday, to: today).hour ?? 0
        return diff == 24
    }

    /// Возвращает текущее смещение локального часового пояса в секундах.
    public func currentTimeZoneOffset() -> Int {
        Calendar.current.timeZone.secondsFromGMT(for: .now)
    }
}