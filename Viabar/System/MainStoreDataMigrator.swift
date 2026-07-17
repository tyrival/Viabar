import Foundation
import SwiftData

@MainActor
enum MainStoreDataMigrator {
    static let currentVersion = 1
    static let versionKey = "mainStoreDataMigrationVersion"

    static func runPendingMigrations(
        in modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) throws {
        var completedVersion = defaults.integer(forKey: versionKey)

        do {
            if completedVersion < 1 {
                _ = try removeOrphanReminders(in: modelContext)
                completedVersion = 1
                defaults.set(completedVersion, forKey: versionKey)
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    static func removeOrphanReminders(in modelContext: ModelContext) throws -> Int {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let milestones = try modelContext.fetch(FetchDescriptor<Milestone>())
        let subTasks = try modelContext.fetch(FetchDescriptor<SubTask>())

        var referencedIDs = Set<PersistentIdentifier>()
        projects.compactMap(\.reminder?.persistentModelID).forEach { referencedIDs.insert($0) }
        milestones.compactMap(\.reminder?.persistentModelID).forEach { referencedIDs.insert($0) }
        subTasks.compactMap(\.reminder?.persistentModelID).forEach { referencedIDs.insert($0) }

        let reminders = try modelContext.fetch(FetchDescriptor<Reminder>())
        let orphans = reminders.filter { !referencedIDs.contains($0.persistentModelID) }
        guard !orphans.isEmpty else { return 0 }

        orphans.forEach { modelContext.delete($0) }
        try modelContext.save()
        return orphans.count
    }
}
