import AppIntents
import WidgetKit

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新任务列表"
    static var supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: SharedModelContainer.widgetKind)
        return .result()
    }
}
