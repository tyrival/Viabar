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

        _ = AppSettingsStore.ensureDefaultSettings(in: sharedModelContainer.mainContext)

        let container = ServiceContainer()
        _ = container.registerProjectService(modelContext: sharedModelContainer.mainContext)
        let notificationScheduleService = container.registerNotificationScheduleService(
            modelContext: sharedModelContainer.mainContext
        )
        notificationScheduleService.start()
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
        }
        .modelContainer(sharedModelContainer)
    }
}
