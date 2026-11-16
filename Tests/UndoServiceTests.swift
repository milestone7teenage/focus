import Foundation
import SwiftData
import XCTest
@testable import focus

@MainActor
final class UndoServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var scheduler: InMemoryNotificationScheduler!
    private var undoService: UndoService!
    private var repository: TaskRepository!
    private var engine: ScheduleEngine!

    override func setUp() async throws {
        container = try TestContainer.make()
        scheduler = InMemoryNotificationScheduler()
        repository = TaskRepository(modelContext: ModelContext(container))
        engine = ScheduleEngine()
    }

    override func tearDown() async throws {
        container = nil
        scheduler = nil
        undoService = nil
        repository = nil
        engine = nil
    }

    private func makeUndoService(lifecycle: @escaping () -> UndoService.LifecycleState) -> UndoService {
        UndoService(lifecycle: lifecycle)
    }

    private func makeManager() -> TaskManager {
        TaskManager(repository: repository, scheduler: scheduler, engine: engine)
    }

    func testUndoWithinWindowRestoresTask() async throws {
        var lifecycleState: UndoService.LifecycleState = .active
        undoService = makeUndoService(lifecycle: { lifecycleState })
        let manager = makeManager()

        let task = try await manager.createOneTime(title: "Quick undo", scheduledAt: Date(timeIntervalSinceNow: 600))
        let snapshot = try await manager.deleteOneTime(id: task.id)
        await undoService.store(snapshot: snapshot!)

        let restoredSnapshot = await undoService.undo()
        XCTAssertNotNil(restoredSnapshot, "Undo в пределах 3 секунд должен вернуть снимок")

        if let restoredSnapshot {
            try await manager.restore(snapshot: restoredSnapshot)
        }

        let remaining = try await repository.fetchAllOneTime()
        XCTAssertEqual(remaining.count, 1, "Задача восстановлена")
        XCTAssertEqual(remaining.first?.id, task.id)
    }

    func testUndoAfterExpiryFails() async throws {
        var lifecycleState: UndoService.LifecycleState = .active
        undoService = makeUndoService(lifecycle: { lifecycleState })
        let manager = makeManager()

        let task = try await manager.createOneTime(title: "Too late", scheduledAt: Date(timeIntervalSinceNow: 600))
        let snapshot = try await manager.deleteOneTime(id: task.id)
        await undoService.store(snapshot: snapshot!)

        // Ждём более 3 секунд, чтобы таймер истёк.
        try await Task.sleep(nanoseconds: 3_200_000_000)

        let restoredSnapshot = await undoService.undo()
        XCTAssertNil(restoredSnapshot, "Undo после 3 секунд должен быть недоступен")

        let remaining = try await repository.fetchAllOneTime()
        XCTAssertTrue(remaining.isEmpty, "Задача окончательно удалена")
    }

    func testSnapshotDestroyedOnBackground() async throws {
        var lifecycleState: UndoService.LifecycleState = .active
        undoService = makeUndoService(lifecycle: { lifecycleState })
        let manager = makeManager()

        let task = try await manager.createOneTime(title: "Background me", scheduledAt: Date(timeIntervalSinceNow: 600))
        let snapshot = try await manager.deleteOneTime(id: task.id)

        // Сворачиваем ДО сохранения снимка — снимок не должен сохраниться.
        lifecycleState = .background
        await undoService.store(snapshot: snapshot!)
        lifecycleState = .active

        let restoredSnapshot = await undoService.undo()
        XCTAssertNil(restoredSnapshot, "Снимок должен быть уничтожен при сворачивании/уходе в background")

        let remaining = try await repository.fetchAllOneTime()
        XCTAssertTrue(remaining.isEmpty, "Задача окончательно удалена при сворачивании")
    }

    func testSnapshotDestroyedOnInactive() async throws {
        var lifecycleState: UndoService.LifecycleState = .active
        undoService = makeUndoService(lifecycle: { lifecycleState })
        let manager = makeManager()

        let task = try await manager.createOneTime(title: "Inactive me", scheduledAt: Date(timeIntervalSinceNow: 600))
        let snapshot = try await manager.deleteOneTime(id: task.id)

        lifecycleState = .inactive
        await undoService.store(snapshot: snapshot!)
        lifecycleState = .active

        let restoredSnapshot = await undoService.undo()
        XCTAssertNil(restoredSnapshot, "Снимок уничтожается при inactive")
    }
}