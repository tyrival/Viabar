import AppKit
import Observation
import SwiftData

enum TrashRestoreAvailability: Equatable {
    case available
    case missingProject
    case missingParentTask
}

enum TrashServiceError: Error {
    case missingProject
    case missingParentTask
}

@MainActor
@Observable
final class TrashService {
    private static let pageSize = 40

    private let modelContext: ModelContext
    private let projectModelContext: ModelContext
    private let notificationScheduleService: NotificationScheduleService
    private(set) var items: [TrashItem] = []
    private(set) var hasMoreItems = false

    init(
        modelContext: ModelContext,
        projectModelContext: ModelContext,
        notificationScheduleService: NotificationScheduleService
    ) {
        self.modelContext = modelContext
        self.projectModelContext = projectModelContext
        self.notificationScheduleService = notificationScheduleService
        refreshItems()
    }

    func store(_ milestone: Milestone, deletedAt: Date = Date()) throws {
        guard let project = owningProject(for: milestone) else {
            throw TrashServiceError.missingProject
        }
        let payload = TrashPayload.task(
            TrashTaskSnapshot(
                title: milestone.title,
                isCompleted: milestone.isCompleted,
                completedAt: milestone.completedAt,
                reminder: reminderSnapshot(milestone.reminder),
                subtasks: milestone.subtasks.map(subTaskSnapshot)
            )
        )
        modelContext.insert(try makeItem(
            payload: payload,
            project: project,
            deletedAt: deletedAt,
            originalOrderIndex: milestone.orderIndex
        ))
        try modelContext.save()
        refreshItems()
    }

    func store(_ subTask: SubTask, deletedAt: Date = Date()) throws {
        guard let milestone = owningMilestone(for: subTask) else {
            throw TrashServiceError.missingParentTask
        }
        guard let project = owningProject(for: milestone) else {
            throw TrashServiceError.missingProject
        }
        modelContext.insert(try makeItem(
            payload: .subTask(subTaskSnapshot(subTask)),
            project: project,
            deletedAt: deletedAt,
            originalParentTaskId: milestone.milestoneId,
            originalParentTaskTitle: milestone.title,
            originalOrderIndex: subTask.orderIndex
        ))
        try modelContext.save()
        refreshItems()
    }

    func store(_ memo: Memo, deletedAt: Date = Date()) throws {
        guard let project = owningProject(for: memo) else {
            throw TrashServiceError.missingProject
        }
        modelContext.insert(try makeItem(
            payload: .memo(TrashMemoSnapshot(content: memo.content, createdAt: memo.createdAt)),
            project: project,
            deletedAt: deletedAt,
            originalOrderIndex: memo.orderIndex
        ))
        try modelContext.save()
        refreshItems()
    }

    func restoreAvailability(for item: TrashItem) -> TrashRestoreAvailability {
        guard let project = project(id: item.originalProjectId) else {
            return .missingProject
        }
        guard TrashItemKind(rawValue: item.kind) == .subTask else {
            return .available
        }
        guard let parentID = item.originalParentTaskId,
              milestone(id: parentID, in: project) != nil
        else {
            return .missingParentTask
        }
        return .available
    }

    func restore(_ item: TrashItem) throws {
        guard let project = project(id: item.originalProjectId) else {
            throw TrashServiceError.missingProject
        }

        switch try item.payload() {
        case .task(let snapshot):
            let milestone = Milestone(
                title: snapshot.title,
                orderIndex: item.originalOrderIndex,
                isCompleted: snapshot.isCompleted
            )
            milestone.completedAt = snapshot.completedAt
            milestone.reminder = restoreReminder(snapshot.reminder)
            milestone.project = project
            projectModelContext.insert(milestone)
            project.milestones.append(milestone)

            for snapshot in snapshot.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let subTask = restoreSubTask(snapshot)
                subTask.milestone = milestone
                projectModelContext.insert(subTask)
                milestone.subtasks.append(subTask)
                notificationScheduleService.syncSubTask(subTask, project: project)
            }
            normalizeMilestoneOrder(in: project)
            notificationScheduleService.syncMilestone(milestone, project: project)
            notificationScheduleService.syncProject(project)

        case .subTask(let snapshot):
            guard let parentID = item.originalParentTaskId,
                  let milestone = milestone(id: parentID, in: project)
            else {
                throw TrashServiceError.missingParentTask
            }
            let subTask = restoreSubTask(snapshot)
            subTask.orderIndex = item.originalOrderIndex
            subTask.milestone = milestone
            projectModelContext.insert(subTask)
            milestone.subtasks.append(subTask)
            normalizeSubTaskOrder(in: milestone)
            milestone.syncCompletionFromSubtasks()
            notificationScheduleService.syncSubTask(subTask, project: project)
            notificationScheduleService.syncProject(project)

        case .memo(let snapshot):
            let memo = Memo(
                content: snapshot.content,
                createdAt: snapshot.createdAt,
                orderIndex: item.originalOrderIndex
            )
            memo.project = project
            projectModelContext.insert(memo)
            project.memos.append(memo)
            normalizeMemoOrder(in: project)
        }

        try projectModelContext.save()
        modelContext.delete(item)
        try modelContext.save()
        refreshItems()
    }

    func copyToPasteboard(_ item: TrashItem) throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(try item.copyText(), forType: .string)
    }

    func cleanupExpired(
        policy: TrashRetentionPolicy,
        now: Date = Date()
    ) throws {
        let items = try modelContext.fetch(FetchDescriptor<TrashItem>())
        for item in policy.expiredItems(from: items, now: now) {
            modelContext.delete(item)
        }
        try modelContext.save()
        refreshItems()
    }

    func allItems() -> [TrashItem] {
        let descriptor = FetchDescriptor<TrashItem>(
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func loadNextPage() {
        guard hasMoreItems else { return }
        var descriptor = FetchDescriptor<TrashItem>(
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        descriptor.fetchOffset = items.count
        descriptor.fetchLimit = Self.pageSize
        let nextItems = (try? modelContext.fetch(descriptor)) ?? []
        items.append(contentsOf: nextItems)
        hasMoreItems = nextItems.count == Self.pageSize
    }

    func replaceItems(with replacement: [TrashItem]) throws {
        for item in allItems() {
            modelContext.delete(item)
        }
        for item in replacement {
            modelContext.insert(item)
        }
        try modelContext.save()
        refreshItems()
    }

    private func makeItem(
        payload: TrashPayload,
        project: Project,
        deletedAt: Date,
        originalParentTaskId: UUID? = nil,
        originalParentTaskTitle: String? = nil,
        originalOrderIndex: Int
    ) throws -> TrashItem {
        TrashItem(
            kind: payload.kind,
            deletedAt: deletedAt,
            originalProjectId: project.projectId,
            originalProjectTitle: project.title,
            originalProjectAccentColor: project.accentColor,
            originalProjectSymbolName: project.sfSymbolName,
            originalParentTaskId: originalParentTaskId,
            originalParentTaskTitle: originalParentTaskTitle,
            originalOrderIndex: originalOrderIndex,
            payloadVersion: TrashItem.currentPayloadVersion,
            payloadData: try JSONEncoder.backupEncoder.encode(payload)
        )
    }

    private func reminderSnapshot(_ reminder: Reminder?) -> TrashReminderSnapshot? {
        reminder.map {
            TrashReminderSnapshot(
                type: $0.type,
                fireTime: $0.fireTime,
                fireTimestamp: $0.fireTimestamp,
                repeatIntervalDays: $0.repeatIntervalDays,
                lastTriggeredTimestamp: $0.lastTriggeredTimestamp
            )
        }
    }

    private func subTaskSnapshot(_ subTask: SubTask) -> TrashSubTaskSnapshot {
        TrashSubTaskSnapshot(
            title: subTask.title,
            isCompleted: subTask.isCompleted,
            completedAt: subTask.completedAt,
            orderIndex: subTask.orderIndex,
            reminder: reminderSnapshot(subTask.reminder)
        )
    }

    private func restoreSubTask(_ snapshot: TrashSubTaskSnapshot) -> SubTask {
        let subTask = SubTask(
            title: snapshot.title,
            orderIndex: snapshot.orderIndex,
            isCompleted: snapshot.isCompleted
        )
        subTask.completedAt = snapshot.completedAt
        subTask.reminder = restoreReminder(snapshot.reminder)
        return subTask
    }

    private func restoreReminder(_ snapshot: TrashReminderSnapshot?) -> Reminder? {
        guard let snapshot else { return nil }
        let reminder = Reminder(
            type: snapshot.type,
            fireTime: snapshot.fireTime,
            fireTimestamp: snapshot.fireTimestamp,
            repeatIntervalDays: snapshot.repeatIntervalDays
        )
        reminder.lastTriggeredTimestamp = snapshot.lastTriggeredTimestamp
        projectModelContext.insert(reminder)
        return reminder
    }

    private func project(id: UUID) -> Project? {
        allProjects().first { $0.projectId == id }
    }

    private func milestone(id: UUID, in project: Project) -> Milestone? {
        project.milestones.first { $0.milestoneId == id }
    }

    private func owningProject(for milestone: Milestone) -> Project? {
        milestone.project
            ?? allProjects().first { project in
                project.milestones.contains { $0.milestoneId == milestone.milestoneId }
            }
    }

    private func owningMilestone(for subTask: SubTask) -> Milestone? {
        subTask.milestone
            ?? allProjects()
                .flatMap(\.milestones)
                .first { milestone in
                    milestone.subtasks.contains { $0.taskId == subTask.taskId }
                }
    }

    private func owningProject(for memo: Memo) -> Project? {
        memo.project
            ?? allProjects().first { project in
                project.memos.contains { $0.memoId == memo.memoId }
            }
    }

    private func allProjects() -> [Project] {
        (try? projectModelContext.fetch(FetchDescriptor<Project>())) ?? []
    }

    private func refreshItems() {
        items = []
        hasMoreItems = true
        loadNextPage()
    }

    private func normalizeMilestoneOrder(in project: Project) {
        let items = project.milestones.sorted { $0.orderIndex < $1.orderIndex }
        for (index, item) in items.enumerated() {
            item.orderIndex = index
        }
    }

    private func normalizeSubTaskOrder(in milestone: Milestone) {
        let items = milestone.subtasks.sorted { $0.orderIndex < $1.orderIndex }
        for (index, item) in items.enumerated() {
            item.orderIndex = index
        }
    }

    private func normalizeMemoOrder(in project: Project) {
        let items = project.memos.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.orderIndex < $1.orderIndex
        }
        for (index, item) in items.enumerated() {
            item.orderIndex = index
        }
    }
}

extension ServiceContainer {
    var trashService: TrashService? {
        resolve(TrashService.self)
    }

    func registerTrashService(
        modelContext: ModelContext,
        projectModelContext: ModelContext,
        notificationScheduleService: NotificationScheduleService
    ) -> TrashService {
        let service = TrashService(
            modelContext: modelContext,
            projectModelContext: projectModelContext,
            notificationScheduleService: notificationScheduleService
        )
        register(service)
        return service
    }
}
