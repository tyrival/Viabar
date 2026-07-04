import Foundation

enum ExternalAddKind: Equatable {
    case memo
    case todo
}

struct ExternalAddRequest: Equatable {
    let kind: ExternalAddKind
    let projectReference: ExternalAddReference
    let milestoneReference: ExternalAddReference?
    let text: String
}

enum ExternalAddReference: Equatable {
    case id(UUID)
    case name(String)
}

enum ExternalAddURL {
    static func request(from url: URL) -> ExternalAddRequest? {
        guard url.scheme == "viabar", url.host == "add" else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1 else { return nil }

        switch components[0].lowercased() {
        case "memo":
            return memoRequest(from: url)
        case "todo":
            return todoRequest(from: url)
        default:
            return nil
        }
    }

    private static func memoRequest(from url: URL) -> ExternalAddRequest? {
        guard let project = reference(named: "project", in: url),
              let content = firstNonEmptyValue(named: ["content", "text", "body"], in: url)
        else { return nil }

        return ExternalAddRequest(
            kind: .memo,
            projectReference: project,
            milestoneReference: nil,
            text: content
        )
    }

    private static func todoRequest(from url: URL) -> ExternalAddRequest? {
        guard let project = reference(named: "project", in: url),
              let milestone = reference(named: "milestone", in: url),
              let title = firstNonEmptyValue(named: ["title", "text", "content"], in: url)
        else { return nil }

        return ExternalAddRequest(
            kind: .todo,
            projectReference: project,
            milestoneReference: milestone,
            text: title
        )
    }

    private static func reference(named name: String, in url: URL) -> ExternalAddReference? {
        guard let value = firstNonEmptyValue(named: [name], in: url) else { return nil }
        if let id = UUID(uuidString: value) {
            return .id(id)
        }
        return .name(value)
    }

    private static func firstNonEmptyValue(named names: [String], in url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }

        for name in names {
            guard let value = items.first(where: { $0.name == name })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else { continue }
            return value
        }

        return nil
    }
}

@MainActor
enum ExternalAddHandler {
    static func perform(
        _ request: ExternalAddRequest,
        projects: [Project],
        projectService: ProjectService
    ) -> GlobalSearchNavigationRequest? {
        guard let project = resolveProject(request.projectReference, in: projects) else {
            return nil
        }

        switch request.kind {
        case .memo:
            let memo = projectService.addMemo(to: project, content: request.text)
            return GlobalSearchNavigationRequest(
                projectID: project.projectId,
                destination: .memo(memo.memoId)
            )

        case .todo:
            guard let milestoneReference = request.milestoneReference,
                  let milestone = resolveMilestone(milestoneReference, in: project)
            else { return nil }

            let subtask = projectService.addSubTask(to: milestone, title: request.text)
            return GlobalSearchNavigationRequest(
                projectID: project.projectId,
                destination: .subTask(
                    milestoneID: milestone.milestoneId,
                    subTaskID: subtask.taskId
                )
            )
        }
    }

    private static func resolveProject(
        _ reference: ExternalAddReference,
        in projects: [Project]
    ) -> Project? {
        switch reference {
        case .id(let id):
            return projects.first { $0.projectId == id }
        case .name(let name):
            return projects
                .sorted { lhs, rhs in
                    if lhs.isArchived != rhs.isArchived {
                        return !lhs.isArchived
                    }
                    return lhs.orderIndex < rhs.orderIndex
                }
                .first { $0.title.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    private static func resolveMilestone(
        _ reference: ExternalAddReference,
        in project: Project
    ) -> Milestone? {
        switch reference {
        case .id(let id):
            return project.milestones.first { $0.milestoneId == id }
        case .name(let name):
            return project.milestones
                .sorted { $0.orderIndex < $1.orderIndex }
                .first { $0.title.caseInsensitiveCompare(name) == .orderedSame }
        }
    }
}
