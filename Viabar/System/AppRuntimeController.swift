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
    private var mainWindowVisibilityPolicy = MainWindowVisibilityPolicy()
    nonisolated(unsafe) private var applicationObserverTokens: [NSObjectProtocol] = []

    init() {
        globalShortcuts.onCommand = { [weak self] command in
            switch command {
            case .toggleMainPanel:
                self?.toggleMainPanel()
            case .openSearch:
                self?.presentSearch()
            }
        }
        observeApplicationVisibility()
    }

    deinit {
        for token in applicationObserverTokens {
            NotificationCenter.default.removeObserver(token)
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

    func menuBarPanelDidPresent() {
        guard mainWindowVisibilityPolicy.consumeMenuBarPanelPresentationShouldHideMainWindow() else {
            return
        }
        mainWindow?.orderOut(nil)
    }

    func consumePendingNavigationRequest() -> GlobalSearchNavigationRequest? {
        defer { pendingNavigationRequest = nil }
        return pendingNavigationRequest
    }

    private func showMainPanel() {
        mainWindowVisibilityPolicy.cancelPendingMenuBarSuppression()
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    private func observeApplicationVisibility() {
        let notificationCenter = NotificationCenter.default
        applicationObserverTokens.append(
            notificationCenter.addObserver(
                forName: NSApplication.willHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.mainWindowVisibilityPolicy.applicationWillHide(
                        mainWindowIsVisible: self?.mainWindow?.isVisible == true
                    )
                }
            }
        )
        applicationObserverTokens.append(
            notificationCenter.addObserver(
                forName: NSApplication.didUnhideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.mainWindowVisibilityPolicy.applicationDidUnhideShouldHideMainWindow() {
                        self.mainWindow?.orderOut(nil)
                    }
                    let generation = self.mainWindowVisibilityPolicy.generation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.mainWindowVisibilityPolicy.cancelPendingMenuBarSuppression(
                            ifGeneration: generation
                        )
                    }
                }
            }
        )
    }
}

struct MainWindowVisibilityPolicy {
    private var isMenuBarSuppressionPending = false
    private var shouldHideMainWindowWhenApplicationUnhides = false
    private(set) var generation = 0

    mutating func applicationWillHide(mainWindowIsVisible: Bool) {
        generation += 1
        isMenuBarSuppressionPending = mainWindowIsVisible
        shouldHideMainWindowWhenApplicationUnhides = false
    }

    mutating func consumeMenuBarPanelPresentationShouldHideMainWindow() -> Bool {
        guard isMenuBarSuppressionPending else { return false }
        isMenuBarSuppressionPending = false
        shouldHideMainWindowWhenApplicationUnhides = true
        return true
    }

    mutating func applicationDidUnhideShouldHideMainWindow() -> Bool {
        defer { shouldHideMainWindowWhenApplicationUnhides = false }
        return shouldHideMainWindowWhenApplicationUnhides
    }

    mutating func cancelPendingMenuBarSuppression() {
        isMenuBarSuppressionPending = false
        shouldHideMainWindowWhenApplicationUnhides = false
    }

    mutating func cancelPendingMenuBarSuppression(ifGeneration generation: Int) {
        guard self.generation == generation else { return }
        cancelPendingMenuBarSuppression()
    }
}
