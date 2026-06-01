import Foundation
import SwiftData

enum TrashItemKind: String, Codable {
    case milestone
    case subTask
    case memo
}

extension TrashRetentionPolicy {
    func expiredItems(from items: [TrashItem], now: Date) -> [TrashItem] {
        let cutoff = now.addingTimeInterval(-Double(dayCount) * 86_400)
        return items.filter { $0.deletedAt < cutoff }
    }
}

struct TrashReminderSnapshot: Codable, Equatable {
    let type: String
    let fireTime: String?
    let fireTimestamp: Date?
    let repeatIntervalDays: Int?
    let lastTriggeredTimestamp: Date?
}

struct TrashSubTaskSnapshot: Codable, Equatable {
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let orderIndex: Int
    let reminder: TrashReminderSnapshot?
}

struct TrashTaskSnapshot: Codable, Equatable {
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let reminder: TrashReminderSnapshot?
    let subtasks: [TrashSubTaskSnapshot]
}

struct TrashMemoSnapshot: Codable, Equatable {
    let content: String
    let createdAt: Date
}

enum TrashPayload: Codable, Equatable {
    case task(TrashTaskSnapshot)
    case subTask(TrashSubTaskSnapshot)
    case memo(TrashMemoSnapshot)

    var kind: TrashItemKind {
        switch self {
        case .task: .milestone
        case .subTask: .subTask
        case .memo: .memo
        }
    }
}

enum TrashItemPayloadError: Error {
    case unsupportedVersion(Int)
}

@Model
final class TrashItem {
    @Attribute(.unique) var trashItemId: UUID
    var kind: String
    var deletedAt: Date
    var originalProjectId: UUID
    var originalProjectTitle: String
    var originalProjectAccentColor: String
    var originalProjectSymbolName: String
    var originalParentTaskId: UUID?
    var originalParentTaskTitle: String?
    var originalOrderIndex: Int
    var payloadVersion: Int
    var payloadData: Data

    init(
        trashItemId: UUID = UUID(),
        kind: TrashItemKind,
        deletedAt: Date = Date(),
        originalProjectId: UUID,
        originalProjectTitle: String,
        originalProjectAccentColor: String,
        originalProjectSymbolName: String,
        originalParentTaskId: UUID? = nil,
        originalParentTaskTitle: String? = nil,
        originalOrderIndex: Int,
        payloadVersion: Int,
        payloadData: Data
    ) {
        self.trashItemId = trashItemId
        self.kind = kind.rawValue
        self.deletedAt = deletedAt
        self.originalProjectId = originalProjectId
        self.originalProjectTitle = originalProjectTitle
        self.originalProjectAccentColor = originalProjectAccentColor
        self.originalProjectSymbolName = originalProjectSymbolName
        self.originalParentTaskId = originalParentTaskId
        self.originalParentTaskTitle = originalParentTaskTitle
        self.originalOrderIndex = originalOrderIndex
        self.payloadVersion = payloadVersion
        self.payloadData = payloadData
    }
}

extension TrashItem {
    static let currentPayloadVersion = 1

    func payload() throws -> TrashPayload {
        guard payloadVersion == Self.currentPayloadVersion else {
            throw TrashItemPayloadError.unsupportedVersion(payloadVersion)
        }
        return try JSONDecoder.backupDecoder.decode(TrashPayload.self, from: payloadData)
    }

    func copyText() throws -> String {
        switch try payload() {
        case .task(let snapshot):
            let subtasks = snapshot.subtasks
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { "- \($0.title)" }
            return ([snapshot.title] + subtasks).joined(separator: "\n")
        case .subTask(let snapshot):
            return snapshot.title
        case .memo(let snapshot):
            return snapshot.content
        }
    }

    func matches(_ query: String) throws -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        let copiedText = try copyText()
        return originalProjectTitle.localizedCaseInsensitiveContains(term)
            || displayPath.localizedCaseInsensitiveContains(term)
            || copiedText.localizedCaseInsensitiveContains(term)
    }

    var displayText: String {
        guard let payload = try? payload() else { return "" }
        switch payload {
        case .task(let snapshot):
            return snapshot.title
        case .subTask(let snapshot):
            return snapshot.title
        case .memo(let snapshot):
            return snapshot.content
        }
    }

    var displayPath: String {
        displayPath(language: .simplifiedChinese)
    }

    func displayPath(language: EffectiveAppLanguage) -> String {
        let task = AppLocalization.string("任务", language: language)
        let subTask = AppLocalization.string("子任务", language: language)
        let memo = AppLocalization.string("备忘录", language: language)
        switch TrashItemKind(rawValue: kind) {
        case .milestone:
            return "\(originalProjectTitle) / \(task)"
        case .subTask:
            let parent = originalParentTaskTitle.map(Self.compactParentTaskTitle) ?? task
            return "\(originalProjectTitle) / \(parent) / \(subTask)"
        case .memo:
            return "\(originalProjectTitle) / \(memo)"
        case nil:
            return originalProjectTitle
        }
    }

    private static func compactParentTaskTitle(_ title: String) -> String {
        guard title.count > 10 else { return title }
        return String(title.prefix(9)) + "…"
    }
}

enum TrashItemIndex {
    static func results(matching query: String, items: [TrashItem]) -> [TrashItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingItems = term.isEmpty
            ? items
            : items.filter { (try? $0.matches(term)) == true }
        return sortedNewestFirst(matchingItems)
    }

    static func sortedNewestFirst(_ items: [TrashItem]) -> [TrashItem] {
        items.sorted { $0.deletedAt > $1.deletedAt }
    }
}
