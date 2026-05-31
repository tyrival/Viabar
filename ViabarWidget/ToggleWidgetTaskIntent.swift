import AppIntents
import SwiftData
import WidgetKit

struct ToggleWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "完成任务"
    static var supportedModes: IntentModes = .background

    @Parameter(title: "任务类型")
    var kind: String

    @Parameter(title: "任务 ID")
    var taskID: String

    init() {}

    init(kind: WidgetTaskKind, taskID: UUID) {
        self.kind = kind.rawValue
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let kind = WidgetTaskKind(rawValue: kind),
              let id = UUID(uuidString: taskID)
        else { return .result() }

        let container = try SharedModelContainer.makeWidgetContainer()
        let context = container.mainContext

        switch kind {
        case .milestone:
            let descriptor = FetchDescriptor<Milestone>(
                predicate: #Predicate { $0.milestoneId == id }
            )
            if let milestone = try context.fetch(descriptor).first {
                TaskCompletionMutation.toggle(milestone)
            }
        case .subTask:
            let descriptor = FetchDescriptor<SubTask>(
                predicate: #Predicate { $0.taskId == id }
            )
            if let subtask = try context.fetch(descriptor).first {
                TaskCompletionMutation.toggle(subtask)
            }
        }

        try context.save()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedModelContainer.widgetKind)
        return .result()
    }
}
