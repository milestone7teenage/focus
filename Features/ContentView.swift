import SwiftUI

/// Главный контейнер с двумя вкладками: «Разовые» и «Регулярные».
struct ContentView: View {
    @StateObject private var oneTimeVM: OneTimeTasksViewModel
    @StateObject private var recurringVM: RecurringTasksViewModel

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
            OneTimeTasksView(viewModel: oneTimeVM)
                .tabItem {
                    Label("Разовые", systemImage: "list.bullet")
                }

            RecurringTasksView(viewModel: recurringVM)
                .tabItem {
                    Label("Регулярные", systemImage: "repeat")
                }
        }
        .tint(Color(.label))
    }
}