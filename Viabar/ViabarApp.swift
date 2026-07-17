import AppKit
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
    private let trashModelContainer: ModelContainer

    // MARK: - Init

    init() {
        do {
            sharedModelContainer = try SharedModelContainer.makeMainAppContainer()
            trashModelContainer = try SharedModelContainer.makeTrashContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        do {
            try MainStoreDataMigrator.runPendingMigrations(
                in: sharedModelContainer.mainContext
            )
        } catch {
            print("[MainStoreDataMigration] failed: \(error.localizedDescription)")
        }

        let settings = AppSettingsStore.ensureDefaultSettings(in: sharedModelContainer.mainContext)
        AppSettingsStore.adoptViabarMenuBarIconDefaultIfNeeded(
            settings,
            in: sharedModelContainer.mainContext
        )

        // 初始化服务容器并注册核心服务
        let container = ServiceContainer()
        let projectService = container.registerProjectService(
            modelContext: sharedModelContainer.mainContext
        )
        projectService.configureSync(.default)

        let notificationScheduleService = container.registerNotificationScheduleService(
            modelContext: sharedModelContainer.mainContext
        )
        notificationScheduleService.configureCompleteAction { [weak projectService] ownerId, ownerKind in
            projectService?.completeReminderOwner(id: ownerId, kind: ownerKind)
        }
        let trashService = container.registerTrashService(
            modelContext: trashModelContainer.mainContext,
            projectModelContext: sharedModelContainer.mainContext,
            notificationScheduleService: notificationScheduleService
        )
        try? trashService.cleanupExpired(
            policy: TrashRetentionSettingsStore.policy()
        )
        _ = container.registerBackupService(
            modelContext: sharedModelContainer.mainContext,
            notificationScheduleService: notificationScheduleService,
            trashService: trashService
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
                    await Task.yield()
                    serviceContainer.notificationScheduleService?.start()
                    let settings = AppSettingsStore.ensureDefaultSettings(
                        in: sharedModelContainer.mainContext
                    )
                    AppAppearanceController.apply(storedTheme: settings.theme)
                    try? runtimeController.configureShortcuts(from: settings)
                    serviceContainer.backupService?.start(settings: settings)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    serviceContainer.notificationScheduleService?.applicationDidBecomeActive()
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
