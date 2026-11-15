import SwiftUI
import SwiftData

@main
struct FocusApp: App {
    /// Minimal ModelContainer on an empty schema (no entity models yet).
    /// Models will be added in Stage 2 (ROADMAP.md) alongside their own schemas.
    private static let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Schema([]), configurations: [])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}