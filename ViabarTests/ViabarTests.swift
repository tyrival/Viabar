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
        #expect(settings.theme == AppTheme.system.rawValue)
        #expect(settings.language == AppLanguage.system.rawValue)
        #expect(settings.overviewScope == OverviewScope.allProjects.rawValue)
        #expect(settings.weekdayFilterEnabled == false)
        #expect(settings.dateFormat == AppDateFormat.yearMonthDaySlashes.rawValue)
        #expect(settings.toggleMainPanelShortcut == "Option+V")
        #expect(settings.openSearchShortcut == "Command+F")
        #expect(settings.syncEnabled == true)
        #expect(settings.lastSyncAt == nil)
        #expect(settings.backupEnabled == true)
        #expect(settings.backupPath == "~/Documents/Viabar")
        #expect(settings.automaticallyChecksForUpdates == true)
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
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["en-SG"]) == .english)
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["zh-Hant-TW"]) == .english)
        #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["ja-JP"]) == .english)
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
