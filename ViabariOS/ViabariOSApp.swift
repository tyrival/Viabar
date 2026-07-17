//
//  ViabariOSApp.swift
//  ViabariOS
//
//  Created by 周晨煜 on 6/2/26.
//

import SwiftUI
import SwiftData

@main
struct ViabariOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var serviceContainer: ServiceContainer
    private let sharedModelContainer: ModelContainer
    private let trashModelContainer: ModelContainer

    init() {
        do {
            sharedModelContainer = try SharedModelContainer.makeIOSAppContainer()
            trashModelContainer = try SharedModelContainer.makeTrashContainer()
        } catch {
            fatalError("Could not create iOS ModelContainer: \(error)")
        }

        do {
            try MainStoreDataMigrator.runPendingMigrations(
                in: sharedModelContainer.mainContext
            )
        } catch {
            print("[MainStoreDataMigration] failed: \(error.localizedDescription)")
        }

        _ = AppSettingsStore.ensureDefaultSettings(in: sharedModelContainer.mainContext)

        let container = ServiceContainer()
        let projectService = container.registerProjectService(modelContext: sharedModelContainer.mainContext)
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
        try? trashService.cleanupExpired(policy: TrashRetentionSettingsStore.policy())
        _serviceContainer = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serviceContainer)
                .task {
                    await Task.yield()
                    serviceContainer.notificationScheduleService?.start()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    serviceContainer.notificationScheduleService?.applicationDidBecomeActive()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
