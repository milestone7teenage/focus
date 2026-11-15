import Foundation
import SwiftData

/// Базовая схема MVP v1.0. Без сложных миграций.
/// Используется в `ModelContainer` приложения и in-memory конфигурации для тестов.
public enum SchemaV1 {
    public static let schema = Schema([
        OneTimeTask.self,
        RegularTaskTemplate.self,
        DailyTaskInstance.self,
    ])
}