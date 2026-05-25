import Foundation
import SwiftData

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "系统"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

enum OverviewScope: String, CaseIterable, Identifiable {
    case allProjects
    case favoriteProjects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allProjects: "所有项目"
        case .favoriteProjects: "星标项目"
        }
    }
}

enum AppDateFormat: String, CaseIterable, Identifiable {
    case yearMonthDaySlashes = "yyyy/MM/dd HH:mm"
    case yearMonthDayDashes = "yyyy-MM-dd HH:mm"
    case monthDay = "MM/dd HH:mm"
    case dayMonthYear = "dd/MM/yyyy HH:mm"

    static let defaultValue = AppDateFormat.yearMonthDaySlashes

    var id: String { rawValue }

    var example: String {
        AppDateFormatter.string(from: AppDateFormatter.exampleDate, pattern: rawValue)
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var settingsId: String
    var createdAt: Date
    var launchAtLogin: Bool
    var menuBarComponentEnabled: Bool
    var theme: String
    var language: String
    var overviewScope: String
    var weekdayFilterEnabled: Bool
    var dateFormat: String
    var toggleMainPanelShortcut: String
    var openSearchShortcut: String
    var syncEnabled: Bool
    var lastSyncAt: Date?
    var backupEnabled: Bool
    var backupPath: String
    var automaticallyChecksForUpdates: Bool = true

    init(
        settingsId: String = "shared",
        createdAt: Date = Date(),
        launchAtLogin: Bool = false,
        menuBarComponentEnabled: Bool = false,
        theme: String = AppTheme.system.rawValue,
        language: String = AppLanguage.system.rawValue,
        overviewScope: String = OverviewScope.allProjects.rawValue,
        weekdayFilterEnabled: Bool = false,
        dateFormat: String = AppDateFormat.defaultValue.rawValue,
        toggleMainPanelShortcut: String = "Option+V",
        openSearchShortcut: String = "Command+F",
        syncEnabled: Bool = true,
        lastSyncAt: Date? = nil,
        backupEnabled: Bool = true,
        backupPath: String = "~/Documents/Viabar",
        automaticallyChecksForUpdates: Bool = true
    ) {
        self.settingsId = settingsId
        self.createdAt = createdAt
        self.launchAtLogin = launchAtLogin
        self.menuBarComponentEnabled = menuBarComponentEnabled
        self.theme = theme
        self.language = language
        self.overviewScope = overviewScope
        self.weekdayFilterEnabled = weekdayFilterEnabled
        self.dateFormat = dateFormat
        self.toggleMainPanelShortcut = toggleMainPanelShortcut
        self.openSearchShortcut = openSearchShortcut
        self.syncEnabled = syncEnabled
        self.lastSyncAt = lastSyncAt
        self.backupEnabled = backupEnabled
        self.backupPath = backupPath
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
}

@MainActor
enum AppSettingsStore {
    @discardableResult
    static func ensureDefaultSettings(in context: ModelContext) -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\AppSettings.createdAt)]
        )
        descriptor.fetchLimit = 1

        if let settings = try? context.fetch(descriptor).first {
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }
}

enum AppDateFormatter {
    static let exampleDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 5, day: 24, hour: 14, minute: 30)
    )!

    static func resolvedFormat(for rawValue: String?) -> AppDateFormat {
        AppDateFormat(rawValue: rawValue ?? "") ?? .defaultValue
    }

    static func string(from date: Date, pattern: String?) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = resolvedFormat(for: pattern).rawValue
        return formatter.string(from: date)
    }
}

struct ShortcutKeyCombination: Equatable {
    enum Modifier: String, CaseIterable {
        case control = "Control"
        case option = "Option"
        case shift = "Shift"
        case command = "Command"

        var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    enum Key: Equatable {
        case character(String)
        case space
        case `return`
        case tab
        case delete
        case up
        case down
        case left
        case right
        case escape

        var storedValue: String {
            switch self {
            case .character(let value): value.uppercased()
            case .space: "Space"
            case .return: "Return"
            case .tab: "Tab"
            case .delete: "Delete"
            case .up: "Up"
            case .down: "Down"
            case .left: "Left"
            case .right: "Right"
            case .escape: "Escape"
            }
        }

        var displayValue: String {
            switch self {
            case .character(let value): value.uppercased()
            case .space: "Space"
            case .return: "Return"
            case .tab: "Tab"
            case .delete: "⌫"
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            case .escape: "Esc"
            }
        }
    }

    let modifiers: [Modifier]
    let key: Key

    init?(modifiers: [Modifier], key: Key) {
        let orderedModifiers = Modifier.allCases.filter { modifiers.contains($0) }
        guard !orderedModifiers.isEmpty, key != .escape else { return nil }

        self.modifiers = orderedModifiers
        self.key = key
    }

    var storedValue: String {
        (modifiers.map(\.rawValue) + [key.storedValue]).joined(separator: "+")
    }

    var displayValue: String {
        (modifiers.map(\.symbol) + [key.displayValue]).joined(separator: " ")
    }

    static func displayString(for storedValue: String) -> String {
        let components = storedValue.split(separator: "+").map(String.init)
        guard let last = components.last,
              let key = key(from: last) else {
            return storedValue
        }

        let modifiers = components.dropLast().compactMap { Modifier(rawValue: $0) }
        guard modifiers.count == components.count - 1,
              let combination = ShortcutKeyCombination(modifiers: modifiers, key: key) else {
            return storedValue
        }

        return combination.displayValue
    }

    private static func key(from storedValue: String) -> Key? {
        switch storedValue {
        case "Space": .space
        case "Return": .return
        case "Tab": .tab
        case "Delete": .delete
        case "Up": .up
        case "Down": .down
        case "Left": .left
        case "Right": .right
        case "Escape": .escape
        default:
            storedValue.count == 1 ? .character(storedValue) : nil
        }
    }
}
