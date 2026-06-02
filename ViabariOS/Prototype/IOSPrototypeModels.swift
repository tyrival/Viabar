import Foundation

struct IOSPrototypeProject: Identifiable, Hashable {
    let id: UUID
    var title: String
    var accentHex: String
    var symbol: String
    var isFavorite: Bool
    var isArchived: Bool
    var archiveFolderID: UUID?
    var reminderDate: Date?
    var milestones: [IOSPrototypeMilestone]
    var memos: [IOSPrototypeMemo]

    var progress: Double {
        guard !milestones.isEmpty else { return 0 }
        let total = milestones.reduce(0.0) { $0 + $1.score }
        return ((total / Double(milestones.count)) * 10000).rounded() / 10000
    }

    var topUnfinishedMilestone: IOSPrototypeMilestone? {
        milestones
            .sorted { $0.orderIndex < $1.orderIndex }
            .first { $0.score < 1 }
    }
}

struct IOSPrototypeArchiveFolder: Identifiable, Hashable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var orderIndex: Int
}

struct IOSPrototypeMilestone: Identifiable, Hashable {
    let id: UUID
    var title: String
    var orderIndex: Int
    var isCompleted: Bool
    var reminderDate: Date?
    var subtasks: [IOSPrototypeSubTask]

    var score: Double {
        guard !subtasks.isEmpty else { return isCompleted ? 1 : 0 }
        return Double(subtasks.filter(\.isCompleted).count) / Double(subtasks.count)
    }

    var firstUnfinishedSubtask: IOSPrototypeSubTask? {
        subtasks
            .sorted { $0.orderIndex < $1.orderIndex }
            .first { !$0.isCompleted }
    }
}

struct IOSPrototypeSubTask: Identifiable, Hashable {
    let id: UUID
    var title: String
    var orderIndex: Int
    var isCompleted: Bool
    var reminderDate: Date?
}

struct IOSPrototypeMemo: Identifiable, Hashable {
    let id: UUID
    var content: String
    var createdAt: Date
}

enum IOSPrototypeHomeTab: Hashable {
    case overview
    case reports
    case archive
}

enum IOSPrototypeDetailTab: Hashable {
    case tasks
    case memos
}

enum IOSPrototypeSearchTarget: Hashable {
    case project
    case milestone(milestoneID: UUID)
    case subtask(milestoneID: UUID, subtaskID: UUID)
    case memo(memoID: UUID)
}

struct IOSPrototypeSearchResult: Identifiable, Hashable {
    let id: String
    let projectID: UUID
    let detailTab: IOSPrototypeDetailTab
    let target: IOSPrototypeSearchTarget
    let title: String
    let path: String
}

struct IOSPrototypeNavigationRequest: Identifiable, Hashable {
    let id = UUID()
    let projectID: UUID
    let target: IOSPrototypeSearchTarget
}
