import Foundation
import Testing
import SwiftData
@testable import Viabar

struct GlobalSearchTests {
    @Test func buildsProjectTaskSubtaskAndMemoResults() {
        let project = Project(title: "发布计划", orderIndex: 0)
        let milestone = Milestone(title: "准备发布页面信息架构复核", orderIndex: 0)
        milestone.project = project
        let subtask = SubTask(title: "发布公告复核", orderIndex: 0)
        subtask.milestone = milestone
        milestone.subtasks = [subtask]
        project.milestones = [milestone]
        let memo = Memo(content: "发布检查已结束", orderIndex: 0)
        memo.project = project
        project.memos = [memo]

        let results = GlobalSearchIndex.results(matching: "发布", projects: [project])

        #expect(results.map(\.text) == ["发布计划", "准备发布页面信息架构复核", "发布公告复核", "发布检查已结束"])
        #expect(results.map(\.path) == [
            "发布计划",
            "发布计划 / 准备发布页面信息架构复核",
            "发布计划 / 准备发布页面信息架… / 发布公告复核",
            "发布计划 / 备忘录",
        ])
    }

    @Test func prefixesArchivedResultsAndUsesFolderDisplayOrder() {
        let firstFolder = ArchiveFolder(name: "旧版本", orderIndex: 0)
        let secondFolder = ArchiveFolder(name: "试验", orderIndex: 1)
        let firstProject = archivedProject(title: "较晚标题", folder: firstFolder, orderIndex: 2)
        let secondProject = archivedProject(title: "较早标题", folder: secondFolder, orderIndex: 0)

        let results = GlobalSearchIndex.results(matching: "发布", projects: [secondProject, firstProject])

        #expect(results.map(\.path) == [
            "归档 / 较晚标题 / 备忘录",
            "归档 / 较早标题 / 备忘录",
        ])
    }

    private func archivedProject(title: String, folder: ArchiveFolder, orderIndex: Int) -> Project {
        let project = Project(title: title, orderIndex: orderIndex)
        project.isArchived = true
        project.archiveFolder = folder
        folder.projects.append(project)
        let memo = Memo(content: "发布回顾", orderIndex: 0)
        memo.project = project
        project.memos = [memo]
        return project
    }
}

@MainActor
struct ProjectTemplateAndFavoriteTests {
    @Test func createsIndependentUnfinishedTaskTreeFromTemplate() throws {
        let (service, context) = try makeService()
        let template = service.saveTemplate(
            nil,
            name: "发布模板",
            hideCompleted: false,
            accentColor: "#FFBF00",
            sfSymbolName: "flag.fill",
            milestones: [
                (title: "准备发布", subtasks: ["撰写公告", "验证包"]),
                (title: "发布后复核", subtasks: []),
            ]
        )

        let project = service.createProject(title: "五月发布", template: template)
        let templateMilestones = template.milestones.sorted { $0.orderIndex < $1.orderIndex }
        let templateSubtasks = templateMilestones[0].subtasks.sorted { $0.orderIndex < $1.orderIndex }
        let copiedMilestones = project.milestones.sorted { $0.orderIndex < $1.orderIndex }
        let copiedSubtasks = copiedMilestones[0].subtasks.sorted { $0.orderIndex < $1.orderIndex }

        #expect(project.hideCompleted == false)
        #expect(copiedMilestones.map(\.title) == ["准备发布", "发布后复核"])
        #expect(copiedSubtasks.map(\.title) == ["撰写公告", "验证包"])
        #expect(copiedMilestones.allSatisfy { !$0.isCompleted && $0.reminder == nil })
        #expect(copiedSubtasks.allSatisfy { !$0.isCompleted && $0.reminder == nil })
        #expect(copiedMilestones[0].milestoneId != templateMilestones[0].milestoneId)
        #expect(copiedSubtasks[0].taskId != templateSubtasks[0].taskId)

        copiedMilestones[0].title = "项目专属任务"
        service.save()
        #expect(templateMilestones[0].title == "准备发布")

        context.delete(template)
        try context.save()
        #expect(project.milestones.count == 2)
    }

    @Test func projectStartsUnfavoritedAndTogglePersistsFavoriteState() throws {
        let (service, _) = try makeService()
        let project = service.createProject(title: "重点项目")

        #expect(project.isFavorite == false)
        service.toggleFavorite(project)
        #expect(project.isFavorite == true)
        service.toggleFavorite(project)
        #expect(project.isFavorite == false)
    }

    private func makeService() throws -> (ProjectService, ModelContext) {
        let schema = Schema([
            Project.self,
            Milestone.self,
            SubTask.self,
            Memo.self,
            Reminder.self,
            NotificationScheduleEntry.self,
            ArchiveFolder.self,
            ProjectTemplate.self,
            TemplateMilestone.self,
            TemplateSubTask.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let container = ServiceContainer()
        let service = ProjectService(modelContext: modelContainer.mainContext, container: container)
        container.register(service)
        return (service, modelContainer.mainContext)
    }
}

struct AppSettingsTests {
    @Test func initializesDocumentedDefaults() {
        let settings = AppSettings()

        #expect(settings.launchAtLogin == false)
        #expect(settings.menuBarComponentEnabled == false)
        #expect(settings.menuBarIcon == MenuBarIcon.bookmarkFill.rawValue)
        #expect(settings.menuBarProjectScope == MenuBarProjectScope.allProjects.rawValue)
        #expect(settings.menuBarContentMode == MenuBarContentMode.currentTask.rawValue)
        #expect(settings.theme == AppTheme.system.rawValue)
        #expect(settings.language == AppLanguage.system.rawValue)
        #expect(settings.overviewScope == OverviewScope.allProjects.rawValue)
        #expect(settings.weekdayFilterEnabled == false)
        #expect(settings.dateFormat == AppDateFormat.yearMonthDaySlashes.rawValue)
        #expect(settings.toggleMainPanelShortcut == "Option+V")
        #expect(settings.openSearchShortcut == "Command+F")
        #expect(settings.syncEnabled == true)
        #expect(settings.lastSyncAt == nil)
        #expect(settings.backupEnabled == false)
        #expect(settings.backupPath == "")
        #expect(settings.backupBookmarkData == nil)
        #expect(settings.automaticallyChecksForUpdates == true)
    }

    @Test func resolvesInvalidMenuBarSavedValuesToDocumentedDefaults() {
        #expect(MenuBarIcon.resolve("not-a-symbol") == .bookmarkFill)
        #expect(MenuBarProjectScope.resolve("not-a-scope") == .allProjects)
        #expect(MenuBarContentMode.resolve("not-a-mode") == .currentTask)
        #expect(MenuBarIcon.allCases.map(\.rawValue) == [
            "bookmark",
            "bookmark.fill",
            "bookmark.circle",
            "bookmark.circle.fill",
            "star.rectangle",
            "star.rectangle.fill",
            "list.bullet.rectangle",
            "list.bullet.rectangle.fill",
            "checkmark.seal",
            "checkmark.seal.fill",
            "checkmark.rectangle",
            "checkmark.rectangle.fill",
        ])
    }

    @Test func formatsDatesUsingEverySupportedSelection() {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 5, day: 24, hour: 14, minute: 30)
        )!

        #expect(AppDateFormatter.string(from: date, pattern: "yyyy/MM/dd HH:mm") == "2026/05/24 14:30")
        #expect(AppDateFormatter.string(from: date, pattern: "yyyy-MM-dd HH:mm") == "2026-05-24 14:30")
        #expect(AppDateFormatter.string(from: date, pattern: "MM/dd HH:mm") == "05/24 14:30")
        #expect(AppDateFormatter.string(from: date, pattern: "dd/MM/yyyy HH:mm") == "24/05/2026 14:30")
    }

    @Test func fallsBackToDefaultDateFormatForUnknownSavedValue() {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 5, day: 24, hour: 14, minute: 30)
        )!

        #expect(AppDateFormatter.string(from: date, pattern: "invalid") == "2026/05/24 14:30")
    }

    @Test func rendersStoredShortcutValuesWithMacSymbols() {
        #expect(ShortcutKeyCombination.displayString(for: "Option+V") == "⌥ V")
        #expect(ShortcutKeyCombination.displayString(for: "Command+F") == "⌘ F")
        #expect(
            ShortcutKeyCombination.displayString(for: "Control+Option+Shift+Command+Left")
                == "⌃ ⌥ ⇧ ⌘ ←"
        )
    }

    @Test func createsCanonicalStoredShortcutValues() {
        #expect(
            ShortcutKeyCombination(
                modifiers: [.command, .shift],
                key: .character("f")
            )?.storedValue == "Shift+Command+F"
        )
        #expect(
            ShortcutKeyCombination(
                modifiers: [.option],
                key: .space
            )?.storedValue == "Option+Space"
        )
    }

    @Test func rejectsShortcutWithoutModifiersOrWithEscape() {
        #expect(ShortcutKeyCombination(modifiers: [], key: .character("V")) == nil)
        #expect(ShortcutKeyCombination(modifiers: [.command], key: .escape) == nil)
    }

    @Test func resolvesLanguageImmediatelyWithEnglishSystemFallback() {
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["zh-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["en-SG"]) == .english)
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["zh-Hant-TW"]) == .english)
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["ja-JP"]) == .english)
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["ja-JP", "zh-Hans-CN"]) == .english)
        #expect(AppLanguage.effectiveLanguage(storedValue: "invalid", preferredLanguages: ["zh-Hans"]) == .simplifiedChinese)
        #expect(AppLanguage.effectiveLanguage(storedValue: "english", preferredLanguages: ["zh-Hans"]) == .english)
        #expect(AppLanguage.effectiveLanguage(storedValue: "simplifiedChinese", preferredLanguages: ["en"]) == .simplifiedChinese)
    }

    @Test func overviewScopeFiltersOnlyActiveProjects() {
        let active = Project(title: "Active", orderIndex: 0)
        let favorite = Project(title: "Favorite", orderIndex: 1)
        favorite.isFavorite = true
        let archivedFavorite = Project(title: "Archived", orderIndex: 2)
        archivedFavorite.isFavorite = true
        archivedFavorite.isArchived = true

        #expect(
            OverviewScope.visibleProjects(
                from: [active, favorite, archivedFavorite],
                storedValue: "allProjects"
            ).map(\.title) == ["Active", "Favorite"]
        )
        #expect(
            OverviewScope.visibleProjects(
                from: [active, favorite, archivedFavorite],
                storedValue: "favoriteProjects"
            ).map(\.title) == ["Favorite"]
        )
        #expect(OverviewScope.visibleProjects(from: [active, favorite], storedValue: "invalid").count == 2)
    }

    @Test func rejectsDuplicateConfiguredShortcuts() {
        #expect(AppShortcutConfiguration(toggleMainPanel: "Option+V", openSearch: "Command+F").isValid)
        #expect(!AppShortcutConfiguration(toggleMainPanel: "Option+V", openSearch: "Option+V").isValid)
    }
}

struct MenuBarContentTests {
    @Test func currentModeReturnsFirstUnfinishedSubtaskOnly() {
        let project = Project(title: "Release", orderIndex: 0)
        let milestone = Milestone(title: "Prepare", orderIndex: 0)
        let finished = SubTask(title: "Done", orderIndex: 0, isCompleted: true)
        let target = SubTask(title: "Review", orderIndex: 1)
        finished.milestone = milestone
        target.milestone = milestone
        milestone.project = project
        milestone.subtasks = [finished, target]
        project.milestones = [milestone]

        let cards = MenuBarContentBuilder.cards(
            from: [project],
            scope: .allProjects,
            mode: .currentTask,
            now: Date()
        )

        #expect(cards.count == 1)
        #expect(cards[0].entries.map(\.title) == ["Review"])
        #expect(cards[0].entries[0].parentTitle == "Prepare")
        #expect(
            cards[0].entries[0].destination
                == .subTask(milestoneID: milestone.milestoneId, subTaskID: target.taskId)
        )
    }

    @Test func currentModeCarriesTheVisibleTasksReminderForInlinePresentation() {
        let project = Project(title: "Release", orderIndex: 0)
        let milestone = Milestone(title: "Prepare", orderIndex: 0)
        let fireDate = Date().addingTimeInterval(3600)
        milestone.reminder = Reminder(
            type: "repeating",
            fireTimestamp: fireDate,
            repeatIntervalDays: 7
        )
        milestone.project = project
        project.milestones = [milestone]

        let cards = MenuBarContentBuilder.cards(
            from: [project],
            scope: .allProjects,
            mode: .currentTask,
            now: Date()
        )

        #expect(cards[0].entries[0].reminder?.fireTimestamp == fireDate)
        #expect(cards[0].entries[0].reminder?.repeatIntervalDays == 7)
    }

    @Test func reminderModeFiltersByEndOfTodayAndOrdersMatchingRows() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 12))!
        let project = Project(title: "Release")
        let overdue = Milestone(title: "Overdue", orderIndex: 0)
        let laterToday = Milestone(title: "Later Today", orderIndex: 1)
        let tomorrow = Milestone(title: "Tomorrow", orderIndex: 2)
        overdue.project = project
        laterToday.project = project
        tomorrow.project = project
        overdue.reminder = Reminder(type: "single", fireTimestamp: now.addingTimeInterval(-3600))
        laterToday.reminder = Reminder(type: "single", fireTimestamp: now.addingTimeInterval(3600))
        tomorrow.reminder = Reminder(type: "single", fireTimestamp: now.addingTimeInterval(86400))
        project.milestones = [overdue, laterToday, tomorrow]

        let cards = MenuBarContentBuilder.cards(
            from: [project],
            scope: .allProjects,
            mode: .reminderTask,
            now: now,
            calendar: calendar
        )

        #expect(cards[0].entries.map(\.title) == ["Overdue", "Later Today"])
    }

    @Test func mapsProjectReminderAndFiltersArchivedOrUnstarredProjects() {
        let now = Date()
        let favorite = Project(title: "Favorite", orderIndex: 0)
        favorite.isFavorite = true
        let milestone = Milestone(title: "Mapped Task", orderIndex: 0)
        milestone.project = favorite
        favorite.milestones = [milestone]
        favorite.reminder = Reminder(type: "single", fireTimestamp: now)
        let unstarred = Project(title: "Other", orderIndex: 1)
        let archived = Project(title: "Archived", orderIndex: 2)
        archived.isFavorite = true
        archived.isArchived = true

        let cards = MenuBarContentBuilder.cards(
            from: [favorite, unstarred, archived],
            scope: .favoriteProjects,
            mode: .reminderTask,
            now: now
        )

        #expect(cards.map(\.project.title) == ["Favorite"])
        #expect(cards[0].entries[0].source == .projectReminder)
        #expect(cards[0].entries[0].destination == .milestone(milestone.milestoneId))
    }
}

struct OverviewReportTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 26, hour: 12))!
    }

    @Test func completedSectionsIncludeOnlyTasksCompletedInTheirPeriod() {
        let project = Project(title: "Website", orderIndex: 0)
        project.isArchived = true

        let standalone = Milestone(title: "Launch", orderIndex: 0, isCompleted: true)
        standalone.completedAt = calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 25, hour: 9)
        )
        standalone.project = project

        let parent = Milestone(title: "Design System", orderIndex: 1, isCompleted: true)
        parent.project = project
        let thisWeek = SubTask(title: "Tokens", orderIndex: 0, isCompleted: true)
        thisWeek.completedAt = calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 26, hour: 10)
        )
        thisWeek.milestone = parent
        let earlierThisMonth = SubTask(title: "Typography", orderIndex: 1, isCompleted: true)
        earlierThisMonth.completedAt = calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 5, hour: 10)
        )
        earlierThisMonth.milestone = parent
        parent.subtasks = [thisWeek, earlierThisMonth]
        project.milestones = [standalone, parent]

        let report = OverviewReportBuilder.makeReport(
            projects: [project],
            scheduleEntries: [],
            now: now,
            calendar: calendar
        )

        #expect(report.thisWeek.cards[0].project.isArchived)
        #expect(report.thisWeek.cards[0].groups.map(\.title) == ["Launch", "Design System"])
        #expect(report.thisWeek.cards[0].groups[1].subtasks.map(\.title) == ["Tokens"])
        #expect(report.thisMonth.cards[0].groups[1].subtasks.map(\.title) == ["Tokens", "Typography"])
        #expect(report.thisWeek.copyText == """
        1. Website
        - Launch
        - Design System
          - Tokens
        """)
    }

    @Test func completionIntervalUsesExclusiveEndBoundary() {
        let project = Project(title: "Boundary")
        let task = Milestone(title: "Next Month", isCompleted: true)
        task.completedAt = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))
        task.project = project
        project.milestones = [task]

        let report = OverviewReportBuilder.makeReport(
            projects: [project],
            scheduleEntries: [],
            now: now,
            calendar: calendar
        )

        #expect(report.thisWeek.cards.isEmpty)
        #expect(report.thisMonth.cards.isEmpty)
    }

    @Test func nextWeekExpandsProjectReminderAndDeduplicatesSubtaskReminder() {
        let project = Project(title: "App", orderIndex: 0)
        let parent = Milestone(title: "Store Review", orderIndex: 0)
        parent.project = project
        let screenshots = SubTask(title: "Screenshots", orderIndex: 0)
        let copy = SubTask(title: "Localized Copy", orderIndex: 1)
        screenshots.milestone = parent
        copy.milestone = parent
        parent.subtasks = [screenshots, copy]
        project.milestones = [parent]

        let nextWeek = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 2, hour: 9)
        )!
        let entries = [
            NotificationScheduleEntry(
                ownerId: project.projectId,
                ownerKind: "project",
                projectId: project.projectId,
                projectTitle: project.title,
                body: "",
                fireDate: nextWeek
            ),
            NotificationScheduleEntry(
                ownerId: screenshots.taskId,
                ownerKind: "subtask",
                projectId: project.projectId,
                projectTitle: project.title,
                body: screenshots.title,
                fireDate: nextWeek
            ),
        ]

        let report = OverviewReportBuilder.makeReport(
            projects: [project],
            scheduleEntries: entries,
            now: now,
            calendar: calendar
        )

        #expect(report.nextWeek.cards[0].groups[0].title == "Store Review")
        #expect(report.nextWeek.cards[0].groups[0].subtasks.map(\.title) == ["Screenshots", "Localized Copy"])
        #expect(report.nextWeek.copyText == """
        1. App
        - Store Review
          - Screenshots
          - Localized Copy
        """)
    }

    @Test func nextWeekIncludesDirectRemindersButExcludesArchivedProjects() {
        let active = Project(title: "Active", orderIndex: 0)
        let activeTask = Milestone(title: "Prepare", orderIndex: 0)
        activeTask.project = active
        active.milestones = [activeTask]

        let archived = Project(title: "Archived", orderIndex: 1)
        archived.isArchived = true
        let archivedTask = Milestone(title: "Hidden Task", orderIndex: 0)
        archivedTask.project = archived
        archived.milestones = [archivedTask]
        archived.reminder = Reminder(type: "single", fireTimestamp: now)

        let nextWeek = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 2, hour: 9)
        )!
        let entries = [
            NotificationScheduleEntry(
                ownerId: activeTask.milestoneId,
                ownerKind: "milestone",
                projectId: active.projectId,
                projectTitle: active.title,
                body: activeTask.title,
                fireDate: nextWeek
            ),
            NotificationScheduleEntry(
                ownerId: archivedTask.milestoneId,
                ownerKind: "milestone",
                projectId: archived.projectId,
                projectTitle: archived.title,
                body: archivedTask.title,
                fireDate: nextWeek
            ),
        ]

        let report = OverviewReportBuilder.makeReport(
            projects: [archived, active],
            scheduleEntries: entries,
            now: now,
            calendar: calendar
        )

        #expect(report.nextWeek.cards.map(\.project.title) == ["Active"])
        #expect(report.nextWeek.cards[0].groups.map(\.title) == ["Prepare"])
    }
}

struct BackupMetadataTests {
    @Test func parsesAndSortsBackupFilesNewestFirst() throws {
        let older = try #require(
            BackupFileMetadata(url: URL(fileURLWithPath: "/tmp/20260524-101000.viabackup"))
        )
        let newer = try #require(
            BackupFileMetadata(url: URL(fileURLWithPath: "/tmp/20260525-211900.viabackup"))
        )

        #expect(BackupFileMetadata.sortedNewestFirst([older, newer]).map(\.url.lastPathComponent) == [
            "20260525-211900.viabackup",
            "20260524-101000.viabackup",
        ])
        #expect(BackupFileMetadata(url: URL(fileURLWithPath: "/tmp/not-a-backup.viabackup")) == nil)
    }

    @Test func retainsHourlyDailyWeeklyAndDeletesExpiredBackups() {
        let now = Date(timeIntervalSince1970: 1_769_342_400)
        let files = [
            metadata("latest-hour", hoursBefore: 1, now: now),
            metadata("duplicate-hour", hoursBefore: 1.2, now: now),
            metadata("latest-day", hoursBefore: 30, now: now),
            metadata("duplicate-day", hoursBefore: 33, now: now),
            metadata("latest-week", hoursBefore: 24 * 12, now: now),
            metadata("duplicate-week", hoursBefore: 24 * 13, now: now),
            metadata("expired", hoursBefore: 24 * 190, now: now),
        ]

        let deleted = BackupRetentionPolicy.urlsToDelete(from: files, now: now)

        #expect(deleted == Set([
            URL(fileURLWithPath: "/tmp/duplicate-hour.viabackup"),
            URL(fileURLWithPath: "/tmp/duplicate-day.viabackup"),
            URL(fileURLWithPath: "/tmp/duplicate-week.viabackup"),
            URL(fileURLWithPath: "/tmp/expired.viabackup"),
        ]))
    }

    @Test func roundTripsVersionedBackupSnapshot() throws {
        let snapshot = BackupSnapshot(
            formatVersion: BackupSnapshot.currentFormatVersion,
            createdAt: Date(timeIntervalSince1970: 0),
            settings: BackupSettingsSnapshot(backupEnabled: true, backupPath: "~/Documents/Viabar"),
            folders: [],
            projects: [],
            templates: []
        )

        let encoded = try JSONEncoder.backupEncoder.encode(snapshot)

        #expect(try JSONDecoder.backupDecoder.decode(BackupSnapshot.self, from: encoded) == snapshot)
    }

    private func metadata(_ name: String, hoursBefore: Double, now: Date) -> BackupFileMetadata {
        BackupFileMetadata(
            url: URL(fileURLWithPath: "/tmp/\(name).viabackup"),
            createdAt: now.addingTimeInterval(-hoursBefore * 3600)
        )
    }
}

@MainActor
struct BackupRestoreTests {
    @Test func restoreRebuildsNotificationTimelineFromReminderConfiguration() throws {
        let schema = Schema([
            Project.self,
            Milestone.self,
            SubTask.self,
            Memo.self,
            Reminder.self,
            NotificationScheduleEntry.self,
            ArchiveFolder.self,
            ProjectTemplate.self,
            TemplateMilestone.self,
            TemplateSubTask.self,
            AppSettings.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let schedule = NotificationScheduleService(modelContext: context, notificationPoster: { _, _ in })
        let service = BackupService(modelContext: context, notificationScheduleService: schedule)
        let fireDate = Date().addingTimeInterval(3600)
        let projectID = UUID()
        let milestoneID = UUID()
        let snapshot = BackupSnapshot(
            formatVersion: BackupSnapshot.currentFormatVersion,
            createdAt: Date(),
            settings: BackupSettingsSnapshot(backupEnabled: true, backupPath: "~/Documents/Viabar"),
            folders: [],
            projects: [
                BackupProjectSnapshot(
                    projectId: projectID,
                    title: "Recovered",
                    hideCompleted: true,
                    isArchived: false,
                    isFavorite: false,
                    orderIndex: 0,
                    archivedAt: nil,
                    accentColor: ViabarColor.primaryHex,
                    sfSymbolName: "bookmark.fill",
                    archiveFolderId: nil,
                    reminder: nil,
                    milestones: [
                        BackupMilestoneSnapshot(
                            milestoneId: milestoneID,
                            title: "Future",
                            isCompleted: false,
                            completedAt: nil,
                            orderIndex: 0,
                            reminder: BackupReminderSnapshot(
                                reminderId: UUID(),
                                type: "single",
                                fireTime: nil,
                                fireTimestamp: fireDate,
                                repeatIntervalDays: nil,
                                lastTriggeredTimestamp: nil
                            ),
                            subtasks: []
                        ),
                    ],
                    memos: []
                ),
            ],
            templates: []
        )

        try service.restore(snapshot: snapshot)

        #expect(try context.fetch(FetchDescriptor<Project>()).map(\.title) == ["Recovered"])
        #expect(try context.fetch(FetchDescriptor<NotificationScheduleEntry>()).map(\.ownerId) == [milestoneID])
    }
}

@MainActor
struct NotificationScheduleLifecycleTests {
    @Test func singleTaskReminderRemainsPersistedAfterNotificationIsConsumed() throws {
        let (service, scheduleService, context) = try makeServices()
        let project = service.createProject(title: "Release")
        let milestone = service.addMilestone(to: project, title: "Review")
        let firedAt = Date().addingTimeInterval(60)
        service.updateReminder(Reminder(type: "single", fireTimestamp: firedAt), for: milestone)

        scheduleService.processDueEntries(now: firedAt.addingTimeInterval(1))

        #expect(milestone.reminder?.fireTimestamp == firedAt)
        #expect(fetchEntries(in: context).isEmpty)
    }

    @Test func repeatingSubTaskReminderAdvancesToTheNextFutureFireDate() throws {
        let (service, scheduleService, context) = try makeServices()
        let project = service.createProject(title: "Release")
        let milestone = service.addMilestone(to: project, title: "Prepare")
        let subTask = service.addSubTask(to: milestone, title: "Review")
        let firedAt = Date().addingTimeInterval(60)
        let now = firedAt.addingTimeInterval(3 * 86_400)
        service.updateReminder(
            Reminder(type: "repeating", fireTimestamp: firedAt, repeatIntervalDays: 1),
            for: subTask
        )

        scheduleService.processDueEntries(now: now)

        let advancedDate = try #require(subTask.reminder?.fireTimestamp)
        #expect(advancedDate > now)
        #expect(fetchEntries(in: context).map(\.fireDate) == [advancedDate])
    }

    @Test func projectNotificationUsesSelectedEnglishLanguageForBuiltInBody() throws {
        var deliveredNotification: (title: String, body: String)?
        let (service, scheduleService, context) = try makeServices { title, body in
            deliveredNotification = (title, body)
        }
        context.insert(AppSettings(language: AppLanguage.english.rawValue))
        let project = service.createProject(title: "Release")
        _ = service.addMilestone(to: project, title: "Review")
        let firedAt = Date().addingTimeInterval(60)
        project.reminder = Reminder(type: "single", fireTimestamp: firedAt)
        scheduleService.syncProject(project)

        scheduleService.processDueEntries(now: firedAt.addingTimeInterval(1))

        #expect(deliveredNotification?.title == "Release")
        #expect(deliveredNotification?.body == "Next: Review")
    }

    private func makeServices(
        notificationPoster: @escaping (String, String) -> Void = { _, _ in }
    ) throws -> (ProjectService, NotificationScheduleService, ModelContext) {
        let schema = Schema([
            Project.self,
            Milestone.self,
            SubTask.self,
            Memo.self,
            Reminder.self,
            NotificationScheduleEntry.self,
            ArchiveFolder.self,
            ProjectTemplate.self,
            TemplateMilestone.self,
            TemplateSubTask.self,
            AppSettings.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let context = modelContainer.mainContext
        let container = ServiceContainer()
        let service = ProjectService(modelContext: context, container: container)
        let scheduleService = NotificationScheduleService(modelContext: context, notificationPoster: notificationPoster)
        container.register(service)
        container.register(scheduleService)
        return (service, scheduleService, context)
    }

    private func fetchEntries(in context: ModelContext) -> [NotificationScheduleEntry] {
        (try? context.fetch(FetchDescriptor<NotificationScheduleEntry>())) ?? []
    }
}
