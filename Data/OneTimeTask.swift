import Foundation
import SwiftData

/// Разовая задача с фиксированной датой и временем.
/// Привязка к местному времени устройства — через `DateComponents` текущего локального календаря.
/// При Snooze напрямую обновляется `scheduledAt = now + 30 минут` и состояние сбрасывается в `.pending`.
/// Поле `snoozedUntil` отсутствует — оно есть только в `DailyTaskInstance`.
@Model
public final class OneTimeTask {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var scheduledAt: Date
    public var state: ReminderState
    public var createdAt: Date
    public var repeatCount: Int
    public var notificationGeneration: Int

    public init(
        id: UUID = UUID(),
        title: String,
        scheduledAt: Date,
        state: ReminderState = .pending,
        createdAt: Date = .now,
        repeatCount: Int = 0,
        notificationGeneration: Int = 0
    ) {
        self.id = id
        self.title = title
        self.scheduledAt = scheduledAt
        self.state = state
        self.createdAt = createdAt
        self.repeatCount = repeatCount
        self.notificationGeneration = notificationGeneration
    }
}