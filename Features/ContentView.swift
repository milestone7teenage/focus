import SwiftUI

/// Главный контейнер с двумя вкладками: «Разовые» и «Регулярные».
struct ContentView: View {
    @StateObject private var oneTimeVM: OneTimeTasksViewModel
    @StateObject private var recurringVM: RecurringTasksViewModel
    @State private var showNotificationAlert = false

    init(manager: TaskManager, notificationScheduler: NotificationScheduler) {
        _oneTimeVM = StateObject(wrappedValue: OneTimeTasksViewModel(
            manager: manager,
            notificationScheduler: notificationScheduler
        ))
        _recurringVM = StateObject(wrappedValue: RecurringTasksViewModel(
            manager: manager,
            notificationScheduler: notificationScheduler
        ))
    }

    var body: some View {
        TabView {
            OneTimeTasksView(
                tasks: oneTimeVM.tasks,
                showUndoBanner: $oneTimeVM.showUndoBanner,
                onTaskTap: { _ in },
                onComplete: { id in Task { await oneTimeVM.onComplete(id) } },
                onSnooze: { id in Task { await oneTimeVM.onSnooze(id) } },
                onDelete: { id in Task { await oneTimeVM.onDelete(id) } },
                onUndo: { Task { await oneTimeVM.onUndo() } },
                onDismissUndo: { oneTimeVM.onDismissUndo() },
                onAdd: { oneTimeVM.onAdd() },
                notificationPermissionDenied: oneTimeVM.notificationPermissionDenied
            )
            .tabItem {
                Label("Разовые", systemImage: "list.bullet")
            }

            RecurringTasksView(
                templates: recurringVM.templates,
                showUndoBanner: $recurringVM.showUndoBanner,
                onTaskTap: { _ in },
                onComplete: { id in Task { await recurringVM.onComplete(id) } },
                onSnooze: { id in Task { await recurringVM.onSnooze(id) } },
                onDelete: { id in Task { await recurringVM.onDelete(id) } },
                onUndo: { Task { await recurringVM.onUndo() } },
                onDismissUndo: { recurringVM.onDismissUndo() },
                onAdd: { recurringVM.onAdd() },
                notificationPermissionDenied: recurringVM.notificationPermissionDenied
            )
            .tabItem {
                Label("Регулярные", systemImage: "repeat")
            }
        }
        .tint(Color(.label))
        .task {
            await oneTimeVM.load()
            await recurringVM.load()
            // Проверка разрешения на уведомления при запуске
            let authorized = await oneTimeVM.notificationScheduler.checkAuthorization()
            if !authorized {
                oneTimeVM.notificationPermissionDenied = true
                recurringVM.notificationPermissionDenied = true
            }
        }
        .onAppear {
            Task {
                await oneTimeVM.load()
                await recurringVM.load()
            }
        }
        .alert("Уведомления отключены", isPresented: $showNotificationAlert) {
            Button("Настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Для работы напоминаний включите уведомления в системных настройках.")
        }
        .onChange(of: oneTimeVM.notificationPermissionDenied) { _, new in
            showNotificationAlert = new
        }
    }
}