import Foundation
import SwiftUI
import Combine

/// ViewModel для вкладки «Разовые» задачи.
/// Связывает UI с TaskManager, управляет состоянием списка и Undo.
@MainActor
public final class OneTimeTasksViewModel: ObservableObject {
    @Published public var tasks: [OneTimeTaskItem] = []
    @Published public var showUndoBanner = false

    private let manager: TaskManager
    private var undoSnapshot: TaskSnapshot?
    private var undoItem: OneTimeTaskItem?

    public init(manager: TaskManager) {
        self.manager = manager
    }

    public func load() async {
        do {
            let all = try await manager.fetchAllOneTime()
            tasks = all.map { OneTimeTaskItem(id: $0.id, title: $0.title, scheduledAt: $0.scheduledAt, isSeen: $0.state == .seen) }
        } catch {
            // Handle error silently for MVP
        }
    }

    public func onAdd() {
        // Sheet presentation handled by view
    }

    public func onTaskTap(_ item: OneTimeTaskItem) {
        // Future: edit sheet
    }

    public func onComplete(_ id: UUID) async {
        do {
            try await manager.completeOneTime(id: id)
            await load()
        } catch { }
    }

    public func onSnooze(_ id: UUID) async {
        do {
            try await manager.snoozeOneTime(id: id)
            await load()
        } catch { }
    }

    public func onDelete(_ id: UUID) async {
        do {
            if let snapshot = try await manager.deleteOneTime(id: id) {
                undoSnapshot = snapshot
                undoItem = tasks.first { $0.id == id }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showUndoBanner = true
                }
                await load()
            }
        } catch { }
    }

    public func onUndo() async {
        guard let snapshot = undoSnapshot else { return }
        do {
            try await manager.restore(snapshot: snapshot)
            undoSnapshot = nil
            undoItem = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showUndoBanner = false
            }
            await load()
        } catch { }
    }

    public func onDismissUndo() {
        undoSnapshot = nil
        undoItem = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showUndoBanner = false
        }
    }
}