import SwiftUI

/// Главный контейнер с двумя вкладками: «Разовые» и «Регулярные».
struct ContentView: View {
    @StateObject private var oneTimeVM: OneTimeTasksViewModel
    @StateObject private var recurringVM: RecurringTasksViewModel

    init(manager: TaskManager) {
        _oneTimeVM = StateObject(wrappedValue: OneTimeTasksViewModel(manager: manager))
        _recurringVM = StateObject(wrappedValue: RecurringTasksViewModel(manager: manager))
    }

    var body: some View {
        TabView {
            OneTimeTasksView(
                tasks: oneTimeVM.tasks,
                onTaskTap: { _ in },
                onComplete: { id in Task { await oneTimeVM.onComplete(id) } },
                onSnooze: { id in Task { await oneTimeVM.onSnooze(id) } },
                onDelete: { id in Task { await oneTimeVM.onDelete(id) } },
                onUndo: { Task { await oneTimeVM.onUndo() } },
                onDismissUndo: { oneTimeVM.onDismissUndo() },
                onAdd: { oneTimeVM.onAdd() }
            )
            .tabItem {
                Label("Разовые", systemImage: "list.bullet")
            }

            RecurringTasksView(
                templates: recurringVM.templates,
                onTaskTap: { _ in },
                onComplete: { id in Task { await recurringVM.onComplete(id) } },
                onSnooze: { id in Task { await recurringVM.onSnooze(id) } },
                onDelete: { id in Task { await recurringVM.onDelete(id) } },
                onUndo: { Task { await recurringVM.onUndo() } },
                onDismissUndo: { recurringVM.onDismissUndo() },
                onAdd: { recurringVM.onAdd() }
            )
            .tabItem {
                Label("Регулярные", systemImage: "repeat")
            }
        }
        .tint(Color(.label)) // Монохромный акцент
        .task {
            await oneTimeVM.load()
            await recurringVM.load()
        }
        .onAppear {
            // Обновление при каждом появлении (возврат из бэкграунда)
            Task {
                await oneTimeVM.load()
                await recurringVM.load()
            }
        }
    }
}

#Preview {
    ContentView(manager: TaskManager(
        repository: TaskRepository(modelContext: try! ModelContainer(for: SchemaV1.schema).mainContext),
        scheduler: InMemoryNotificationScheduler(),
        engine: ScheduleEngine()
    ))
}