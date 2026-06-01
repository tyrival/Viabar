import Foundation
import SwiftData

extension SharedModelContainer {
    static func makeTrashContainer(fileManager: FileManager = .default) throws -> ModelContainer {
        let shared = try sharedStoreURL(fileManager: fileManager)
        let trashURL = shared.deletingLastPathComponent().appending(path: trashStoreFileName)
        try fileManager.createDirectory(
            at: trashURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let trashSchema = Schema([TrashItem.self])
        let configuration = ModelConfiguration(
            "ViabarTrash",
            schema: trashSchema,
            url: trashURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: trashSchema, configurations: [configuration])
    }
}
