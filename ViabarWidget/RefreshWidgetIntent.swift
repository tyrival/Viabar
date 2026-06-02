import AppIntents
import WidgetKit

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新任务列表"

    func perform() async throws -> some IntentResult {
        SharedModelContainer.widgetKinds.forEach {
            WidgetCenter.shared.reloadTimelines(ofKind: $0)
        }
        return .result()
    }
}
