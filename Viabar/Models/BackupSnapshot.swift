import Foundation

struct BackupSnapshot: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let createdAt: Date
    let settings: BackupSettingsSnapshot
    let folders: [BackupFolderSnapshot]
    let projects: [BackupProjectSnapshot]
    let templates: [BackupTemplateSnapshot]
    let trashItems: [BackupTrashItemSnapshot]

    init(
        formatVersion: Int,
        createdAt: Date,
        settings: BackupSettingsSnapshot,
        folders: [BackupFolderSnapshot],
        projects: [BackupProjectSnapshot],
        templates: [BackupTemplateSnapshot],
        trashItems: [BackupTrashItemSnapshot] = []
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.settings = settings
        self.folders = folders
        self.projects = projects
        self.templates = templates
        self.trashItems = trashItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        settings = try container.decode(BackupSettingsSnapshot.self, forKey: .settings)
        folders = try container.decode([BackupFolderSnapshot].self, forKey: .folders)
        projects = try container.decode([BackupProjectSnapshot].self, forKey: .projects)
        templates = try container.decode([BackupTemplateSnapshot].self, forKey: .templates)
        trashItems = try container.decodeIfPresent([BackupTrashItemSnapshot].self, forKey: .trashItems) ?? []
    }
}

struct BackupSettingsSnapshot: Codable, Equatable {
    var settingsId: String = "shared"
    var createdAt: Date = Date()
    var launchAtLogin: Bool = false
    var menuBarComponentEnabled: Bool = false
    var menuBarIcon: String = MenuBarIcon.bookmarkFill.rawValue
    var menuBarProjectScope: String = MenuBarProjectScope.allProjects.rawValue
    var menuBarContentMode: String = MenuBarContentMode.currentTask.rawValue
    var theme: String = AppTheme.system.rawValue
    var language: String = AppLanguage.system.rawValue
    var overviewScope: String = OverviewScope.allProjects.rawValue
    var weekStartDay: String?
    var weekdayFilterEnabled: Bool = false
    var dateFormat: String = AppDateFormat.defaultValue.rawValue
    var toggleMainPanelShortcut: String = "Option+V"
    var openSearchShortcut: String = "Command+F"
    var syncEnabled: Bool = true
    var lastSyncAt: Date?
    var backupEnabled: Bool
    var backupPath: String
    var trashRetentionPolicy: String?
    var automaticallyChecksForUpdates: Bool = true

    init(backupEnabled: Bool, backupPath: String) {
        self.backupEnabled = backupEnabled
        self.backupPath = backupPath
        trashRetentionPolicy = TrashRetentionPolicy.defaultValue.rawValue
    }

    init(settings: AppSettings) {
        settingsId = settings.settingsId
        createdAt = settings.createdAt
        launchAtLogin = settings.launchAtLogin
        menuBarComponentEnabled = settings.menuBarComponentEnabled
        menuBarIcon = settings.menuBarIcon
        menuBarProjectScope = settings.menuBarProjectScope
        menuBarContentMode = settings.menuBarContentMode
        theme = settings.theme
        language = settings.language
        overviewScope = settings.overviewScope
        weekStartDay = WeekStartDaySettingsStore.value().rawValue
        weekdayFilterEnabled = settings.weekdayFilterEnabled
        dateFormat = settings.dateFormat
        toggleMainPanelShortcut = settings.toggleMainPanelShortcut
        openSearchShortcut = settings.openSearchShortcut
        syncEnabled = settings.syncEnabled
        lastSyncAt = settings.lastSyncAt
        backupEnabled = settings.backupEnabled
        backupPath = settings.backupPath
        trashRetentionPolicy = TrashRetentionSettingsStore.policy().rawValue
        automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
    }
}

struct BackupFolderSnapshot: Codable, Equatable {
    let folderId: UUID
    let name: String
    let orderIndex: Int
    let parentId: UUID?
}

struct BackupReminderSnapshot: Codable, Equatable {
    let reminderId: UUID
    let type: String
    let fireTime: String?
    let fireTimestamp: Date?
    let repeatIntervalDays: Int?
    let lastTriggeredTimestamp: Date?

    init(
        reminderId: UUID,
        type: String,
        fireTime: String?,
        fireTimestamp: Date?,
        repeatIntervalDays: Int?,
        lastTriggeredTimestamp: Date?
    ) {
        self.reminderId = reminderId
        self.type = type
        self.fireTime = fireTime
        self.fireTimestamp = fireTimestamp
        self.repeatIntervalDays = repeatIntervalDays
        self.lastTriggeredTimestamp = lastTriggeredTimestamp
    }

    init(reminder: Reminder) {
        reminderId = reminder.reminderId
        type = reminder.type
        fireTime = reminder.fireTime
        fireTimestamp = reminder.fireTimestamp
        repeatIntervalDays = reminder.repeatIntervalDays
        lastTriggeredTimestamp = reminder.lastTriggeredTimestamp
    }
}

struct BackupProjectSnapshot: Codable, Equatable {
    let projectId: UUID
    let title: String
    let hideCompleted: Bool
    let isArchived: Bool
    let isFavorite: Bool
    let orderIndex: Int
    let archivedAt: Date?
    let accentColor: String
    let sfSymbolName: String
    let archiveFolderId: UUID?
    let reminder: BackupReminderSnapshot?
    let milestones: [BackupMilestoneSnapshot]
    let memos: [BackupMemoSnapshot]
}

struct BackupMilestoneSnapshot: Codable, Equatable {
    let milestoneId: UUID
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let orderIndex: Int
    let reminder: BackupReminderSnapshot?
    let subtasks: [BackupSubTaskSnapshot]
}

struct BackupSubTaskSnapshot: Codable, Equatable {
    let taskId: UUID
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let orderIndex: Int
    let reminder: BackupReminderSnapshot?
}

struct BackupMemoSnapshot: Codable, Equatable {
    let memoId: UUID
    let content: String
    let createdAt: Date
    let orderIndex: Int
}

struct BackupTemplateSnapshot: Codable, Equatable {
    let templateId: UUID
    let name: String
    let hideCompleted: Bool
    let orderIndex: Int
    let accentColor: String
    let sfSymbolName: String
    let milestones: [BackupTemplateMilestoneSnapshot]
}

struct BackupTemplateMilestoneSnapshot: Codable, Equatable {
    let milestoneId: UUID
    let title: String
    let orderIndex: Int
    let subtasks: [BackupTemplateSubTaskSnapshot]
}

struct BackupTemplateSubTaskSnapshot: Codable, Equatable {
    let taskId: UUID
    let title: String
    let orderIndex: Int
}

struct BackupTrashItemSnapshot: Codable, Equatable {
    let trashItemId: UUID
    let kind: String
    let deletedAt: Date
    let originalProjectId: UUID
    let originalProjectTitle: String
    let originalProjectAccentColor: String
    let originalProjectSymbolName: String
    let originalParentTaskId: UUID?
    let originalParentTaskTitle: String?
    let originalOrderIndex: Int
    let payloadVersion: Int
    let payloadData: Data
}

struct BackupFileMetadata: Identifiable, Hashable {
    let url: URL
    let createdAt: Date

    var id: URL { url }

    init(url: URL, createdAt: Date) {
        self.url = url
        self.createdAt = createdAt
    }

    init?(url: URL) {
        guard url.pathExtension == "viabackup",
              let date = Self.fileNameFormatter.date(from: url.deletingPathExtension().lastPathComponent)
        else { return nil }
        self.init(url: url, createdAt: date)
    }

    static func sortedNewestFirst(_ files: [BackupFileMetadata]) -> [BackupFileMetadata] {
        files.sorted { $0.createdAt > $1.createdAt }
    }

    static func url(in directory: URL, date: Date) -> URL {
        directory
            .appendingPathComponent(fileNameFormatter.string(from: date))
            .appendingPathExtension("viabackup")
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

enum BackupRetentionPolicy {
    static func urlsToDelete(
        from files: [BackupFileMetadata],
        now: Date,
        calendar: Calendar = .current
    ) -> Set<URL> {
        let hourlyBoundary = now.addingTimeInterval(-24 * 60 * 60)
        let dailyBoundary = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let weeklyBoundary = calendar.date(byAdding: .month, value: -6, to: now) ?? .distantPast
        var retainedBuckets = Set<String>()
        var deletes = Set<URL>()

        for file in BackupFileMetadata.sortedNewestFirst(files) {
            let key: String
            if file.createdAt >= hourlyBoundary {
                key = "hour-\(componentsKey([.year, .month, .day, .hour], for: file.createdAt, calendar: calendar))"
            } else if file.createdAt >= dailyBoundary {
                key = "day-\(componentsKey([.year, .month, .day], for: file.createdAt, calendar: calendar))"
            } else if file.createdAt >= weeklyBoundary {
                key = "week-\(componentsKey([.yearForWeekOfYear, .weekOfYear], for: file.createdAt, calendar: calendar))"
            } else {
                deletes.insert(file.url)
                continue
            }

            if retainedBuckets.contains(key) {
                deletes.insert(file.url)
            } else {
                retainedBuckets.insert(key)
            }
        }
        return deletes
    }

    private static func componentsKey(
        _ components: Set<Calendar.Component>,
        for date: Date,
        calendar: Calendar
    ) -> String {
        let value = calendar.dateComponents(components, from: date)
        return components.sorted { "\($0)" < "\($1)" }.map { component in
            "\(component)=\(value.value(for: component) ?? 0)"
        }.joined(separator: "-")
    }
}

extension JSONEncoder {
    static var backupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var backupDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
