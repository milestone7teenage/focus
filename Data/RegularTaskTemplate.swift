import Foundation
import SwiftData

/// Постоянный шаблон ежедневной задачи.
/// Хранит название и местное время (localHour/localMinute).
@Model
public final class RegularTaskTemplate {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var localHour: Int
    public var localMinute: Int
    public var isEnabled: Bool
    public var createdAt: Date
    public var notificationGeneration: Int

    public init(
        id: UUID = UUID(),
        title: String,
        localHour: Int,
        localMinute: Int,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        notificationGeneration: Int = 0
    ) {
        self.id = id
        self.title = title
        self.localHour = localHour
        self.localMinute = localMinute
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.notificationGeneration = notificationGeneration
    }
}