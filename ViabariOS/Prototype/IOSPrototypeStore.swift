import Foundation
import Observation

@MainActor
@Observable
final class IOSPrototypeStore {
    var projects: [IOSPrototypeProject] = IOSPrototypeStore.demoProjects()
    var homeTab: IOSPrototypeHomeTab = .overview
    var selectedProjectID: UUID?
    var detailTab: IOSPrototypeDetailTab = .tasks
    var isSearchPresented = false
    var searchText = ""
    var archiveFolders: [IOSPrototypeArchiveFolder] = IOSPrototypeStore.demoArchiveFolders()
    var expandedArchiveFolderIDs: Set<UUID> = []
    var navigationRequest: IOSPrototypeNavigationRequest?
    private var consumedNavigationHighlightRequestIDs: Set<UUID> = []

    var favoriteProjects: [IOSPrototypeProject] {
        projects.filter { $0.isFavorite && !$0.isArchived }
    }

    var regularProjects: [IOSPrototypeProject] {
        projects.filter { !$0.isFavorite && !$0.isArchived }
    }

    var rootArchiveFolders: [IOSPrototypeArchiveFolder] {
        archiveFolders
            .filter { $0.parentID == nil }
            .sorted(by: sortFolders)
    }

    var selectedProject: IOSPrototypeProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    var searchResults: [IOSPrototypeSearchResult] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }

        var results: [IOSPrototypeSearchResult] = []
        for project in projects {
            let prefix = project.isArchived ? "归档 / " : ""
            let projectPath = "\(prefix)\(project.title)"
            if project.title.localizedCaseInsensitiveContains(term) {
                results.append(result(
                    project: project,
                    tab: .tasks,
                    target: .project,
                    title: project.title,
                    path: projectPath
                ))
            }
            for milestone in project.milestones.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                if milestone.title.localizedCaseInsensitiveContains(term) {
                    results.append(result(
                        project: project,
                        tab: .tasks,
                        target: .milestone(milestoneID: milestone.id),
                        title: milestone.title,
                        path: "\(projectPath) / \(milestone.title)"
                    ))
                }
                for subtask in milestone.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex })
                where subtask.title.localizedCaseInsensitiveContains(term) {
                    results.append(result(
                        project: project,
                        tab: .tasks,
                        target: .subtask(milestoneID: milestone.id, subtaskID: subtask.id),
                        title: subtask.title,
                        path: "\(projectPath) / \(milestone.title) / \(subtask.title)"
                    ))
                }
            }
            for memo in project.memos where memo.content.localizedCaseInsensitiveContains(term) {
                results.append(result(
                    project: project,
                    tab: .memos,
                    target: .memo(memoID: memo.id),
                    title: memo.content,
                    path: "\(projectPath) / 备忘录"
                ))
            }
        }
        return results
    }

    func selectProject(_ id: UUID, detailTab: IOSPrototypeDetailTab = .tasks) {
        selectedProjectID = id
        self.detailTab = detailTab
        isSearchPresented = false
        searchText = ""
    }

    func navigate(to result: IOSPrototypeSearchResult) {
        selectedProjectID = result.projectID
        detailTab = result.detailTab
        navigationRequest = IOSPrototypeNavigationRequest(projectID: result.projectID, target: result.target)
        if projects.first(where: { $0.id == result.projectID })?.isArchived == true {
            revealArchiveAncestors(for: result.projectID)
        }
        isSearchPresented = false
        searchText = ""
    }

    func consumeNavigationHighlight(_ requestID: UUID?) -> Bool {
        guard let requestID else { return false }
        return consumedNavigationHighlightRequestIDs.insert(requestID).inserted
    }

    func toggleFavorite(_ projectID: UUID) {
        updateProject(projectID) { $0.isFavorite.toggle() }
    }

    func archive(_ projectID: UUID) {
        let rootFolderID = ensureDefaultArchiveFolder()
        updateProject(projectID) {
            $0.isArchived = true
            $0.archiveFolderID = rootFolderID
        }
    }

    func unarchive(_ projectID: UUID) {
        updateProject(projectID) {
            $0.isArchived = false
            $0.archiveFolderID = nil
        }
    }

    func deleteProject(_ projectID: UUID) {
        projects.removeAll { $0.id == projectID }
    }

    func renameProject(_ projectID: UUID, title: String) {
        guard let title = normalized(title) else { return }
        updateProject(projectID) { $0.title = title }
    }

    func toggleMilestone(_ milestoneID: UUID, in projectID: UUID) {
        updateMilestone(milestoneID, in: projectID) { milestone in
            milestone.isCompleted.toggle()
            guard !milestone.subtasks.isEmpty else { return }
            for index in milestone.subtasks.indices {
                milestone.subtasks[index].isCompleted = milestone.isCompleted
            }
        }
    }

    func toggleSubtask(_ subtaskID: UUID, milestoneID: UUID, in projectID: UUID) {
        updateMilestone(milestoneID, in: projectID) { milestone in
            guard let index = milestone.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            milestone.subtasks[index].isCompleted.toggle()
            milestone.isCompleted = milestone.subtasks.allSatisfy(\.isCompleted)
        }
    }

    func renameMilestone(_ milestoneID: UUID, in projectID: UUID, title: String) {
        guard let title = normalized(title) else { return }
        updateMilestone(milestoneID, in: projectID) { $0.title = title }
    }

    func renameSubtask(_ subtaskID: UUID, milestoneID: UUID, in projectID: UUID, title: String) {
        guard let title = normalized(title) else { return }
        updateMilestone(milestoneID, in: projectID) { milestone in
            guard let index = milestone.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            milestone.subtasks[index].title = title
        }
    }

    func renameMemo(_ memoID: UUID, in projectID: UUID, content: String) {
        guard let content = normalized(content) else { return }
        updateProject(projectID) { project in
            guard let index = project.memos.firstIndex(where: { $0.id == memoID }) else { return }
            project.memos[index].content = content
        }
    }

    func addMilestone(to projectID: UUID, title: String) {
        guard let title = normalized(title) else { return }
        updateProject(projectID) { project in
            project.milestones.append(IOSPrototypeMilestone(
                id: UUID(),
                title: title,
                orderIndex: project.milestones.count,
                isCompleted: false,
                reminderDate: nil,
                subtasks: []
            ))
        }
    }

    func addMemo(to projectID: UUID, content: String) {
        guard let content = normalized(content) else { return }
        updateProject(projectID) { project in
            project.memos.insert(IOSPrototypeMemo(id: UUID(), content: content, createdAt: Date()), at: 0)
        }
    }

    func addSubtask(to milestoneID: UUID, in projectID: UUID, title: String) {
        guard let title = normalized(title) else { return }
        updateMilestone(milestoneID, in: projectID) { milestone in
            milestone.subtasks.append(IOSPrototypeSubTask(
                id: UUID(),
                title: title,
                orderIndex: milestone.subtasks.count,
                isCompleted: false,
                reminderDate: nil
            ))
            milestone.isCompleted = false
        }
    }

    func deleteMilestone(_ milestoneID: UUID, in projectID: UUID) {
        updateProject(projectID) { $0.milestones.removeAll { $0.id == milestoneID } }
    }

    func deleteSubtask(_ subtaskID: UUID, milestoneID: UUID, in projectID: UUID) {
        updateMilestone(milestoneID, in: projectID) { milestone in
            milestone.subtasks.removeAll { $0.id == subtaskID }
            if !milestone.subtasks.isEmpty {
                milestone.isCompleted = milestone.subtasks.allSatisfy(\.isCompleted)
            }
        }
    }

    func deleteMemo(_ memoID: UUID, in projectID: UUID) {
        updateProject(projectID) { $0.memos.removeAll { $0.id == memoID } }
    }

    func archiveChildren(of parentID: UUID?) -> [IOSPrototypeArchiveFolder] {
        archiveFolders
            .filter { $0.parentID == parentID }
            .sorted(by: sortFolders)
    }

    func archivedProjects(in folderID: UUID) -> [IOSPrototypeProject] {
        projects
            .filter { $0.isArchived && $0.archiveFolderID == folderID }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func createArchiveFolder(name: String, parentID: UUID? = nil) {
        guard let name = normalized(name) else { return }
        let siblings = archiveChildren(of: parentID)
        archiveFolders.append(IOSPrototypeArchiveFolder(
            id: UUID(),
            name: name,
            parentID: parentID,
            orderIndex: siblings.count
        ))
    }

    func renameArchiveFolder(_ folderID: UUID, name: String) {
        guard let name = normalized(name),
              let index = archiveFolders.firstIndex(where: { $0.id == folderID })
        else { return }
        archiveFolders[index].name = name
    }

    func archiveFolderHasContents(_ folderID: UUID) -> Bool {
        !archiveChildren(of: folderID).isEmpty || !archivedProjects(in: folderID).isEmpty
    }

    func deleteArchiveFolder(_ folderID: UUID) {
        let descendantIDs = archiveDescendantIDs(of: folderID)
        projects.removeAll { project in
            guard let archiveFolderID = project.archiveFolderID else { return false }
            return descendantIDs.contains(archiveFolderID)
        }
        archiveFolders.removeAll { descendantIDs.contains($0.id) }
        expandedArchiveFolderIDs.subtract(descendantIDs)
    }

    func revealArchiveAncestors(for projectID: UUID) {
        guard let folderID = projects.first(where: { $0.id == projectID })?.archiveFolderID else { return }
        var currentID: UUID? = folderID
        while let id = currentID {
            expandedArchiveFolderIDs.insert(id)
            currentID = archiveFolders.first(where: { $0.id == id })?.parentID
        }
    }

    private func result(
        project: IOSPrototypeProject,
        tab: IOSPrototypeDetailTab,
        target: IOSPrototypeSearchTarget,
        title: String,
        path: String
    ) -> IOSPrototypeSearchResult {
        IOSPrototypeSearchResult(
            id: searchResultID(projectID: project.id, target: target),
            projectID: project.id,
            detailTab: tab,
            target: target,
            title: title,
            path: path
        )
    }

    private func searchResultID(projectID: UUID, target: IOSPrototypeSearchTarget) -> String {
        switch target {
        case .project:
            return "project-\(projectID.uuidString)"
        case let .milestone(milestoneID):
            return "milestone-\(milestoneID.uuidString)"
        case let .subtask(_, subtaskID):
            return "subtask-\(subtaskID.uuidString)"
        case let .memo(memoID):
            return "memo-\(memoID.uuidString)"
        }
    }

    private func updateProject(_ projectID: UUID, mutate: (inout IOSPrototypeProject) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        mutate(&projects[index])
    }

    private func updateMilestone(
        _ milestoneID: UUID,
        in projectID: UUID,
        mutate: (inout IOSPrototypeMilestone) -> Void
    ) {
        updateProject(projectID) { project in
            guard let index = project.milestones.firstIndex(where: { $0.id == milestoneID }) else { return }
            mutate(&project.milestones[index])
        }
    }

    private func normalized(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func ensureDefaultArchiveFolder() -> UUID {
        if let id = rootArchiveFolders.first?.id {
            return id
        }
        let id = UUID()
        archiveFolders.append(IOSPrototypeArchiveFolder(id: id, name: "默认归档", parentID: nil, orderIndex: 0))
        return id
    }

    private func archiveDescendantIDs(of folderID: UUID) -> Set<UUID> {
        archiveChildren(of: folderID).reduce(into: Set([folderID])) { result, child in
            result.formUnion(archiveDescendantIDs(of: child.id))
        }
    }

    private func sortFolders(_ lhs: IOSPrototypeArchiveFolder, _ rhs: IOSPrototypeArchiveFolder) -> Bool {
        if lhs.orderIndex == rhs.orderIndex {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return lhs.orderIndex < rhs.orderIndex
    }

    private static func demoArchiveFolders() -> [IOSPrototypeArchiveFolder] {
        [
            IOSPrototypeArchiveFolder(id: DemoArchiveFolderID.clients, name: "客户项目", parentID: nil, orderIndex: 0),
            IOSPrototypeArchiveFolder(id: DemoArchiveFolderID.overseas, name: "海外项目", parentID: DemoArchiveFolderID.clients, orderIndex: 0),
            IOSPrototypeArchiveFolder(id: DemoArchiveFolderID.internalTools, name: "内部工具", parentID: nil, orderIndex: 1)
        ]
    }

    private static func demoProjects() -> [IOSPrototypeProject] {
        let now = Date()
        let reminder = Calendar.current.date(byAdding: .day, value: 26, to: now)
        let later = Calendar.current.date(byAdding: .day, value: 31, to: now)

        return [
            IOSPrototypeProject(
                id: UUID(),
                title: "EIOT-冻结数据",
                accentHex: "#4C9BFF",
                symbol: "bookmark.fill",
                isFavorite: true,
                isArchived: false,
                archiveFolderID: nil,
                reminderDate: reminder,
                milestones: [
                    IOSPrototypeMilestone(
                        id: UUID(),
                        title: "提供设备样机",
                        orderIndex: 0,
                        isCompleted: false,
                        reminderDate: reminder,
                        subtasks: [
                            IOSPrototypeSubTask(
                                id: UUID(),
                                title: "ADW300",
                                orderIndex: 0,
                                isCompleted: false,
                                reminderDate: nil
                            ),
                            IOSPrototypeSubTask(
                                id: UUID(),
                                title: "AWT 仪表",
                                orderIndex: 1,
                                isCompleted: true,
                                reminderDate: later
                            )
                        ]
                    ),
                    IOSPrototypeMilestone(
                        id: UUID(),
                        title: "方案编写",
                        orderIndex: 1,
                        isCompleted: true,
                        reminderDate: nil,
                        subtasks: []
                    ),
                    IOSPrototypeMilestone(
                        id: UUID(),
                        title: "交付复核",
                        orderIndex: 2,
                        isCompleted: false,
                        reminderDate: later,
                        subtasks: []
                    )
                ],
                memos: [
                    IOSPrototypeMemo(id: UUID(), content: "AWT无法远程升级仪表，优先级低", createdAt: now),
                    IOSPrototypeMemo(id: UUID(), content: "样机寄送后补充序列号\n并同步给测试负责人", createdAt: now.addingTimeInterval(-86400)),
                    IOSPrototypeMemo(id: UUID(), content: "冻结版本需要在周会前确认", createdAt: now.addingTimeInterval(-172800))
                ]
            ),
            IOSPrototypeProject(
                id: UUID(),
                title: "移动端交互验证",
                accentHex: "#FF6B6B",
                symbol: "iphone",
                isFavorite: true,
                isArchived: false,
                archiveFolderID: nil,
                reminderDate: later,
                milestones: [
                    IOSPrototypeMilestone(
                        id: UUID(),
                        title: "总览原型",
                        orderIndex: 0,
                        isCompleted: true,
                        reminderDate: nil,
                        subtasks: []
                    ),
                    IOSPrototypeMilestone(
                        id: UUID(),
                        title: "详情页交互",
                        orderIndex: 1,
                        isCompleted: false,
                        reminderDate: later,
                        subtasks: []
                    )
                ],
                memos: [
                    IOSPrototypeMemo(id: UUID(), content: "保持页面密度接近 macOS", createdAt: now)
                ]
            ),
            IOSPrototypeProject(
                id: UUID(),
                title: "版本发布",
                accentHex: "#31C48D",
                symbol: "shippingbox.fill",
                isFavorite: false,
                isArchived: false,
                archiveFolderID: nil,
                reminderDate: nil,
                milestones: [
                    IOSPrototypeMilestone(
                        id: UUID(),
                        title: "发布说明",
                        orderIndex: 0,
                        isCompleted: true,
                        reminderDate: nil,
                        subtasks: []
                    )
                ],
                memos: []
            ),
            IOSPrototypeProject(
                id: UUID(),
                title: "历史归档",
                accentHex: "#A78BFA",
                symbol: "archivebox.fill",
                isFavorite: false,
                isArchived: true,
                archiveFolderID: DemoArchiveFolderID.overseas,
                reminderDate: nil,
                milestones: [],
                memos: []
            )
        ]
    }
}

private enum DemoArchiveFolderID {
    static let clients = UUID(uuidString: "6BF6A2E4-7CF5-41A9-A9F0-4415A0D9CB65")!
    static let overseas = UUID(uuidString: "8D019B4B-4E27-4CC4-B3B0-FE45A8579E63")!
    static let internalTools = UUID(uuidString: "EEF09A02-DB33-45F7-84FB-3844AEB7A67C")!
}
