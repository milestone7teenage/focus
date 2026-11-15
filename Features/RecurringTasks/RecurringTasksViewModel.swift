import Foundation
import SwiftUI
import Combine

/// ViewModel для вкладки «Регулярные» задачи.
@MainActor
public final class RecurringTasksViewModel: ObservableObject {
    @Published public var templates: [RegularTaskItem] = []
    @Published public var showUndoBanner = false
    @Published public var notificationPermissionDenied = false

    public let manager: TaskManager
    public let notificationScheduler: NotificationScheduler

    private var undoSnapshot: TaskSnapshot?
    private var undoItem: RegularTaskItem?

    public init(manager: TaskManager, notificationScheduler: NotificationScheduler) {
        self.manager = manager
        self.notificationScheduler = notificationScheduler
    }

    public func load() async {
        do {
            let allTemplates = try await manager.fetchAllRegular()
            var items: [RegularTaskItem] = []

            for template in allTemplates {
                let instances = try await manager.fetchActiveInstances(for: template.id)
                let todayInstance = instances.first { $0.dayKey == CalendarPolicy.dayKey(for: .now) }

                items.append(RegularTaskItem(
                    id: template.id,
                    title: template.title,
                    localHour: template.localHour,
                    localMinute: template.localMinute,
                    isEnabled: template.isEnabled,
                    instanceState: todayInstance?.state,
                    instanceSnoozedUntil: todayInstance?.snoozedUntil
                ))
            }
            templates = items
        } catch { }
    }

    public func onAdd() {
        // Sheet presentation handled by view
    }

    public func onTaskTap(_ item: RegularTaskItem) {
        // Future: edit sheet
    }

    public func onComplete(_ id: UUID) async {
        do {
            let instances = try await manager.fetchActiveInstances(for: id)
            if let instance = instances.first(where: { $0.dayKey == CalendarPolicy.dayKey(for: .now) }) {
                try await manager.completeInstance(id: instance.id)
            }
            await load()
        } catch { }
    }

    public func onSnooze(_ id: UUID) async {
        do {
            let instances = try await manager.fetchActiveInstances(for: id)
            if let instance = instances.first(where: { $0.dayKey == CalendarPolicy.dayKey(for: .now) }) {
                try await manager.snoozeInstance(id: instance.id)
            }
            await load()
        } catch { }
    }

    public func onDelete(_ id: UUID) async {
        do {
            if let snapshot = try await manager.deleteRegular(id: id) {
                undoSnapshot = snapshot
                undoItem = templates.first { $0.id == id }
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