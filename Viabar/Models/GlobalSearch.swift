import Foundation

enum GlobalSearchDestination: Equatable {
    case project
    case milestone(UUID)
    case subTask(milestoneID: UUID, subTaskID: UUID)
    case memo(UUID)
}

struct GlobalSearchNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: UUID
    let destination: GlobalSearchDestination
}

struct GlobalSearchResult: Identifiable {
    let id: String
    let project: Project
    let text: String
    let path: String
    let destination: GlobalSearchDestination
}

enum GlobalSearchIndex {
    static func results(matching query: String, projects: [Project]) -> [GlobalSearchResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }

        return orderedProjects(from: projects).flatMap { project in
            matchingResults(in: project, term: term)
        }
    }

    private static func matchingResults(in project: Project, term: String) -> [GlobalSearchResult] {
        var results: [GlobalSearchResult] = []
        let prefix = project.isArchived ? "归档 / " : ""
        let projectPath = "\(prefix)\(project.title)"

        if project.title.localizedCaseInsensitiveContains(term) {
            results.append(
                GlobalSearchResult(
                    id: "project-\(project.projectId.uuidString)",
                    project: project,
                    text: project.title,
                    path: projectPath,
                    destination: .project
                )
            )
        }

        for milestone in project.milestones.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            if milestone.title.localizedCaseInsensitiveContains(term) {
                results.append(
                    GlobalSearchResult(
                        id: "milestone-\(milestone.milestoneId.uuidString)",
                        project: project,
                        text: milestone.title,
                        path: "\(projectPath) / \(milestone.title)",
                        destination: .milestone(milestone.milestoneId)
                    )
                )
            }

            let parentTitle = compactMilestoneTitle(milestone.title)
            for subTask in milestone.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                guard subTask.title.localizedCaseInsensitiveContains(term) else { continue }
                results.append(
                    GlobalSearchResult(
                        id: "subtask-\(subTask.taskId.uuidString)",
                        project: project,
                        text: subTask.title,
                        path: "\(projectPath) / \(parentTitle) / \(subTask.title)",
                        destination: .subTask(
                            milestoneID: milestone.milestoneId,
                            subTaskID: subTask.taskId
                        )
                    )
                )
            }
        }

        for memo in sortedMemos(in: project) where memo.content.localizedCaseInsensitiveContains(term) {
            results.append(
                GlobalSearchResult(
                    id: "memo-\(memo.memoId.uuidString)",
                    project: project,
                    text: memo.content,
                    path: "\(projectPath) / 备忘录",
                    destination: .memo(memo.memoId)
                )
            )
        }

        return results
    }

    private static func orderedProjects(from projects: [Project]) -> [Project] {
        let activeProjects = projects
            .filter { !$0.isArchived }
            .sorted(by: sortProjects)
        let archivedProjects = projects.filter(\.isArchived)
        let archivedProjectIDs = Set(archivedProjects.map(\.projectId))
        var orderedArchived: [Project] = []
        var includedProjectIDs: Set<UUID> = []

        let roots = uniqueArchiveRoots(from: archivedProjects)
            .sorted(by: sortFolders)
        for root in roots {
            appendArchivedProjects(
                in: root,
                allowedProjectIDs: archivedProjectIDs,
                includedProjectIDs: &includedProjectIDs,
                results: &orderedArchived
            )
        }

        let unlistedProjects = archivedProjects
            .filter { !includedProjectIDs.contains($0.projectId) }
            .sorted(by: sortProjects)

        return activeProjects + orderedArchived + unlistedProjects
    }

    private static func sortedMemos(in project: Project) -> [Memo] {
        project.memos.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.orderIndex < $1.orderIndex
        }
    }

    private static func compactMilestoneTitle(_ title: String) -> String {
        guard title.count > 10 else { return title }
        return String(title.prefix(9)) + "…"
    }

    private static func uniqueArchiveRoots(from projects: [Project]) -> [ArchiveFolder] {
        var roots: [ArchiveFolder] = []
        var rootIDs: Set<UUID> = []

        for project in projects {
            guard let root = archiveRoot(of: project.archiveFolder),
                  rootIDs.insert(root.folderId).inserted
            else { continue }
            roots.append(root)
        }

        return roots
    }

    private static func archiveRoot(of folder: ArchiveFolder?) -> ArchiveFolder? {
        var current = folder
        while let parent = current?.parent {
            current = parent
        }
        return current
    }

    private static func appendArchivedProjects(
        in folder: ArchiveFolder,
        allowedProjectIDs: Set<UUID>,
        includedProjectIDs: inout Set<UUID>,
        results: inout [Project]
    ) {
        for project in folder.projects.sorted(by: sortProjects) {
            guard allowedProjectIDs.contains(project.projectId),
                  includedProjectIDs.insert(project.projectId).inserted
            else { continue }
            results.append(project)
        }

        for child in folder.children.sorted(by: sortFolders) {
            appendArchivedProjects(
                in: child,
                allowedProjectIDs: allowedProjectIDs,
                includedProjectIDs: &includedProjectIDs,
                results: &results
            )
        }
    }

    private static func sortProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        if lhs.orderIndex == rhs.orderIndex {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.orderIndex < rhs.orderIndex
    }

    private static func sortFolders(_ lhs: ArchiveFolder, _ rhs: ArchiveFolder) -> Bool {
        if lhs.orderIndex == rhs.orderIndex {
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return lhs.orderIndex < rhs.orderIndex
    }
}
