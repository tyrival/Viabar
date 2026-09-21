import AppKit
import SwiftUI
import SwiftData

@main
struct ViabarApp: App {

    // MARK: - State

    @NSApplicationDelegateAdaptor(ViabarAppDelegate.self) private var appDelegate
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
        _isMenuBarInserted = State(initialValue: settings.menuBarComponentEnabled)
        _menuBarIcon = State(initialValue: MenuBarIcon.resolve(settings.menuBarIcon))

        // 外部 URL（viabar://）统一由 AppKit 层接管，静默写入、不弹窗不抢焦点
        let runtime = AppRuntimeController()
        _runtimeController = State(initialValue: runtime)
        ExternalURLRouter.shared.configure(
            modelContext: sharedModelContainer.mainContext,
            projectService: projectService,
            runtimeController: runtime
        )
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
        // 关闭 WindowGroup 的「外部事件自动开窗」：URL 事件全部交给
        // ViabarAppDelegate → ExternalURLRouter 处理，避免外部投递时弹窗、抢焦点。
        // navigate 指令需要的显示/激活由 AppRuntimeController.showMainPanel() 完成。
        .handlesExternalEvents(matching: [])
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
