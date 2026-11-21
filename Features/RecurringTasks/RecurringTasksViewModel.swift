import Foundation
import SwiftUI
import Combine
import UserNotifications

/// ViewModel для вкладки «Регулярные» задачи.
@MainActor
public final class RecurringTasksViewModel: ObservableObject {
    @Published public var templates: [RegularTaskItem] = []
    @Published public var showUndoBanner = false
    @Published public var showCreateSheet = false
    @Published public var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

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
            await updateNotificationStatus()
        } catch { }
    }

    public func onAdd() {
        // Always open sheet regardless of notification permission
        showCreateSheet = true
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

    /// Called when user taps "Разрешить" in notification banner.
    /// Only requests authorization and updates status. Does NOT open create sheet.
    public func requestNotificationPermission() async {
        await notificationScheduler.requestAuthorization(options: [.alert, .sound, .badge])
        await updateNotificationStatus()
    }

    /// Call when app becomes active (e.g., returning from Settings)
    public func refreshNotificationStatus() async {
        await updateNotificationStatus()
    }

    /// ✅ D-04: Вызывается при возврате из background для обновления данных
    public func refresh() async {
        await load()
    }

    private func updateNotificationStatus() async {
        let status = await notificationScheduler.authorizationStatus()
        await MainActor.run {
            self.notificationAuthorizationStatus = status
        }
    }
}