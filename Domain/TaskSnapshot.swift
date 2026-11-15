import Foundation

/// DTO-снимок для Undo. Хранится в памяти на 3 секунды после удаления.
/// При сворачивании/закрытии приложения снимок уничтожается мгновенно — задача считается окончательно удалённой.
public enum TaskSnapshot {
    case oneTime(OneTimeSnapshot)
    case recurring(RecurringSnapshot)
}

public struct OneTimeSnapshot: Sendable, Codable {
    public let id: UUID
    public let title: String
    public let scheduledAt: Date
    public let state: ReminderState
    public let createdAt: Date
    public let repeatCount: Int
    public let notificationGeneration: Int

    public init(_ task: OneTimeTask) {
        id = task.id
        title = task.title
        scheduledAt = task.scheduledAt
        state = task.state
        createdAt = task.createdAt
        repeatCount = task.repeatCount
        notificationGeneration = task.notificationGeneration
    }
}

public struct RecurringSnapshot: Sendable, Codable {
    public let templateID: UUID
    public let templateTitle: String
    public let localHour: Int
    public let localMinute: Int
    public let isEnabled: Bool
    public let createdAt: Date
    public let templateGeneration: Int

    public let instanceID: UUID?
    public let instanceDayKey: String?
    public let instanceState: ReminderState?
    public let instanceRepeatCount: Int?
    public let instanceSnoozedUntil: Date?
    public let instanceGeneration: Int?

    public init(template: RegularTaskTemplate, instance: DailyTaskInstance?) {
        templateID = template.id
        templateTitle = template.title
        localHour = template.localHour
        localMinute = template.localMinute
        isEnabled = template.isEnabled
        createdAt = template.createdAt
        templateGeneration = template.notificationGeneration

        if let instance {
            instanceID = instance.id
            instanceDayKey = instance.dayKey
            instanceState = instance.state
            instanceRepeatCount = instance.repeatCount
            instanceSnoozedUntil = instance.snoozedUntil
            instanceGeneration = instance.notificationGeneration
        } else {
            instanceID = nil
            instanceDayKey = nil
            instanceState = nil
            instanceRepeatCount = nil
            instanceSnoozedUntil = nil
            instanceGeneration = nil
        }
    }
}