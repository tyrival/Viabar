import Foundation
import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Service Registry

/// 轻量服务注册中心，统一管理所有业务服务实例，
/// 供 View 层通过 Environment 注入和获取。
@MainActor
@Observable
final class ServiceContainer {
    private var services: [ObjectIdentifier: AnyObject] = [:]

    func register<T: AnyObject>(_ service: T) {
        services[ObjectIdentifier(T.self)] = service
    }

    func resolve<T: AnyObject>(_ type: T.Type) -> T? {
        services[ObjectIdentifier(type)] as? T
    }
}

// MARK: - ProjectServiceProtocol

protocol ProjectServiceProtocol: AnyObject {
    // Project CRUD
    func createProject(title: String, hideCompleted: Bool, orderIndex: Int, template: ProjectTemplate?) -> Project
    func allProjects() -> [Project]
    func updateProject(_ project: Project)
    func updateProjectDisplayPreferences(_ project: Project)
    func deleteProject(_ project: Project)
    func toggleFavorite(_ project: Project)

    // Milestone
    func addMilestone(to project: Project, title: String, orderIndex: Int?) -> Milestone
    func deleteMilestone(_ milestone: Milestone)
    func updateReminder(_ reminder: Reminder?, for milestone: Milestone)

    // SubTask
    func addSubTask(to milestone: Milestone, title: String, orderIndex: Int?) -> SubTask
    func deleteSubTask(_ subTask: SubTask)
    func updateReminder(_ reminder: Reminder?, for subTask: SubTask)

    // Memo
    func addMemo(to project: Project, content: String) -> Memo
    func deleteMemo(_ memo: Memo)
    func reorderMemos(in project: Project, movingID: UUID, targetID: UUID?, placement: ReorderPlacement)

    // Batch
    func toggleMilestoneComplete(_ milestone: Milestone)
    func toggleSubTaskComplete(_ subTask: SubTask)

    // Archive & Folders
    func archiveProject(_ project: Project, to folder: ArchiveFolder)
    func unarchiveProject(_ project: Project)
    func createArchiveFolder(name: String, parent: ArchiveFolder?) -> ArchiveFolder
    func deleteArchiveFolder(_ folder: ArchiveFolder)
    func moveProjectToFolder(_ project: Project, folder: ArchiveFolder)
    func moveFolder(_ folder: ArchiveFolder, to parent: ArchiveFolder?)
    func reorderFolders(in parent: ArchiveFolder?, fromOffsets: IndexSet, toOffset: Int)
    func fetchRootFolders() -> [ArchiveFolder]
    func allActiveProjects() -> [Project]

    // Reorder
    func reorderActiveProjects(fromOffsets: IndexSet, toOffset: Int)
    func reorderActiveProject(movingID: UUID, targetID: UUID?, placement: ReorderPlacement)
    func reorderMilestones(in project: Project, movingID: UUID, targetID: UUID?, placement: ReorderPlacement)
    func moveSubTask(_ subTaskID: UUID, to targetMilestoneID: UUID, targetSubTaskID: UUID?, placement: ReorderPlacement)
    func reorderFolderProjects(_ folder: ArchiveFolder, fromOffsets: IndexSet, toOffset: Int)
    func reorderFolders(fromOffsets: IndexSet, toOffset: Int)

    func saveTemplate(
        _ template: ProjectTemplate?,
        name: String,
        hideCompleted: Bool,
        accentColor: String,
        sfSymbolName: String,
        milestones: [(title: String, subtasks: [String])]
    ) -> ProjectTemplate
    func deleteTemplate(_ template: ProjectTemplate)

    func save()
}

enum ReorderPlacement: Equatable {
    case before
    case after
    case end
}

// MARK: - ProjectService

/// 项目核心业务服务 —— 负责 Project / Milestone / SubTask / Memo 的 CRUD，
/// 封装 SwiftData 持久化细节，并预置 iCloud 同步对接接口。
@MainActor
@Observable
final class ProjectService: ProjectServiceProtocol {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let container: ServiceContainer

    private var notificationScheduleService: NotificationScheduleService? {
        container.notificationScheduleService
    }

    // MARK: - Sync State (reserved for CloudSyncService)

    private(set) var syncStatus: SyncStatus = .idle
    private(set) var lastSyncDate: Date?
    private(set) var syncConfig: CloudSyncConfig?
    private(set) var syncHistory: [SyncEvent] = []

    /// CloudSyncService 实现 —— Phase 2 注入
    weak var cloudSyncService: CloudSyncServiceProtocol?

    // MARK: - Init

    init(modelContext: ModelContext, container: ServiceContainer) {
        self.modelContext = modelContext
        self.container = container
    }

    // MARK: - Project CRUD

    @discardableResult
    func createProject(
        title: String,
        hideCompleted: Bool = true,
        orderIndex: Int = 0,
        template: ProjectTemplate? = nil
    ) -> Project {
        let activeProjects = allActiveProjects()
        let insertionIndex = min(max(orderIndex, 0), activeProjects.count)

        for (index, existingProject) in activeProjects.enumerated() {
            existingProject.orderIndex = index < insertionIndex ? index : index + 1
        }

        let project = Project(
            title: title,
            hideCompleted: template?.hideCompleted ?? hideCompleted,
            orderIndex: insertionIndex
        )
        modelContext.insert(project)
        if let template {
            copyTaskTree(from: template, to: project)
        }
        save()
        return project
    }

    func allProjects() -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func updateProject(_ project: Project) {
        // SwiftData auto-tracks changes on managed objects,
        // keeping this as an explicit entry point for future side-effects (sync, undo, etc.)
        save()
        syncReminderTimeline(for: project)
    }

    func updateProjectDisplayPreferences(_ project: Project) {
        // Display-only settings should not rewrite reminder timeline entries.
        save()
    }

    func deleteProject(_ project: Project) {
        notificationScheduleService?.removeEntries(projectId: project.projectId)
        modelContext.delete(project)
        save()
    }

    func toggleFavorite(_ project: Project) {
        project.isFavorite.toggle()
        save()
    }

    // MARK: - Milestone CRUD

    @discardableResult
    func addMilestone(to project: Project, title: String, orderIndex: Int? = nil) -> Milestone {
        let idx = orderIndex ?? project.milestones.count
        let milestone = Milestone(title: title, orderIndex: idx)
        milestone.project = project
        project.milestones.append(milestone)
        save()
        syncProjectReminder(project)
        return milestone
    }

    func deleteMilestone(_ milestone: Milestone) {
        let project = milestone.project
        guard let trashService = container.trashService else { return }
        do {
            try trashService.store(milestone)
        } catch {
            return
        }
        notificationScheduleService?.removeEntry(ownerId: milestone.milestoneId)
        milestone.subtasks.forEach { notificationScheduleService?.removeEntry(ownerId: $0.taskId) }
        modelContext.delete(milestone)
        save()
        if let project {
            syncProjectReminder(project)
        }
    }

    func updateReminder(_ reminder: Reminder?, for milestone: Milestone) {
        print("[ProjectService] updateReminder(milestone: \(milestone.milestoneId)) reminderId=\(reminder?.reminderId.uuidString ?? "nil") fireTimestamp=\(String(describing: reminder?.fireTimestamp))")
        milestone.reminder = reminder
        save()
        guard let project = milestone.project else { return }
        notificationScheduleService?.syncMilestone(milestone, project: project)
    }

    func toggleMilestoneComplete(_ milestone: Milestone) {
        TaskCompletionMutation.toggle(milestone)
        save()
        if let project = milestone.project {
            syncReminderTimeline(for: project)
        }
    }

    // MARK: - SubTask CRUD

    @discardableResult
    func addSubTask(to milestone: Milestone, title: String, orderIndex: Int? = nil) -> SubTask {
        let idx = orderIndex ?? milestone.subtasks.count
        let subtask = SubTask(title: title, orderIndex: idx)
        subtask.milestone = milestone
        milestone.subtasks.append(subtask)
        milestone.syncCompletionFromSubtasks()
        save()
        if let project = milestone.project {
            syncProjectReminder(project)
        }
        return subtask
    }

    func deleteSubTask(_ subTask: SubTask) {
        let milestone = subTask.milestone
        let project = milestone?.project
        guard let trashService = container.trashService else { return }
        do {
            try trashService.store(subTask)
        } catch {
            return
        }
        notificationScheduleService?.removeEntry(ownerId: subTask.taskId)
        modelContext.delete(subTask)
        milestone?.syncCompletionFromSubtasks()
        save()
        if let project {
            syncProjectReminder(project)
        }
    }

    func updateReminder(_ reminder: Reminder?, for subTask: SubTask) {
        print("[ProjectService] updateReminder(subTask: \(subTask.taskId)) reminderId=\(reminder?.reminderId.uuidString ?? "nil") fireTimestamp=\(String(describing: reminder?.fireTimestamp))")
        subTask.reminder = reminder
        save()
        guard let project = subTask.milestone?.project else { return }
        notificationScheduleService?.syncSubTask(subTask, project: project)
    }

    func toggleSubTaskComplete(_ subTask: SubTask) {
        TaskCompletionMutation.toggle(subTask)
        save()
        if let project = subTask.milestone?.project {
            syncReminderTimeline(for: project)
        }
    }

    // MARK: - Memo CRUD

    @discardableResult
    func addMemo(to project: Project, content: String) -> Memo {
        normalizeMemoOrder(in: project)
        let memo = Memo(content: content, orderIndex: project.memos.count)
        memo.project = project
        project.memos.append(memo)
        save()
        return memo
    }

    func deleteMemo(_ memo: Memo) {
        guard let trashService = container.trashService else { return }
        do {
            try trashService.store(memo)
        } catch {
            return
        }
        modelContext.delete(memo)
        save()
    }

    // MARK: - Archive & Folders

    func archiveProject(_ project: Project, to folder: ArchiveFolder) {
        project.isArchived = true
        project.archivedAt = Date()
        project.archiveFolder = folder
        save()
        notificationScheduleService?.removeEntries(projectId: project.projectId)
    }

    func unarchiveProject(_ project: Project) {
        project.isArchived = false
        project.archivedAt = nil
        project.archiveFolder = nil
        // 移回活跃列表末尾
        project.orderIndex = allActiveProjects().count
        save()
        syncReminderTimeline(for: project)
    }

    @discardableResult
    func createArchiveFolder(name: String, parent: ArchiveFolder? = nil) -> ArchiveFolder {
        let siblings = folders(in: parent)
        let folder = ArchiveFolder(name: name, orderIndex: siblings.count, parent: parent)
        modelContext.insert(folder)
        save()
        return folder
    }

    func deleteArchiveFolder(_ folder: ArchiveFolder) {
        deleteArchiveFolderContents(folder)
        modelContext.delete(folder)
        save()
    }

    func moveProjectToFolder(_ project: Project, folder: ArchiveFolder) {
        project.archiveFolder = folder
        project.isArchived = true
        save()
        notificationScheduleService?.removeEntries(projectId: project.projectId)
    }

    func moveFolder(_ folder: ArchiveFolder, to parent: ArchiveFolder?) {
        guard folder.parent?.folderId != parent?.folderId else { return }

        let siblings = folders(in: parent)
        folder.parent = parent
        folder.orderIndex = siblings.count
        save()
    }

    func fetchRootFolders() -> [ArchiveFolder] {
        let descriptor = FetchDescriptor<ArchiveFolder>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.parent == nil }
    }

    func allActiveProjects() -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return (try? modelContext.fetch(descriptor))?.filter { !$0.isArchived } ?? []
    }

    // MARK: - Reorder

    func reorderActiveProjects(fromOffsets: IndexSet, toOffset: Int) {
        var items = allActiveProjects()
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (i, item) in items.enumerated() {
            item.orderIndex = i
        }
        save()
    }

    func reorderActiveProject(movingID: UUID, targetID: UUID?, placement: ReorderPlacement) {
        var items = allActiveProjects()
        guard let movingIndex = items.firstIndex(where: { $0.projectId == movingID }) else { return }
        let moving = items.remove(at: movingIndex)

        let insertionIndex = insertionIndex(
            in: items,
            targetID: targetID,
            placement: placement,
            id: \.projectId
        )
        items.insert(moving, at: insertionIndex)
        for (index, item) in items.enumerated() {
            item.orderIndex = index
        }
        save()
    }

    func reorderMilestones(in project: Project, movingID: UUID, targetID: UUID?, placement: ReorderPlacement) {
        var items = project.milestones.sorted { $0.orderIndex < $1.orderIndex }
        guard let movingIndex = items.firstIndex(where: { $0.milestoneId == movingID }) else { return }
        let moving = items.remove(at: movingIndex)

        let insertionIndex = insertionIndex(
            in: items,
            targetID: targetID,
            placement: placement,
            id: \.milestoneId
        )
        items.insert(moving, at: insertionIndex)
        for (index, item) in items.enumerated() {
            item.orderIndex = index
        }
        save()
        syncProjectReminder(project)
    }

    func moveSubTask(_ subTaskID: UUID, to targetMilestoneID: UUID, targetSubTaskID: UUID?, placement: ReorderPlacement) {
        let milestones = allMilestones()
        guard let moving = milestones.flatMap(\.subtasks).first(where: { $0.taskId == subTaskID }),
              let targetMilestone = milestones.first(where: { $0.milestoneId == targetMilestoneID })
        else { return }

        let sourceMilestone = moving.milestone
        sourceMilestone?.subtasks.removeAll { $0.taskId == subTaskID }
        moving.milestone = targetMilestone
        if !targetMilestone.subtasks.contains(where: { $0.taskId == subTaskID }) {
            targetMilestone.subtasks.append(moving)
        }

        var targetItems = targetMilestone.subtasks
            .filter { $0.taskId != subTaskID }
            .sorted { $0.orderIndex < $1.orderIndex }
        let insertionIndex = insertionIndex(
            in: targetItems,
            targetID: targetSubTaskID,
            placement: placement,
            id: \.taskId
        )
        targetItems.insert(moving, at: insertionIndex)
        for (index, item) in targetItems.enumerated() {
            item.orderIndex = index
            item.milestone = targetMilestone
        }
        targetMilestone.subtasks = targetItems

        if sourceMilestone?.milestoneId != targetMilestone.milestoneId, let sourceMilestone {
            normalizeSubTaskOrder(in: sourceMilestone)
            sourceMilestone.syncCompletionFromSubtasks()
        }
        targetMilestone.syncCompletionFromSubtasks()
        save()
        if let project = targetMilestone.project {
            syncProjectReminder(project)
        }
        if let project = sourceMilestone?.project, project.projectId != targetMilestone.project?.projectId {
            syncProjectReminder(project)
        }
    }

    func reorderMemos(in project: Project, movingID: UUID, targetID: UUID?, placement: ReorderPlacement) {
        normalizeMemoOrder(in: project)
        var items = project.memos.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.orderIndex < $1.orderIndex
        }
        guard let movingIndex = items.firstIndex(where: { $0.memoId == movingID }) else { return }
        let moving = items.remove(at: movingIndex)

        let insertionIndex = insertionIndex(
            in: items,
            targetID: targetID,
            placement: placement,
            id: \.memoId
        )
        items.insert(moving, at: insertionIndex)
        for (index, item) in items.enumerated() {
            item.orderIndex = index
        }
        save()
    }

    func reorderFolderProjects(_ folder: ArchiveFolder, fromOffsets: IndexSet, toOffset: Int) {
        var items = folder.projects.sorted { $0.orderIndex < $1.orderIndex }
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (i, item) in items.enumerated() {
            item.orderIndex = i
        }
        save()
    }

    func reorderFolders(fromOffsets: IndexSet, toOffset: Int) {
        reorderFolders(in: nil, fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func reorderFolders(in parent: ArchiveFolder?, fromOffsets: IndexSet, toOffset: Int) {
        var items = folders(in: parent)
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (i, item) in items.enumerated() {
            item.orderIndex = i
        }
        save()
    }

    // MARK: - Template CRUD

    @discardableResult
    func saveTemplate(
        _ template: ProjectTemplate?,
        name: String,
        hideCompleted: Bool,
        accentColor: String,
        sfSymbolName: String,
        milestones: [(title: String, subtasks: [String])]
    ) -> ProjectTemplate {
        let savedTemplate: ProjectTemplate
        if let template {
            savedTemplate = template
            template.milestones.forEach { modelContext.delete($0) }
            template.milestones.removeAll()
        } else {
            let descriptor = FetchDescriptor<ProjectTemplate>(
                sortBy: [SortDescriptor(\.orderIndex)]
            )
            let templates = (try? modelContext.fetch(descriptor)) ?? []
            let nextIndex = (templates.map(\.orderIndex).max() ?? -1) + 1
            savedTemplate = ProjectTemplate(name: name, orderIndex: nextIndex)
            modelContext.insert(savedTemplate)
        }

        savedTemplate.name = name
        savedTemplate.hideCompleted = hideCompleted
        savedTemplate.accentColor = accentColor
        savedTemplate.sfSymbolName = sfSymbolName

        for (milestoneIndex, milestoneInput) in milestones.enumerated() {
            let milestone = TemplateMilestone(title: milestoneInput.title, orderIndex: milestoneIndex)
            milestone.template = savedTemplate
            modelContext.insert(milestone)
            savedTemplate.milestones.append(milestone)

            for (subtaskIndex, subtaskTitle) in milestoneInput.subtasks.enumerated() {
                let subtask = TemplateSubTask(title: subtaskTitle, orderIndex: subtaskIndex)
                subtask.milestone = milestone
                modelContext.insert(subtask)
                milestone.subtasks.append(subtask)
            }
        }

        save()
        return savedTemplate
    }

    func deleteTemplate(_ template: ProjectTemplate) {
        modelContext.delete(template)
        save()
    }

    // MARK: - Persist

    func save() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
            SharedModelContainer.widgetKinds.forEach {
                WidgetCenter.shared.reloadTimelines(ofKind: $0)
            }
        } catch {
            // TODO: Phase 2 — 统一错误处理与用户提示
            print("[ProjectService] save failed: \(error.localizedDescription)")
        }
    }

    private func syncReminderTimeline(for project: Project) {
        guard !project.isArchived else {
            notificationScheduleService?.removeEntries(projectId: project.projectId)
            return
        }

        syncProjectReminder(project)
        project.milestones.forEach { milestone in
            notificationScheduleService?.syncMilestone(milestone, project: project)
            milestone.subtasks.forEach { subtask in
                notificationScheduleService?.syncSubTask(subtask, project: project)
            }
        }
    }

    private func syncProjectReminder(_ project: Project) {
        notificationScheduleService?.syncProject(project)
    }

    private func folders(in parent: ArchiveFolder?) -> [ArchiveFolder] {
        let descriptor = FetchDescriptor<ArchiveFolder>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        let folders = (try? modelContext.fetch(descriptor)) ?? []
        return folders.filter { $0.parent?.folderId == parent?.folderId }
    }

    private func allMilestones() -> [Milestone] {
        let descriptor = FetchDescriptor<Milestone>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func copyTaskTree(from template: ProjectTemplate, to project: Project) {
        for templateMilestone in template.milestones.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let milestone = Milestone(title: templateMilestone.title, orderIndex: templateMilestone.orderIndex)
            milestone.project = project
            modelContext.insert(milestone)
            project.milestones.append(milestone)

            for templateSubtask in templateMilestone.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let subtask = SubTask(title: templateSubtask.title, orderIndex: templateSubtask.orderIndex)
                subtask.milestone = milestone
                modelContext.insert(subtask)
                milestone.subtasks.append(subtask)
            }
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

    private func insertionIndex<Item>(
        in items: [Item],
        targetID: UUID?,
        placement: ReorderPlacement,
        id: KeyPath<Item, UUID>
    ) -> Int {
        guard placement != .end,
              let targetID,
              let targetIndex = items.firstIndex(where: { $0[keyPath: id] == targetID })
        else {
            return items.count
        }

        switch placement {
        case .before:
            return targetIndex
        case .after:
            return targetIndex + 1
        case .end:
            return items.count
        }
    }

    private func deleteArchiveFolderContents(_ folder: ArchiveFolder) {
        let childFolders = folders(in: folder)
        for child in childFolders {
            deleteArchiveFolderContents(child)
            modelContext.delete(child)
        }

        for project in folder.projects {
            notificationScheduleService?.removeEntries(projectId: project.projectId)
            modelContext.delete(project)
        }
    }
}

// MARK: - iCloud Sync (reserved, Phase 2+)

extension ProjectService {

    /// 配置 iCloud 同步 —— 通过 ModelConfiguration.cloudKitDatabase 启用
    ///
    /// SwiftData 内置 CloudKit 集成，只需在 ModelContainer 初始化时传入：
    /// ```
    /// ModelConfiguration(
    ///     schema: schema,
    ///     isStoredInMemoryOnly: false,
    ///     cloudKitDatabase: .private("iCloud.com.viabar")
    /// )
    /// ```
    ///
    /// 此方法预留自定义配置注入，供后续 CloudSyncService 调用。
    func configureSync(_ config: CloudSyncConfig) {
        syncConfig = config
    }

    /// 标记同步开始 —— 由 CloudSyncService 在 import/export 前后调用
    func onSyncWillStart() {
        syncStatus = .importing
    }

    /// 标记同步结束
    func onSyncDidFinish(affectedCount: Int = 0) {
        syncStatus = .idle
        lastSyncDate = Date()
        syncHistory.append(
            SyncEvent(
                status: .idle,
                affectedEntityCount: affectedCount
            )
        )
    }

    /// 标记同步错误
    func onSyncError(_ error: Error) {
        syncStatus = .error
        syncHistory.append(
            SyncEvent(status: .error, error: error)
        )
    }

    /// 处理来自 CloudKit 的远程变更通知（Silent Push）
    /// CloudSyncService 收到 push 后调用此方法，触发 UI 刷新或数据合并。
    func handleRemoteChange(_ notification: Notification?) {
        // TODO: Phase 2 — 解析 NSPersistentCloudKitContainer 变更通知，
        // 执行增量合并，通知 UI 层刷新。
        lastSyncDate = Date()
    }

    /// 重置本地同步状态（用于登出 iCloud 或调试清空场景）
    func resetSyncState() {
        syncStatus = .idle
        lastSyncDate = nil
        syncConfig = nil
        syncHistory.removeAll()
    }
}

// MARK: - ServiceContainer Convenience

extension ServiceContainer {

    /// 快捷获取已注册的 ProjectService
    var projectService: ProjectService? {
        resolve(ProjectService.self)
    }

    /// 注册 ProjectService 到容器
    func registerProjectService(modelContext: ModelContext) -> ProjectService {
        let service = ProjectService(modelContext: modelContext, container: self)
        register(service)
        return service
    }
}
