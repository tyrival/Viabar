import AppKit
import Observation

@MainActor
@Observable
final class AppRuntimeController {
    let launchAtLogin = AppLaunchAtLoginController()
    private let globalShortcuts = AppGlobalShortcutController()

    private(set) var searchPresentationID = UUID()
    private(set) var navigationPresentationID = UUID()
    private weak var mainWindow: NSWindow?
    private var openMainWindow: (() -> Void)?
    private var isSearchPresentationPending = false
    private var pendingNavigationRequest: GlobalSearchNavigationRequest?

    init() {
        globalShortcuts.onCommand = { [weak self] command in
            switch command {
            case .toggleMainPanel:
                self?.toggleMainPanel()
            case .openSearch:
                self?.presentSearch()
            }
        }
    }

    func registerMainWindow(_ window: NSWindow?) {
        mainWindow = window
    }

    func registerMainWindowOpener(_ action: @escaping () -> Void) {
        openMainWindow = action
    }

    func configureShortcuts(from settings: AppSettings) throws {
        try globalShortcuts.reconfigure(
            AppShortcutConfiguration(
                toggleMainPanel: settings.toggleMainPanelShortcut,
                openSearch: settings.openSearchShortcut
            )
        )
    }

    func toggleMainPanel() {
        if let mainWindow,
           NSApplication.shared.isActive,
           mainWindow.isVisible,
           mainWindow.isKeyWindow {
            mainWindow.orderOut(nil)
        } else {
            showMainPanel()
        }
    }

    func presentSearch() {
        isSearchPresentationPending = true
        showMainPanel()
        searchPresentationID = UUID()
    }

    func consumePendingSearchPresentation() -> Bool {
        guard isSearchPresentationPending else { return false }
        isSearchPresentationPending = false
        return true
    }

    func navigate(to request: GlobalSearchNavigationRequest) {
        pendingNavigationRequest = request
        showMainPanel()
        navigationPresentationID = UUID()
    }

    func consumePendingNavigationRequest() -> GlobalSearchNavigationRequest? {
        defer { pendingNavigationRequest = nil }
        return pendingNavigationRequest
    }

    private func showMainPanel() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
}
