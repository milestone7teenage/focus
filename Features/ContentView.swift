import SwiftUI

/// Главный контейнер с двумя вкладками: «Разовые» и «Регулярные».
struct ContentView: View {
    @EnvironmentObject private var oneTimeVM: OneTimeTasksViewModel
    @EnvironmentObject private var recurringVM: RecurringTasksViewModel

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