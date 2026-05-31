import AppIntents
import SwiftData

struct WidgetProjectEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "项目")
    static var defaultQuery = WidgetProjectEntityQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct WidgetProjectEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [WidgetProjectEntity] {
        try fetchActiveProjects().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WidgetProjectEntity] {
        try fetchActiveProjects()
    }

    @MainActor
    private func fetchActiveProjects() throws -> [WidgetProjectEntity] {
        let container = try SharedModelContainer.makeWidgetContainer()
        let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
        return WidgetContentBuilder.activeProjects(from: projects).map {
            WidgetProjectEntity(id: $0.projectId, title: $0.title)
        }
    }
}

struct SelectWidgetProjectIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "选择项目"
    static var description = IntentDescription("选择桌面小组件要显示的项目")

    @Parameter(title: "项目")
    var project: WidgetProjectEntity?
}
