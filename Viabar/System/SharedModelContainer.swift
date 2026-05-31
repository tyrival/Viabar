import Foundation
import OSLog
import SwiftData

enum SharedStoreError: Error {
    case appGroupUnavailable
    case sharedStoreUnavailable
}

enum SharedModelContainer {
    static let appGroupIdentifier = "group.com.tyrival.Viabar"
    static let storeFileName = "default.store"
    static let migrationMarkerFileName = ".viabar-shared-store-v1"
    static let widgetKind = "ViabarLargeWidget"

    private static let logger = Logger(
        subsystem: "com.tyrival.Viabar",
        category: "SharedModelContainer"
    )

    static var schema: Schema {
        Schema([
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
            AppSettings.self,
        ])
    }

    static func sharedStoreURL(fileManager: FileManager = .default) throws -> URL {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedStoreError.appGroupUnavailable
        }
        return containerURL
            .appending(path: "ViabarSharedStore", directoryHint: .isDirectory)
            .appending(path: storeFileName)
    }

    static func legacyStoreURL(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: storeFileName)
    }

    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Viabar",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeMainAppContainer(fileManager: FileManager = .default) throws -> ModelContainer {
        let legacy = try legacyStoreURL(fileManager: fileManager)
        do {
            let shared = try sharedStoreURL(fileManager: fileManager)
            try SharedStoreMigrator.migrateStoreFilesIfNeeded(
                legacyStoreURL: legacy,
                sharedStoreURL: shared,
                fileManager: fileManager,
                validate: { candidate in
                    _ = try makeContainer(storeURL: candidate)
                }
            )
            try fileManager.createDirectory(
                at: shared.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try makeContainer(storeURL: shared)
        } catch {
            logger.error(
                "Shared store migration failed; using legacy store: \(String(describing: error), privacy: .public)"
            )
            return try makeContainer(storeURL: legacy)
        }
    }

    static func makeWidgetContainer(fileManager: FileManager = .default) throws -> ModelContainer {
        let shared = try sharedStoreURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: shared.path) else {
            throw SharedStoreError.sharedStoreUnavailable
        }
        return try makeContainer(storeURL: shared)
    }
}

enum SharedStoreMigrator {
    private static let suffixes = ["", "-wal", "-shm"]

    static func migrateStoreFilesIfNeeded(
        legacyStoreURL: URL,
        sharedStoreURL: URL,
        fileManager: FileManager = .default,
        validate: (URL) throws -> Void
    ) throws {
        guard fileManager.fileExists(atPath: legacyStoreURL.path),
              !fileManager.fileExists(atPath: sharedStoreURL.path)
        else { return }

        let sharedStoreDirectory = sharedStoreURL.deletingLastPathComponent()
        let temporaryDirectory = sharedStoreDirectory
            .deletingLastPathComponent()
            .appending(
                path: ".viabar-migration-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let candidateURL = temporaryDirectory.appending(path: sharedStoreURL.lastPathComponent)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        do {
            for suffix in suffixes {
                let source = URL(fileURLWithPath: legacyStoreURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(
                    at: source,
                    to: URL(fileURLWithPath: candidateURL.path + suffix)
                )
            }

            try validate(candidateURL)
            try Data().write(
                to: temporaryDirectory.appending(path: SharedModelContainer.migrationMarkerFileName)
            )
            if fileManager.fileExists(atPath: sharedStoreDirectory.path) {
                let contents = try fileManager.contentsOfDirectory(
                    at: sharedStoreDirectory,
                    includingPropertiesForKeys: nil
                )
                guard contents.isEmpty else {
                    throw SharedStoreError.sharedStoreUnavailable
                }
                try fileManager.removeItem(at: sharedStoreDirectory)
            }
            try fileManager.moveItem(at: temporaryDirectory, to: sharedStoreDirectory)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }
}
