import SwiftUI
import SwiftData

@main
struct ViabarApp: App {

    // MARK: - State

    @State private var serviceContainer: ServiceContainer
    @State private var runtimeController: AppRuntimeController
    @State private var isMenuBarInserted: Bool
    @State private var menuBarIcon: MenuBarIcon
    private let sharedModelContainer: ModelContainer

    // MARK: - Init

    init() {
        do {
            sharedModelContainer = try SharedModelContainer.makeMainAppContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        let settings = AppSettingsStore.ensureDefaultSettings(in: sharedModelContainer.mainContext)

        // 初始化服务容器并注册核心服务
        let container = ServiceContainer()
        let projectService = container.registerProjectService(
            modelContext: sharedModelContainer.mainContext
        )
        projectService.configureSync(.default)

        let notificationScheduleService = container.registerNotificationScheduleService(
            modelContext: sharedModelContainer.mainContext
        )
        notificationScheduleService.start()
        _ = container.registerBackupService(
            modelContext: sharedModelContainer.mainContext,
            notificationScheduleService: notificationScheduleService
        )

        let updateService = container.registerUpdateService()
        updateService.automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
        updateService.start()

        // Phase 2 预留：
        // let syncService = CloudSyncService(...)
        // container.register(syncService)
        // projectService.cloudSyncService = syncService

        _serviceContainer = State(initialValue: container)
        _runtimeController = State(initialValue: AppRuntimeController())
        _isMenuBarInserted = State(initialValue: settings.menuBarComponentEnabled)
        _menuBarIcon = State(initialValue: MenuBarIcon.resolve(settings.menuBarIcon))
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 1080, minHeight: 700)
                .environment(serviceContainer)
                .environment(runtimeController)
                .task {
                    let settings = AppSettingsStore.ensureDefaultSettings(
                        in: sharedModelContainer.mainContext
                    )
                    AppAppearanceController.apply(storedTheme: settings.theme)
                    try? runtimeController.configureShortcuts(from: settings)
                    serviceContainer.backupService?.start(settings: settings)
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新...") {
                    serviceContainer.updateService?.checkForUpdates()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1260, height: 820)
        .modelContainer(sharedModelContainer)

        MenuBarExtra(isInserted: $isMenuBarInserted) {
            MenuBarPanelView()
                .environment(serviceContainer)
                .environment(runtimeController)
        } label: {
            MenuBarStatusLabelView(icon: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView(
                onMenuBarEnabledChange: { isMenuBarInserted = $0 },
                onMenuBarIconChange: { menuBarIcon = $0 }
            )
                .environment(serviceContainer)
                .environment(runtimeController)
                .modelContainer(sharedModelContainer)
        }
    }
}
