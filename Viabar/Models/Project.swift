import Foundation
import SwiftData

// MARK: - ProjectStyle

struct ProjectStyle: Codable, Equatable {
    var backgroundColor: String  // hex color, e.g. "#FF6B6B"
    var sfSymbol: String         // SF Symbol name, e.g. "circle.dashed"

    static let `default` = ProjectStyle(
        backgroundColor: ViabarColor.primaryHex,
        sfSymbol: "circle.dashed"
    )
}

// MARK: - Reminder

@Model
final class Reminder {
    var reminderId: UUID
    var type: String          // "single" or "repeating"
    var fireTime: String?     // "HH:mm" for repeating type
    var fireTimestamp: Date?  // absolute fire time for single type
    var repeatIntervalDays: Int?
    var lastTriggeredTimestamp: Date?

    init(
        type: String,
        fireTime: String? = nil,
        fireTimestamp: Date? = nil,
        repeatIntervalDays: Int? = nil
    ) {
        self.reminderId = UUID()
        self.type = type
        self.fireTime = fireTime
        self.fireTimestamp = fireTimestamp
        self.repeatIntervalDays = repeatIntervalDays
    }
}

// MARK: - Project

@Model
final class Project {
    @Attribute(.unique) var projectId: UUID
    var title: String
    var hideCompleted: Bool
    var isArchived: Bool = false
    var orderIndex: Int = 0
    var archivedAt: Date?
    var accentColor: String = ViabarColor.primaryHex
    var sfSymbolName: String = "circle.dashed"

    @Relationship(deleteRule: .cascade, inverse: \Milestone.project)
    var milestones: [Milestone] = []

    @Relationship(deleteRule: .cascade, inverse: \Memo.project)
    var memos: [Memo] = []

    @Relationship(deleteRule: .cascade)
    var reminder: Reminder?

    var archiveFolder: ArchiveFolder?

    init(title: String, hideCompleted: Bool = true, orderIndex: Int = 0) {
        self.projectId = UUID()
        self.title = title
        self.hideCompleted = hideCompleted
        self.isArchived = false
        self.orderIndex = orderIndex
    }

    // MARK: - 3.2.1 Rollup 进度计算

    /// 项目总进度 = Σ(S_i / N)
    /// - N: 里程碑总数（权重均等 = 1/N）
    /// - 无子任务的里程碑：完成得 1.0，未完成得 0
    /// - 有 M 个子任务的里程碑：S = 已完成子任务数 / M
    var progress: Double {
        guard !milestones.isEmpty else { return 0 }

        // 全部完成 → 直接返回 1.0，避免浮点累加误差
        if milestones.allSatisfy({ $0.score >= 1.0 }) {
            return 1.0
        }

        let N = Double(milestones.count)
        let total = milestones.reduce(0.0) { sum, milestone in
            sum + milestone.weightedScore / N
        }
        // 四舍五入到 4 位小数，消除 IEEE 754 累加漂移
        return (total * 10000).rounded() / 10000
    }

    /// 3.2.2 上下文穿透：最顶端未完成的任务标题
    /// 返回第一个 isCompleted == false 的里程碑，
    /// 若该里程碑包含子任务，则精确定位到第一个未完成的子任务。
    var topUnfinishedTitle: String? {
        guard let first = milestones
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .first(where: { !$0.isCompleted })
        else { return nil }

        if first.subtasks.isEmpty {
            return first.title
        }

        let unfinishedSub = first.subtasks
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .first(where: { !$0.isCompleted })

        return unfinishedSub?.title ?? first.title
    }

    /// 3.2.4 报告引擎：给定时间区间内完成的里程碑
    func completedMilestones(between start: Date, and end: Date) -> [Milestone] {
        milestones.filter { $0.isCompleted }
    }

    /// 3.2.4 报告引擎：当前周期未完成的里程碑（用于"下周计划"）
    var unfinishedMilestones: [Milestone] {
        milestones.filter { !$0.isCompleted }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }
}

// MARK: - Milestone

@Model
final class Milestone {
    @Attribute(.unique) var milestoneId: UUID
    var title: String
    var isCompleted: Bool
    var orderIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \SubTask.milestone)
    var subtasks: [SubTask] = []

    @Relationship(deleteRule: .cascade)
    var reminder: Reminder?

    var project: Project?

    init(title: String, orderIndex: Int = 0, isCompleted: Bool = false) {
        self.milestoneId = UUID()
        self.title = title
        self.orderIndex = orderIndex
        self.isCompleted = isCompleted
    }

    /// 单里程碑的自身进度：无子任务 → 0 或 1，有子任务 → completed/M
    var score: Double {
        guard !subtasks.isEmpty else {
            return isCompleted ? 1.0 : 0.0
        }
        let M = Double(subtasks.count)
        guard M > 0 else { return isCompleted ? 1.0 : 0.0 }
        return Double(subtasks.filter(\.isCompleted).count) / M
    }

    /// 供 Project.rollup 使用的加权前分数（等同于 score）
    var weightedScore: Double { score }

    /// 从子任务状态反推里程碑完成状态。
    /// 仅当存在子任务时生效；无子任务时维持手动设定的状态。
    func syncCompletionFromSubtasks() {
        guard !subtasks.isEmpty else { return }
        isCompleted = subtasks.allSatisfy(\.isCompleted)
    }
}

// MARK: - SubTask

@Model
final class SubTask {
    @Attribute(.unique) var taskId: UUID
    var title: String
    var isCompleted: Bool
    var orderIndex: Int

    @Relationship(deleteRule: .cascade)
    var reminder: Reminder?

    var milestone: Milestone?

    init(title: String, orderIndex: Int = 0, isCompleted: Bool = false) {
        self.taskId = UUID()
        self.title = title
        self.orderIndex = orderIndex
        self.isCompleted = isCompleted
    }
}

// MARK: - Memo

@Model
final class Memo {
    @Attribute(.unique) var memoId: UUID
    var content: String
    var createdAt: Date

    var project: Project?

    init(content: String, createdAt: Date = Date()) {
        self.memoId = UUID()
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - ArchiveFolder

@Model
final class ArchiveFolder {
    @Attribute(.unique) var folderId: UUID
    var name: String
    var orderIndex: Int

    @Relationship(deleteRule: .nullify, inverse: \Project.archiveFolder)
    var projects: [Project] = []

    var parent: ArchiveFolder?

    @Relationship(deleteRule: .cascade, inverse: \ArchiveFolder.parent)
    var children: [ArchiveFolder] = []

    var isRoot: Bool { parent == nil }

    /// 递归展平——用于列表渲染时将树形结构展开为带缩进层级的线性列表
    var flattenedWithDepth: [(folder: ArchiveFolder, depth: Int)] {
        var result: [(ArchiveFolder, Int)] = []
        flatten(into: &result, depth: 0)
        return result
    }

    private func flatten(into result: inout [(ArchiveFolder, Int)], depth: Int) {
        let sorted = children.sorted { $0.orderIndex < $1.orderIndex }
        for child in sorted {
            result.append((child, depth))
            child.flatten(into: &result, depth: depth + 1)
        }
    }

    init(name: String, orderIndex: Int = 0, parent: ArchiveFolder? = nil) {
        self.folderId = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.parent = parent
    }
}
