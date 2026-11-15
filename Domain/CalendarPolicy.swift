import Foundation

/// Календарные политики. Чистый доменный компонент без SwiftUI, SwiftData и UserNotifications.
public enum CalendarPolicy {
    /// Текущий локальный календарный день (Device local time).
    public static var localDay: Date {
        Calendar.current.startOfDay(for: .now)
    }

    /// Строка формата `YYYY-MM-DD` в локальном часовом поясе устройства.
    /// Вычисляется строго через `Calendar.current`.
    public static func dayKey(for date: Date = .now) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = components.year, let m = components.month, let d = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// `DateComponents` текущего локального календаря для заданной даты.
    public static func localDateComponents(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    /// Начало локального календарного дня для заданной даты.
    public static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Следующий локальный календарный день.
    public static func nextLocalDay(after date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfDay(date)) ?? (startOfDay(date) + 86400)
    }
}