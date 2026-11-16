import SwiftUI
import SwiftData
import UserNotifications

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

    /// AppDelegate для ранней установки UNUserNotificationCenterDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Shared lifecycle provider
    private static let lifecycleProvider = AppLifecycleProvider()

    /// Shared services
    @State private var manager: TaskManager
    @State private var undoService: UndoService
    @State private var notificationScheduler: NotificationScheduler
    @State private var notificationActionHandler: NotificationActionHandler
    @State private var lifecycleCoordinator: AppLifecycleCoordinator

    init() {
        let context = ModelContext(Self.modelContainer)
        let repository = TaskRepository(modelContext: context)
        let engine = ScheduleEngine()

        // Real notification adapter for production
        let adapter = RealNotificationCenterAdapter()
        let notifScheduler = NotificationScheduler(
            adapter: adapter,
            repository: repository,
            engine: engine
        )

        let actionHandler = NotificationActionHandler(
            manager: TaskManager(repository: repository, scheduler: notifScheduler, engine: engine),
            scheduler: notifScheduler
        )

        let undo = UndoService(
            lifecycle: Self.lifecycleProvider.lifecycleProvider
        )

        let coordinator = AppLifecycleCoordinator(
            manager: TaskManager(repository: repository, scheduler: notifScheduler, engine: engine),
            scheduler: notifScheduler,
            engine: engine,
            onUIUpdate: { /* UI обновляется через @Published в ViewModels */ }
        )

        self._manager = State(wrappedValue: TaskManager(
            repository: repository,
            scheduler: notifScheduler,
            engine: engine
        ))
        self._undoService = State(wrappedValue: undo)
        self._notificationScheduler = State(wrappedValue: notifScheduler)
        self._notificationActionHandler = State(wrappedValue: actionHandler)
        self._lifecycleCoordinator = State(wrappedValue: coordinator)

        // Устанавливаем делегат после инициализации всех stored properties
        appDelegate.setNotificationActionHandler(actionHandler)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager, notificationScheduler: notificationScheduler)
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
            Task {
                await lifecycleCoordinator.onAppActive()
            }
        case .inactive:
            Self.lifecycleProvider.setState(.inactive)
            Task { await undoService.cancel() }
            Task { await lifecycleCoordinator.onAppInactive() }
        case .background:
            Self.lifecycleProvider.setState(.background)
            Task { await undoService.cancel() }
        @unknown default:
            break
        }
    }
}