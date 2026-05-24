import SwiftUI
import SwiftData

@main
struct ViabarApp: App {

    // MARK: - State

    @State private var serviceContainer: ServiceContainer
    private let sharedModelContainer: ModelContainer

    // MARK: - Init

    init() {
        let schema = Schema([
            Project.self,
            Milestone.self,
            SubTask.self,
            Memo.self,
            Reminder.self,
            NotificationScheduleEntry.self,
            ArchiveFolder.self,
            ProjectTemplate.self,
            TemplateMilestone.self,
            TemplateSubTask.self,
        ])

        // iCloud sync 预留：替换为以下配置即可启用 CloudKit 同步
        // let modelConfiguration = ModelConfiguration(
        //     schema: schema,
        //     isStoredInMemoryOnly: false,
        //     cloudKitDatabase: .private("iCloud.com.viabar")
        // )
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            sharedModelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

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

        // Phase 2 预留：
        // let syncService = CloudSyncService(...)
        // container.register(syncService)
        // projectService.cloudSyncService = syncService

        _serviceContainer = State(initialValue: container)
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serviceContainer)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(sharedModelContainer)
    }
}
