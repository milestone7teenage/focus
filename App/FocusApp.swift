import SwiftUI
import SwiftData

@main
struct FocusApp: App {
    /// Minimal ModelContainer on the MVP v1.0 schema (`SchemaV1`).
    private static let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: SchemaV1.schema, configurations: [])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// Shared lifecycle provider
    private static let lifecycleProvider = AppLifecycleProvider()

    /// Shared services
    @State private var manager: TaskManager
    @State private var undoService: UndoService

    init() {
        let context = ModelContext(Self.modelContainer)
        let repository = TaskRepository(modelContext: context)
        let scheduler = InMemoryNotificationScheduler()
        let engine = ScheduleEngine()

        let undo = UndoService(
            lifecycle: Self.lifecycleProvider.lifecycleProvider
        ) { snapshot in
            Task { @MainActor in
                let context = ModelContext(Self.modelContainer)
                let repo = TaskRepository(modelContext: context)
                let mgr = TaskManager(repository: repo, scheduler: InMemoryNotificationScheduler(), engine: ScheduleEngine())
                try await mgr.restore(snapshot: snapshot)
            }
        }

        self._manager = State(wrappedValue: TaskManager(
            repository: repository,
            scheduler: scheduler,
            engine: engine
        ))
        self._undoService = State(wrappedValue: undo)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
        .modelContainer(Self.modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Self.lifecycleProvider.setState(.active)
            Task { try? await manager.runDailyReset() }
        case .inactive:
            Self.lifecycleProvider.setState(.inactive)
            undoService.cancel()
        case .background:
            Self.lifecycleProvider.setState(.background)
            undoService.cancel()
        @unknown default:
            break
        }
    }
}