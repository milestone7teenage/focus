import Foundation

/// Состояние напоминания.
/// `pending` и `seen` — состояния. `completed`/`deleted` — действия, а не архивные состояния:
/// после них активная запись удаляется.
public enum ReminderState: String, CaseIterable, Sendable, Codable {
    case pending
    case seen
}