import Foundation
import SwiftData

/// Дневной экземпляр регулярной задачи — состояние текущей календарной даты.
/// `dayKey` — строка формата `YYYY-MM-DD` в локальном часовом поясе устройства,
/// вычисляется строго через `Calendar.current`.
/// `templateID` дублирует связь с шаблоном для стабильной фильтрации в `#Predicate`.
/// Для одного шаблона допускается не более одного активного экземпляра на текущий локальный день.
@Model
public final class DailyTaskInstance {
    @Attribute(.unique) public var id: UUID
    public var templateID: UUID
    public var template: RegularTaskTemplate?
    public var dayKey: String
    public var state: ReminderState
    public var repeatCount: Int
    public var snoozedUntil: Date?
    public var notificationGeneration: Int

    public init(
        id: UUID = UUID(),
        templateID: UUID,
        template: RegularTaskTemplate?,
        dayKey: String,
        state: ReminderState = .pending,
        repeatCount: Int = 0,
        snoozedUntil: Date? = nil,
        notificationGeneration: Int = 0
    ) {
        self.id = id
        self.templateID = templateID
        self.template = template
        self.dayKey = dayKey
        self.state = state
        self.repeatCount = repeatCount
        self.snoozedUntil = snoozedUntil
        self.notificationGeneration = notificationGeneration
    }
}