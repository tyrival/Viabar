import Observation
import ServiceManagement

@MainActor
@Observable
final class AppLaunchAtLoginController {
    private(set) var isEnabled = false

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            refresh()
            throw error
        }

        refresh()
    }
}
