import Foundation
import Observation

@MainActor
@Observable
final class IOSPersistenceCoordinator {
    var homeTab: IOSPrototypeHomeTab = .overview
    var detailTab: IOSPrototypeDetailTab = .tasks
    var searchText = ""
    var isSearchPresented = false
    var navigationRequest: GlobalSearchNavigationRequest?
    var expandedArchiveFolderIDs: Set<UUID> = []
    var navigationPath: [UUID] = []

    private var consumedHighlightRequestIDs: Set<UUID> = []

    func selectProject(_ project: Project) {
        navigationRequest = nil
        navigationPath = [project.projectId]
    }

    func navigate(to result: GlobalSearchResult) {
        navigate(to: GlobalSearchNavigationRequest(
            projectID: result.project.projectId,
            destination: result.destination
        ))
    }

    func navigate(to request: GlobalSearchNavigationRequest) {
        navigationRequest = request
        detailTab = request.destination.detailTab
        navigationPath = [request.projectID]
        isSearchPresented = false
        searchText = ""
    }

    func revealArchiveAncestors(for project: Project) {
        var folder = project.archiveFolder
        while let current = folder {
            expandedArchiveFolderIDs.insert(current.folderId)
            folder = current.parent
        }
    }

    func consumeHighlight(_ requestID: UUID?) -> Bool {
        guard let requestID else { return false }
        return consumedHighlightRequestIDs.insert(requestID).inserted
    }
}

private extension GlobalSearchDestination {
    var detailTab: IOSPrototypeDetailTab {
        switch self {
        case .memo:
            return .memos
        case .project, .milestone, .subTask:
            return .tasks
        }
    }
}
