import Foundation
import SwiftData
import SwiftUI

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
    func createProject(title: String, hideCompleted: Bool, orderIndex: Int) -> Project
    func allProjects() -> [Project]
    func updateProject(_ project: Project)
    func deleteProject(_ project: Project)

    // Milestone
    func addMilestone(to project: Project, title: String, orderIndex: Int?) -> Milestone
    func deleteMilestone(_ milestone: Milestone)

    // SubTask
    func addSubTask(to milestone: Milestone, title: String, orderIndex: Int?) -> SubTask
    func deleteSubTask(_ subTask: SubTask)

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
    func reorderMilestones(in project: Project, movingID: UUID, targetID: UUID?, placement: ReorderPlacement)
    func moveSubTask(_ subTaskID: UUID, to targetMilestoneID: UUID, targetSubTaskID: UUID?, placement: ReorderPlacement)
    func reorderFolderProjects(_ folder: ArchiveFolder, fromOffsets: IndexSet, toOffset: Int)
    func reorderFolders(fromOffsets: IndexSet, toOffset: Int)

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
    func createProject(title: String, hideCompleted: Bool = true, orderIndex: Int = 0) -> Project {
        let project = Project(title: title, hideCompleted: hideCompleted, orderIndex: orderIndex)
        modelContext.insert(project)
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
    }

    func deleteProject(_ project: Project) {
        modelContext.delete(project)
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
        return milestone
    }

    func deleteMilestone(_ milestone: Milestone) {
        modelContext.delete(milestone)
        save()
    }

    func toggleMilestoneComplete(_ milestone: Milestone) {
        if milestone.subtasks.isEmpty {
            milestone.isCompleted.toggle()
            milestone.completedAt = milestone.isCompleted ? Date() : nil
        } else {
            // 有子任务时，联动切换全部子任务状态
            let target = !milestone.isCompleted
            let completedAt = target ? Date() : nil
            for st in milestone.subtasks {
                st.isCompleted = target
                st.completedAt = completedAt
            }
            milestone.isCompleted = target
            milestone.completedAt = completedAt
        }
        save()
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
        return subtask
    }

    func deleteSubTask(_ subTask: SubTask) {
        let milestone = subTask.milestone
        modelContext.delete(subTask)
        milestone?.syncCompletionFromSubtasks()
        save()
    }

    func toggleSubTaskComplete(_ subTask: SubTask) {
        subTask.isCompleted.toggle()
        subTask.completedAt = subTask.isCompleted ? Date() : nil
        subTask.milestone?.syncCompletionFromSubtasks()
        save()
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
        modelContext.delete(memo)
        save()
    }

    // MARK: - Archive & Folders

    func archiveProject(_ project: Project, to folder: ArchiveFolder) {
        project.isArchived = true
        project.archivedAt = Date()
        project.archiveFolder = folder
        save()
    }

    func unarchiveProject(_ project: Project) {
        project.isArchived = false
        project.archivedAt = nil
        project.archiveFolder = nil
        // 移回活跃列表末尾
        project.orderIndex = allActiveProjects().count
        save()
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

    // MARK: - Persist

    func save() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            // TODO: Phase 2 — 统一错误处理与用户提示
            print("[ProjectService] save failed: \(error.localizedDescription)")
        }
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
