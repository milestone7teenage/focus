import SwiftUI

/// Главный контейнер с двумя вкладками: «Разовые» и «Регулярные».
/// Компактная нижняя панель навигации с центральной кнопкой «+».
struct ContentView: View {
    @EnvironmentObject private var oneTimeVM: OneTimeTasksViewModel
    @EnvironmentObject private var recurringVM: RecurringTasksViewModel
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                OneTimeTasksView(viewModel: oneTimeVM)
                    .tag(0)
                    .tabItem {
                        Label("Разовые", systemImage: "list.bullet")
                            .font(.caption.weight(.medium))
                    }

                RecurringTasksView(viewModel: recurringVM)
                    .tag(1)
                    .tabItem {
                        Label("Регулярные", systemImage: "repeat")
                            .font(.caption.weight(.medium))
                    }
            }
            .tint(Color(.label))
            .padding(.bottom, 16)

            // Центральная кнопка «+» чуть выше вкладок
            VStack {
                Spacer()
                Button(action: {
                    if selectedTab == 0 {
                        oneTimeVM.onAdd()
                    } else {
                        recurringVM.onAdd()
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(DesignSystem.primaryText)
                        .frame(width: 48, height: 48)
                        .background(DesignSystem.cardBackground)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .accessibilityLabel("Добавить задачу")
                .padding(.bottom, 12)
            }
        }
    }
}
