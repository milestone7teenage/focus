import Foundation

/// Публичные модели для отображения задач в UI.
/// Используются в `OneTimeTasksView`, `RecurringTasksView`, `TaskCard` и ViewModels.

/// Разовая задача для отображения в списке.
public struct OneTimeTaskItem: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let scheduledAt: Date
    public let isSeen: Bool

    public init(id: UUID, title: String, scheduledAt: Date, isSeen: Bool) {
        self.id = id
        self.title = title
        self.scheduledAt = scheduledAt
        self.isSeen = isSeen
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.locale = Locale.current
        return formatter.string(from: scheduledAt)
    }

    public var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(scheduledAt)
    }
}

/// Регулярная задача с текущим дневным экземпляром для отображения в списке.
public struct RegularTaskItem: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let localHour: Int
    public let localMinute: Int
    public let isEnabled: Bool
    public let instanceState: ReminderState?
    public let instanceSnoozedUntil: Date?

    public init(
        id: UUID,
        title: String,
        localHour: Int,
        localMinute: Int,
        isEnabled: Bool,
        instanceState: ReminderState? = nil,
        instanceSnoozedUntil: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.localHour = localHour
        self.localMinute = localMinute
        self.isEnabled = isEnabled
        self.instanceState = instanceState
        self.instanceSnoozedUntil = instanceSnoozedUntil
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        let date = Calendar.current.date(bySettingHour: localHour, minute: localMinute, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }

    public var isSeen: Bool {
        instanceState == .seen
    }
}