import SwiftUI
import SwiftData

@main
struct FocusApp: App {
    /// Minimal ModelContainer on the MVP v1.0 schema (`SchemaV1`).
    /// Entity models are introduced here alongside their own schemas (Stage 2).
    private static let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: SchemaV1.schema, configurations: [])
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