import AppKit

@MainActor
enum AppAppearanceController {
    static func apply(storedTheme: String) {
        apply(AppTheme(rawValue: storedTheme) ?? .system)
    }

    static func apply(_ theme: AppTheme) {
        let application = NSApplication.shared
        guard !isAlreadyApplied(theme, to: application) else { return }

        switch theme {
        case .system:
            application.appearance = nil
        case .light:
            application.appearance = NSAppearance(named: .aqua)
        case .dark:
            application.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private static func isAlreadyApplied(_ theme: AppTheme, to application: NSApplication) -> Bool {
        switch theme {
        case .system:
            application.appearance == nil
        case .light:
            application.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .aqua
        case .dark:
            application.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
}
