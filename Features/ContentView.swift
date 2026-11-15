import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            OneTimeView()
                .tabItem {
                    Label("Разовые", systemImage: "list.bullet")
                }

            RecurringView()
                .tabItem {
                    Label("Регулярные", systemImage: "repeat")
                }
        }
    }
}

struct OneTimeView: View {
    var body: some View {
        NavigationStack {
            Text("Разовые задачи")
                .navigationTitle("Разовые")
        }
    }
}

struct RecurringView: View {
    var body: some View {
        NavigationStack {
            Text("Регулярные задачи")
                .navigationTitle("Регулярные")
        }
    }
}

#Preview {
    ContentView()
}