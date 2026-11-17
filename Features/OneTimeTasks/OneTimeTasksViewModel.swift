import Foundation
import SwiftUI
import Combine
import UserNotifications

/// ViewModel для вкладки «Разовые» задачи.
@MainActor
public final class OneTimeTasksViewModel: ObservableObject {
    @Published public var tasks: [OneTimeTaskItem] = []
    @Published public var showUndoBanner = false
    @Published public var showCreateSheet = false
    @Published public var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    public let manager: TaskManager
    public let notificationScheduler: NotificationScheduler

    private var undoSnapshot: TaskSnapshot?
    private var undoItem: OneTimeTaskItem?

    public init(manager: TaskManager, notificationScheduler: NotificationScheduler) {
        self.manager = manager
        self.notificationScheduler = notificationScheduler
    }

    public func load() async {
        do {
            let all = try await manager.fetchAllOneTime()
            tasks = all.map { OneTimeTaskItem(id: $0.id, title: $0.title, scheduledAt: $0.scheduledAt, isSeen: $0.state == .seen) }
            await updateNotificationStatus()
        } catch { }
    }

    public func onAdd() {
        // Always open sheet regardless of notification permission
        showCreateSheet = true
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

    private func updateNotificationStatus() async {
        let status = await notificationScheduler.authorizationStatus()
        await MainActor.run {
            self.notificationAuthorizationStatus = status
        }
    }
}