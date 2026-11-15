import Foundation
import SwiftData

/// Репозиторий для задач. CRUD + undo-поддержка. Актор — безопасно с `SWIFT_STRICT_CONCURRENCY`.
public actor TaskRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - OneTimeTask

    public func createOneTime(_ task: OneTimeTask) throws {
        modelContext.insert(task)
        try save()
    }

    public func fetchOneTime(id: UUID) throws -> OneTimeTask? {
        try modelContext.fetch(FetchDescriptor<OneTimeTask>(predicate: #Predicate { $0.id == id })).first
    }

    public func fetchAllOneTime() throws -> [OneTimeTask] {
        try modelContext.fetch(FetchDescriptor<OneTimeTask>(sortBy: [SortDescriptor(\.scheduledAt, order: .forward)]))
    }

    public func updateOneTime(_ task: OneTimeTask) throws {
        try save()
    }

    /// Мгновенное удаление из SwiftData. Снимок для Undo хранится отдельно в памяти.
    public func deleteOneTime(id: UUID) throws {
        if let task = try fetchOneTime(id: id) {
            modelContext.delete(task)
            try save()
        }
    }

    // MARK: - RegularTaskTemplate

    public func createRegular(_ template: RegularTaskTemplate) throws {
        modelContext.insert(template)
        try save()
    }

    public func fetchRegular(id: UUID) throws -> RegularTaskTemplate? {
        try modelContext.fetch(FetchDescriptor<RegularTaskTemplate>(predicate: #Predicate { $0.id == id })).first
    }

    public func fetchAllRegular() throws -> [RegularTaskTemplate] {
        try modelContext.fetch(FetchDescriptor<RegularTaskTemplate>(sortBy: [SortDescriptor(\.title)]))
    }

    public func updateRegular(_ template: RegularTaskTemplate) throws {
        try save()
    }

    /// Удаление шаблона и всех его дневных экземпляров.
    public func deleteRegular(id: UUID) throws {
        if let template = try fetchRegular(id: id) {
            let instances = try modelContext.fetch(FetchDescriptor<DailyTaskInstance>(predicate: #Predicate { $0.templateID == id }))
            for instance in instances {
                modelContext.delete(instance)
            }
            modelContext.delete(template)
            try save()
        }
    }

    // MARK: - DailyTaskInstance

    public func fetchInstance(id: UUID) throws -> DailyTaskInstance? {
        try modelContext.fetch(FetchDescriptor<DailyTaskInstance>(predicate: #Predicate { $0.id == id })).first
    }

    public func fetchInstances(for templateID: UUID) throws -> [DailyTaskInstance] {
        try modelContext.fetch(FetchDescriptor<DailyTaskInstance>(predicate: #Predicate { $0.templateID == templateID }))
    }

    public func fetchInstance(dayKey: String, templateID: UUID) throws -> DailyTaskInstance? {
        try modelContext.fetch(FetchDescriptor<DailyTaskInstance>(
            predicate: #Predicate {
                $0.templateID == templateID && $0.dayKey == dayKey
            }
        )).first
    }

    /// Все дневные экземпляры (для reset).
    public func fetchAllInstances() throws -> [DailyTaskInstance] {
        try modelContext.fetch(FetchDescriptor<DailyTaskInstance>())
    }

    public func createInstance(_ instance: DailyTaskInstance) throws {
        modelContext.insert(instance)
        try save()
    }

    public func deleteInstance(id: UUID) throws {
        if let instance = try fetchInstance(id: id) {
            modelContext.delete(instance)
            try save()
        }
    }

    public func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}