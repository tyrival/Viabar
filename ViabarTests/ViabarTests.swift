import Foundation
import Testing
import SwiftData
@testable import Viabar

struct TrashItemModelTests {
    @Test func taskPayloadCopiesNestedSubtasksAsHierarchy() throws {
        let payload = TrashPayload.task(
            TrashTaskSnapshot(
                title: "发布准备",
                isCompleted: false,
                completedAt: nil,
                reminder: nil,
                subtasks: [
                    TrashSubTaskSnapshot(
                        title: "打包",
                        isCompleted: false,
                        completedAt: nil,
                        orderIndex: 0,
                        reminder: nil
                    ),
                    TrashSubTaskSnapshot(
                        title: "上传",
                        isCompleted: true,
                        completedAt: Date(timeIntervalSince1970: 10),
                        orderIndex: 1,
                        reminder: nil
                    ),
                ]
            )
        )
        let item = try TrashItem.fixture(projectTitle: "Viabar", payload: payload)

        #expect(try item.copyText() == "发布准备\n- 打包\n- 上传")
        #expect(try item.matches("viabar"))
        #expect(try item.matches("上传"))
        #expect(item.displayText == "发布准备")
        #expect(item.displayPath == "Viabar / 任务")
    }

    @Test func subtaskMatchesNestedTextAndUsesCompactedParentPath() throws {
        let item = try TrashItem.fixture(
            projectTitle: "Viabar",
            parentTaskTitle: "准备发布页面信息架构复核",
            payload: .subTask(
                TrashSubTaskSnapshot(
                    title: "发布公告复核",
                    isCompleted: false,
                    completedAt: nil,
                    orderIndex: 0,
                    reminder: nil
                )
            )
        )

        #expect(try item.matches("发布公告"))
        #expect(item.displayPath == "Viabar / 准备发布页面信息架… / 子任务")
    }

    @Test func emptySearchReturnsAllTrashItemsNewestFirst() throws {
        let older = try TrashItem.fixture(
            deletedAt: Date(timeIntervalSince1970: 10),
            payload: .memo(.init(content: "旧", createdAt: .distantPast))
        )
        let newer = try TrashItem.fixture(
            deletedAt: Date(timeIntervalSince1970: 20),
            payload: .memo(.init(content: "新", createdAt: .distantPast))
        )

        #expect(
            TrashItemIndex.results(matching: "  ", items: [older, newer]).map(\.trashItemId)
                == [newer.trashItemId, older.trashItemId]
        )
    }

    @Test func newestTrashItemsSortFirst() throws {
        let older = try TrashItem.fixture(
            deletedAt: Date(timeIntervalSince1970: 10),
            payload: .memo(.init(content: "旧", createdAt: .distantPast))
        )
        let newer = try TrashItem.fixture(
            deletedAt: Date(timeIntervalSince1970: 20),
            payload: .memo(.init(content: "新", createdAt: .distantPast))
        )

        #expect(
            TrashItemIndex.sortedNewestFirst([older, newer]).map(\.trashItemId)
                == [newer.trashItemId, older.trashItemId]
        )
    }

    @Test func retentionDeletesExpiredItems() throws {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let recent = try TrashItem.fixture(deletedAt: now.addingTimeInterval(-29 * 86_400))
        let expired = try TrashItem.fixture(deletedAt: now.addingTimeInterval(-31 * 86_400))

        #expect(
            TrashRetentionPolicy.thirtyDays.expiredItems(from: [recent, expired], now: now)
                .map(\.trashItemId) == [expired.trashItemId]
        )
    }
}

private extension TrashItem {
    static func fixture(
        deletedAt: Date = Date(),
        projectTitle: String = "Viabar",
        parentTaskTitle: String? = nil,
        payload: TrashPayload = .memo(.init(content: "备忘录", createdAt: .distantPast))
    ) throws -> TrashItem {
        TrashItem(
            kind: payload.kind,
            deletedAt: deletedAt,
            originalProjectId: UUID(),
            originalProjectTitle: projectTitle,
            originalProjectAccentColor: ViabarColor.primaryHex,
            originalProjectSymbolName: "bookmark.fill",
            originalParentTaskId: parentTaskTitle == nil ? nil : UUID(),
            originalParentTaskTitle: parentTaskTitle,
            originalOrderIndex: 0,
            payloadVersion: TrashItem.currentPayloadVersion,
            payloadData: try JSONEncoder.backupEncoder.encode(payload)
        )
    }
}

@MainActor
struct TrashServiceTests {
    @Test func deletingTaskStoresOneSnapshotAndRestoreRecreatesChildren() throws {
        let (projectService, trashService, _, trashContext) = try makeServices()
        let project = projectService.createProject(title: "发布")
        let milestone = projectService.addMilestone(to: project, title: "准备")
        milestone.markerColor = TaskMarkerColor.red.rawValue
        let packaged = projectService.addSubTask(to: milestone, title: "打包")
        packaged.markerColor = TaskMarkerColor.green.rawValue
        _ = projectService.addSubTask(to: milestone, title: "上传")

        projectService.deleteMilestone(milestone)

        let item = try #require(trashContext.fetch(FetchDescriptor<TrashItem>()).first)
        #expect(project.milestones.isEmpty)
        #expect(try item.copyText() == "准备\n- 打包\n- 上传")

        try trashService.restore(item)

        #expect(project.milestones.map(\.title) == ["准备"])
        #expect(project.milestones[0].markerColor == TaskMarkerColor.red.rawValue)
        #expect(project.milestones[0].subtasks.map(\.title).sorted() == ["上传", "打包"])
        #expect(project.milestones[0].subtasks.first { $0.title == "打包" }?.markerColor == TaskMarkerColor.green.rawValue)
        #expect(try trashContext.fetch(FetchDescriptor<TrashItem>()).isEmpty)
    }

    @Test func directlyDeletedSubtaskRequiresOriginalParent() throws {
        let (projectService, trashService, projectContext, trashContext) = try makeServices()
        let project = projectService.createProject(title: "发布")
        let milestone = projectService.addMilestone(to: project, title: "准备")
        let subTask = projectService.addSubTask(to: milestone, title: "打包")

        projectService.deleteSubTask(subTask)

        let item = try #require(trashContext.fetch(FetchDescriptor<TrashItem>()).first)
        #expect(trashService.restoreAvailability(for: item) == .available)
        projectContext.delete(milestone)
        try projectContext.save()
        #expect(trashService.restoreAvailability(for: item) == .missingParentTask)
    }

    @Test func deletingMemoStoresSnapshotAndRestoreRecreatesMemo() throws {
        let (projectService, trashService, _, trashContext) = try makeServices()
        let project = projectService.createProject(title: "发布")
        let memo = projectService.addMemo(to: project, content: "回顾")

        projectService.deleteMemo(memo)

        let item = try #require(trashContext.fetch(FetchDescriptor<TrashItem>()).first)
        try trashService.restore(item)

        #expect(project.memos.map(\.content) == ["回顾"])
    }

    @Test func deletingTaskFallsBackToProjectCollectionWhenInverseIsMissing() throws {
        let (projectService, _, projectContext, trashContext) = try makeServices()
        let project = projectService.createProject(title: "旧项目")
        let milestone = Milestone(title: "旧任务")
        project.milestones.append(milestone)
        projectContext.insert(milestone)
        try projectContext.save()
        milestone.project = nil

        projectService.deleteMilestone(milestone)

        #expect(try trashContext.fetch(FetchDescriptor<TrashItem>()).count == 1)
    }

    @Test func cleanupDeletesOnlyExpiredTrashItems() throws {
        let (_, trashService, _, trashContext) = try makeServices()
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        trashContext.insert(try TrashItem.fixture(deletedAt: now.addingTimeInterval(-29 * 86_400)))
        trashContext.insert(try TrashItem.fixture(deletedAt: now.addingTimeInterval(-31 * 86_400)))

        try trashService.cleanupExpired(policy: .thirtyDays, now: now)

        #expect(try trashContext.fetch(FetchDescriptor<TrashItem>()).count == 1)
    }

    @Test func trashItemsLoadIncrementallyInPages() throws {
        let (_, trashService, _, trashContext) = try makeServices()
        for index in 0..<45 {
            trashContext.insert(try TrashItem.fixture(
                deletedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }

        try trashService.cleanupExpired(
            policy: .ninetyDays,
            now: Date(timeIntervalSince1970: 45)
        )

        #expect(trashService.items.count == 40)
        #expect(trashService.hasMoreItems)
        trashService.loadNextPage()
        #expect(trashService.items.count == 45)
        #expect(!trashService.hasMoreItems)
    }

    private func makeServices() throws -> (ProjectService, TrashService, ModelContext, ModelContext) {
        let projectSchema = Schema([
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
        let projectConfiguration = ModelConfiguration(schema: projectSchema, isStoredInMemoryOnly: true)
        let projectContainer = try ModelContainer(for: projectSchema, configurations: [projectConfiguration])
        let projectContext = projectContainer.mainContext
        let trashSchema = Schema([TrashItem.self])
        let trashConfiguration = ModelConfiguration(schema: trashSchema, isStoredInMemoryOnly: true)
        let trashContainer = try ModelContainer(for: trashSchema, configurations: [trashConfiguration])
        let trashContext = trashContainer.mainContext
        let container = ServiceContainer()
        let scheduleService = NotificationScheduleService(modelContext: projectContext, notificationPoster: { _, _ in })
        let trashService = TrashService(
            modelContext: trashContext,
            projectModelContext: projectContext,
            notificationScheduleService: scheduleService
        )
        let projectService = ProjectService(modelContext: projectContext, container: container)
        container.register(scheduleService)
        container.register(trashService)
        container.register(projectService)
        return (projectService, trashService, projectContext, trashContext)
    }
}

struct GlobalSearchTests {
    @Test func parsesWidgetNavigationURLsIntoSearchNavigationRequests() throws {
        let projectID = UUID()
        let milestoneID = UUID()
        let subTaskID = UUID()

        let projectRequest = try #require(
            WidgetNavigationURL.navigationRequest(
                from: #require(URL(string: "viabar://navigate/project/\(projectID.uuidString)"))
            )
        )
        #expect(projectRequest.projectID == projectID)
        #expect(projectRequest.destination == .project)

        let milestoneRequest = try #require(
            WidgetNavigationURL.navigationRequest(
                from: #require(URL(string: "viabar://navigate/milestone/\(projectID.uuidString)/\(milestoneID.uuidString)"))
            )
        )
        #expect(milestoneRequest.projectID == projectID)
        #expect(milestoneRequest.destination == .milestone(milestoneID))

        let subTaskRequest = try #require(
            WidgetNavigationURL.navigationRequest(
                from: #require(URL(string: "viabar://navigate/subtask/\(projectID.uuidString)/\(milestoneID.uuidString)/\(subTaskID.uuidString)"))
            )
        )
        #expect(subTaskRequest.projectID == projectID)
        #expect(subTaskRequest.destination == .subTask(milestoneID: milestoneID, subTaskID: subTaskID))
    }

    @Test func rejectsInvalidWidgetNavigationURLs() throws {
        let projectID = UUID()

        #expect(
            WidgetNavigationURL.navigationRequest(
                from: #require(URL(string: "https://navigate/project/\(projectID.uuidString)"))
            ) == nil
        )
        #expect(
            WidgetNavigationURL.navigationRequest(
                from: #require(URL(string: "viabar://navigate/subtask/\(projectID.uuidString)/missing"))
            ) == nil
        )
    }

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

struct TaskCompletionMutationTests {
    @Test func togglingParentTaskCompletesEveryChild() {
        let milestone = Milestone(title: "Release")
        let first = SubTask(title: "Package")
        let second = SubTask(title: "Publish")
        first.milestone = milestone
        second.milestone = milestone
        milestone.subtasks = [first, second]

        TaskCompletionMutation.toggle(milestone)

        #expect(milestone.isCompleted)
        #expect(milestone.completedAt != nil)
        #expect(milestone.subtasks.allSatisfy(\.isCompleted))
        #expect(milestone.subtasks.allSatisfy { $0.completedAt != nil })
    }

    @Test func togglingLastChildCompletesParentTask() {
        let milestone = Milestone(title: "Release")
        let first = SubTask(title: "Package", isCompleted: true)
        let second = SubTask(title: "Publish")
        first.milestone = milestone
        second.milestone = milestone
        milestone.subtasks = [first, second]

        TaskCompletionMutation.toggle(second)

        #expect(second.isCompleted)
        #expect(milestone.isCompleted)
        #expect(milestone.completedAt != nil)
    }
}

struct WidgetContentTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func activeProjectsExcludeArchivedProjectsAndPreserveOrder() {
        let second = Project(title: "Second", orderIndex: 1)
        let first = Project(title: "First", orderIndex: 0)
        let archived = Project(title: "Archived", orderIndex: 2)
        archived.isArchived = true

        #expect(
            WidgetContentBuilder.activeProjects(from: [second, archived, first]).map(\.title)
                == ["First", "Second"]
        )
    }

    @Test func flattensUnfinishedParentsAndChildrenWithoutParentSubtitle() {
        let project = Project(title: "Release")
        let milestone = Milestone(title: "Prepare", orderIndex: 0)
        milestone.markerColor = TaskMarkerColor.red.rawValue
        let child = SubTask(title: "Package", orderIndex: 0)
        child.markerColor = TaskMarkerColor.green.rawValue
        let done = SubTask(title: "Already done", orderIndex: 1, isCompleted: true)
        milestone.project = project
        child.milestone = milestone
        done.milestone = milestone
        milestone.subtasks = [done, child]
        project.milestones = [milestone]

        let items = WidgetContentBuilder.items(for: project, now: Date(), calendar: calendar)

        #expect(items.map(\.title) == ["Prepare", "Package"])
        #expect(items.map(\.kind) == [.milestone, .subTask])
        #expect(items.map(\.milestoneID) == [milestone.milestoneId, milestone.milestoneId])
        #expect(items.map(\.isIndented) == [false, true])
        #expect(items[0].markerColor == .red)
        #expect(items[1].markerColor == .green)
    }

    @Test func classifiesOverdueTodayPendingAndFutureReminders() {
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 31, hour: 12)
        )!

        #expect(
            WidgetReminderTone.resolve(
                fireDate: now.addingTimeInterval(-60),
                now: now,
                calendar: calendar
            ) == .overdue
        )
        #expect(
            WidgetReminderTone.resolve(
                fireDate: now.addingTimeInterval(60),
                now: now,
                calendar: calendar
            ) == .todayPending
        )
        #expect(
            WidgetReminderTone.resolve(
                fireDate: now.addingTimeInterval(86_400),
                now: now,
                calendar: calendar
            ) == .future
        )
        #expect(WidgetReminderTone.resolve(fireDate: nil, now: now, calendar: calendar) == nil)
    }

    @Test func truncatesByRowBudgetAndReportsHiddenCount() {
        let project = Project(title: "Release")
        project.milestones = (0..<5).map { Milestone(title: "Task \($0)", orderIndex: $0) }

        let content = WidgetContentBuilder.content(
            for: project,
            rowBudget: 3,
            now: Date(),
            calendar: calendar
        )

        #expect(content.visibleItems.map(\.title) == ["Task 0", "Task 1", "Task 2"])
        #expect(content.hiddenItemCount == 2)
    }

    @Test func largeWidgetAllowsTenPlainTaskRows() {
        let project = Project(title: "Release")
        project.milestones = (0..<12).map { Milestone(title: "Task \($0)", orderIndex: $0) }

        let content = WidgetContentBuilder.content(
            for: project,
            rowBudget: WidgetContentBuilder.largeWidgetRowBudget,
            now: Date(),
            calendar: calendar
        )

        #expect(content.visibleItems.count == 10)
        #expect(content.hiddenItemCount == 2)
    }

    @Test func mediumWidgetAllowsThreePlainTaskRows() {
        let project = Project(title: "Release")
        project.milestones = (0..<6).map { Milestone(title: "Task \($0)", orderIndex: $0) }

        let content = WidgetContentBuilder.content(
            for: project,
            rowBudget: WidgetContentBuilder.mediumWidgetRowBudget,
            now: Date(),
            calendar: calendar
        )

        #expect(content.visibleItems.count == 3)
        #expect(content.hiddenItemCount == 3)
    }

    @Test func reminderSubtitleConsumesASecondBudgetRow() {
        let now = Date()
        let project = Project(title: "Release")
        let reminded = Milestone(title: "Reminded", orderIndex: 0)
        reminded.reminder = Reminder(type: "single", fireTimestamp: now.addingTimeInterval(60))
        let plain = Milestone(title: "Plain", orderIndex: 1)
        project.milestones = [reminded, plain]

        let content = WidgetContentBuilder.content(
            for: project,
            rowBudget: 2,
            now: now,
            calendar: calendar
        )

        #expect(content.visibleItems.map(\.title) == ["Reminded"])
        #expect(content.hiddenItemCount == 1)
    }
}

struct SharedStoreMigratorTests {
    @Test func migratesLegacyStoreFilesBeforeOpeningSharedContainer() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let legacy = root.appending(path: "legacy/default.store")
        let shared = root.appending(path: "group/default.store")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("store".utf8).write(to: legacy)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))

        try SharedStoreMigrator.migrateStoreFilesIfNeeded(
            legacyStoreURL: legacy,
            sharedStoreURL: shared,
            validate: { candidate in
                #expect(FileManager.default.fileExists(atPath: candidate.path))
            }
        )

        #expect(FileManager.default.fileExists(atPath: shared.path))
        #expect(FileManager.default.fileExists(atPath: shared.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path + "-wal"))
        #expect(
            FileManager.default.fileExists(
                atPath: shared.deletingLastPathComponent()
                    .appending(path: SharedModelContainer.migrationMarkerFileName).path
            )
        )
    }

    @Test func failedValidationKeepsLegacyStoreAndDoesNotPublishSharedStore() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let legacy = root.appending(path: "legacy/default.store")
        let shared = root.appending(path: "group/default.store")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("store".utf8).write(to: legacy)

        #expect(throws: SharedStoreError.self) {
            try SharedStoreMigrator.migrateStoreFilesIfNeeded(
                legacyStoreURL: legacy,
                sharedStoreURL: shared,
                validate: { _ in throw SharedStoreError.sharedStoreUnavailable }
            )
        }
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: shared.path))
    }

    @Test func removesLegacyStoreFilesAfterSharedStoreIsAvailable() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let legacy = root.appending(path: "legacy/default.store")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("store".utf8).write(to: legacy)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: legacy.path + "-shm"))

        try SharedStoreMigrator.removeLegacyStoreFiles(
            at: legacy
        )

        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: legacy.path + "-shm"))
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
            TrashItem.self,
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
        #expect(WeekStartDay.defaultValue() == WeekStartDay.resolve(nil))
        #expect(settings.weekdayFilterEnabled == false)
        #expect(settings.dateFormat == AppDateFormat.yearMonthDaySlashes.rawValue)
        #expect(settings.toggleMainPanelShortcut == "Option+V")
        #expect(settings.openSearchShortcut == "Command+F")
        #expect(settings.syncEnabled == true)
        #expect(settings.lastSyncAt == nil)
        #expect(settings.backupEnabled == false)
        #expect(settings.backupPath == "")
        #expect(settings.backupBookmarkData == nil)
        #expect(TrashRetentionPolicy.defaultValue == .ninetyDays)
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

    @Test func resolvesWeekStartDefaultsFromRegionAndPreservesSavedValues() {
        let unitedStates = Locale(identifier: "en_US")
        let singapore = Locale(identifier: "en_SG")

        #expect(WeekStartDay.defaultValue(locale: unitedStates) == .sunday)
        #expect(WeekStartDay.defaultValue(locale: singapore) == .monday)
        #expect(WeekStartDay.resolve("monday", locale: unitedStates) == .monday)
        #expect(WeekStartDay.resolve("invalid", locale: unitedStates) == .sunday)
        #expect(WeekStartDay.resolve(nil, locale: singapore) == .monday)
    }

    @Test func weekStartSettingsStoreUsesRegionDefaultAndPersistsSelection() throws {
        let suiteName = "ViabarTests.WeekStart.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            WeekStartDaySettingsStore.value(
                defaults: defaults,
                locale: Locale(identifier: "en_US")
            ) == .sunday
        )
        WeekStartDaySettingsStore.set(.monday, defaults: defaults)
        #expect(
            WeekStartDaySettingsStore.value(
                defaults: defaults,
                locale: Locale(identifier: "en_US")
            ) == .monday
        )
    }

    @Test func trashRetentionSettingsStoreRepairsInvalidValues() throws {
        let suiteName = "ViabarTests.TrashRetention.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("invalid", forKey: "trashRetentionPolicy")

        #expect(TrashRetentionSettingsStore.policy(defaults: defaults) == .ninetyDays)
        defaults.set("forever", forKey: "trashRetentionPolicy")
        #expect(TrashRetentionSettingsStore.policy(defaults: defaults) == .ninetyDays)
        TrashRetentionSettingsStore.set(.sixtyDays, defaults: defaults)
        #expect(TrashRetentionSettingsStore.policy(defaults: defaults) == .sixtyDays)
    }

    @Test func formatsTrashDeletionTimesRelativeToToday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 13))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9, minute: 8))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 20, minute: 6))!
        let older = calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7, minute: 5))!

        #expect(AppDateFormatter.trashDeletionString(from: today, now: now, language: .english) == "09:08")
        #expect(AppDateFormatter.trashDeletionString(from: yesterday, now: now, language: .english) == "Yesterday 20:06")
        #expect(AppDateFormatter.trashDeletionString(from: older, now: now, language: .english) == "5/20 07:05")
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

struct MainWindowVisibilityPolicyTests {
    @Test func menuBarPanelPresentationKeepsPreviouslyVisibleMainWindowHidden() {
        var policy = MainWindowVisibilityPolicy()

        policy.applicationWillHide(mainWindowIsVisible: true)

        #expect(policy.consumeMenuBarPanelPresentationShouldHideMainWindow())
        #expect(!policy.consumeMenuBarPanelPresentationShouldHideMainWindow())
    }

    @Test func menuBarPanelPresentationDoesNotHideWindowWhenMainWindowWasAlreadyClosed() {
        var policy = MainWindowVisibilityPolicy()

        policy.applicationWillHide(mainWindowIsVisible: false)

        #expect(!policy.consumeMenuBarPanelPresentationShouldHideMainWindow())
    }

    @Test func explicitMainWindowPresentationCancelsPendingMenuBarSuppression() {
        var policy = MainWindowVisibilityPolicy()

        policy.applicationWillHide(mainWindowIsVisible: true)
        policy.cancelPendingMenuBarSuppression()

        #expect(!policy.consumeMenuBarPanelPresentationShouldHideMainWindow())
    }

    @Test func applicationUnhideRepeatsSuppressionWhenPanelAppearedFirst() {
        var policy = MainWindowVisibilityPolicy()

        policy.applicationWillHide(mainWindowIsVisible: true)
        #expect(policy.consumeMenuBarPanelPresentationShouldHideMainWindow())

        #expect(policy.applicationDidUnhideShouldHideMainWindow())
        #expect(!policy.applicationDidUnhideShouldHideMainWindow())
    }

    @Test func delayedCleanupFromEarlierUnhideDoesNotCancelNewHideCycle() {
        var policy = MainWindowVisibilityPolicy()

        policy.applicationWillHide(mainWindowIsVisible: true)
        let firstGeneration = policy.generation
        policy.applicationWillHide(mainWindowIsVisible: true)
        policy.cancelPendingMenuBarSuppression(ifGeneration: firstGeneration)

        #expect(policy.consumeMenuBarPanelPresentationShouldHideMainWindow())
    }
}

struct MenuBarContentTests {
    @Test func currentModeReturnsFirstUnfinishedSubtaskOnly() {
        let project = Project(title: "Release", orderIndex: 0)
        let milestone = Milestone(title: "Prepare", orderIndex: 0)
        let finished = SubTask(title: "Done", orderIndex: 0, isCompleted: true)
        let target = SubTask(title: "Review", orderIndex: 1)
        target.markerColor = TaskMarkerColor.yellow.rawValue
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
        #expect(cards[0].entries[0].markerColor == .yellow)
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

private extension Array where Element == OverviewReportSection {
    var thisWeek: OverviewReportSection {
        first { $0.kind == .weekDone }!
    }

    var nextWeek: OverviewReportSection {
        first { $0.kind == .weekTodo }!
    }

    var thisMonth: OverviewReportSection {
        first { $0.kind == .monthDone }!
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
        parent.markerColor = TaskMarkerColor.red.rawValue
        parent.project = project
        let screenshots = SubTask(title: "Screenshots", orderIndex: 0)
        screenshots.markerColor = TaskMarkerColor.green.rawValue
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
        #expect(report.nextWeek.cards[0].groups[0].markerColor == .red)
        #expect(report.nextWeek.cards[0].groups[0].subtasks[0].markerColor == .green)
        #expect(report.nextWeek.cards[0].groups[0].subtasks[1].markerColor == nil)
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

    @Test func weekStartChangesCompletionAndTodoBoundaries() {
        let project = Project(title: "Boundary")
        let completed = Milestone(title: "Sunday Done", isCompleted: true)
        completed.completedAt = calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 31, hour: 12)
        )
        completed.project = project
        let planned = Milestone(title: "Sunday Todo")
        planned.reminder = Reminder(
            type: "single",
            fireTimestamp: calendar.date(
                from: DateComponents(year: 2026, month: 5, day: 31, hour: 12)
            )
        )
        planned.project = project
        project.milestones = [completed, planned]

        let mondayNow = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)
        )!
        let sundayReport = OverviewReportBuilder.makeReport(
            projects: [project],
            scheduleEntries: [],
            now: mondayNow,
            calendar: calendar,
            weekStartDay: .sunday
        )
        let mondayReport = OverviewReportBuilder.makeReport(
            projects: [project],
            scheduleEntries: [],
            now: mondayNow,
            calendar: calendar,
            weekStartDay: .monday
        )
        let sundayWeekDone = sundayReport.first { $0.kind == .weekDone }!
        let mondayWeekDone = mondayReport.first { $0.kind == .weekDone }!
        let sundayTodo = sundayReport.first { $0.kind == .weekTodo }!
        let mondayTodo = mondayReport.first { $0.kind == .weekTodo }!

        #expect(sundayWeekDone.cards[0].groups.map(\.title) == ["Sunday Done"])
        #expect(mondayWeekDone.cards.isEmpty)
        #expect(sundayTodo.cards[0].groups.map(\.title) == ["Sunday Todo"])
        #expect(mondayTodo.cards[0].groups.map(\.title) == ["Sunday Todo"])
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
        var settings = BackupSettingsSnapshot(backupEnabled: true, backupPath: "~/Documents/Viabar")
        settings.weekStartDay = WeekStartDay.sunday.rawValue
        let snapshot = BackupSnapshot(
            formatVersion: BackupSnapshot.currentFormatVersion,
            createdAt: Date(timeIntervalSince1970: 0),
            settings: settings,
            folders: [],
            projects: [],
            templates: []
        )

        let encoded = try JSONEncoder.backupEncoder.encode(snapshot)

        #expect(try JSONDecoder.backupDecoder.decode(BackupSnapshot.self, from: encoded) == snapshot)
    }

    @Test func decodesLegacyBackupWithoutWeekStart() throws {
        let json = """
        {
          "settingsId": "shared",
          "createdAt": "1970-01-01T00:00:00Z",
          "launchAtLogin": false,
          "menuBarComponentEnabled": false,
          "menuBarIcon": "bookmark.fill",
          "menuBarProjectScope": "allProjects",
          "menuBarContentMode": "currentTask",
          "theme": "system",
          "language": "system",
          "overviewScope": "allProjects",
          "weekdayFilterEnabled": false,
          "dateFormat": "yyyy/MM/dd HH:mm",
          "toggleMainPanelShortcut": "Option+V",
          "openSearchShortcut": "Command+F",
          "syncEnabled": true,
          "backupEnabled": false,
          "backupPath": "",
          "automaticallyChecksForUpdates": true
        }
        """

        let snapshot = try JSONDecoder.backupDecoder.decode(
            BackupSettingsSnapshot.self,
            from: Data(json.utf8)
        )

        #expect(snapshot.weekStartDay == nil)
    }

    @Test func decodesLegacyBackupTasksWithoutMarkerColorAsNone() throws {
        let json = """
        {
          "milestoneId": "00000000-0000-0000-0000-000000000001",
          "title": "Legacy Task",
          "isCompleted": false,
          "completedAt": null,
          "orderIndex": 0,
          "reminder": null,
          "subtasks": [
            {
              "taskId": "00000000-0000-0000-0000-000000000002",
              "title": "Legacy Subtask",
              "isCompleted": false,
              "completedAt": null,
              "orderIndex": 0,
              "reminder": null
            }
          ]
        }
        """

        let snapshot = try JSONDecoder.backupDecoder.decode(
            BackupMilestoneSnapshot.self,
            from: Data(json.utf8)
        )

        #expect(snapshot.markerColor == nil)
        #expect(snapshot.subtasks[0].markerColor == nil)
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
        let trashSchema = Schema([TrashItem.self])
        let trashContainer = try ModelContainer(
            for: trashSchema,
            configurations: [ModelConfiguration(schema: trashSchema, isStoredInMemoryOnly: true)]
        )
        let trashContext = trashContainer.mainContext
        let schedule = NotificationScheduleService(modelContext: context, notificationPoster: { _, _ in })
        let trashService = TrashService(
            modelContext: trashContext,
            projectModelContext: context,
            notificationScheduleService: schedule
        )
        let service = BackupService(
            modelContext: context,
            notificationScheduleService: schedule,
            trashService: trashService
        )
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
        #expect(WeekStartDaySettingsStore.value() == WeekStartDay.defaultValue())
    }

    @Test func restoreRecreatesRecentTrashAndDropsExpiredTrash() throws {
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
        let trashSchema = Schema([TrashItem.self])
        let trashContainer = try ModelContainer(
            for: trashSchema,
            configurations: [ModelConfiguration(schema: trashSchema, isStoredInMemoryOnly: true)]
        )
        let trashContext = trashContainer.mainContext
        let schedule = NotificationScheduleService(modelContext: context, notificationPoster: { _, _ in })
        let trashService = TrashService(
            modelContext: trashContext,
            projectModelContext: context,
            notificationScheduleService: schedule
        )
        let service = BackupService(
            modelContext: context,
            notificationScheduleService: schedule,
            trashService: trashService
        )
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let recent = try TrashItem.fixture(deletedAt: now.addingTimeInterval(-10 * 86_400))
        let expired = try TrashItem.fixture(deletedAt: now.addingTimeInterval(-100 * 86_400))
        var settings = BackupSettingsSnapshot(backupEnabled: false, backupPath: "")
        settings.trashRetentionPolicy = TrashRetentionPolicy.ninetyDays.rawValue
        let snapshot = BackupSnapshot(
            formatVersion: BackupSnapshot.currentFormatVersion,
            createdAt: now,
            settings: settings,
            folders: [],
            projects: [],
            templates: [],
            trashItems: [backupTrashSnapshot(recent), backupTrashSnapshot(expired)]
        )

        try service.restore(snapshot: snapshot, now: now)

        #expect(try trashContext.fetch(FetchDescriptor<TrashItem>()).map(\.trashItemId) == [recent.trashItemId])
        #expect(try context.fetch(FetchDescriptor<NotificationScheduleEntry>()).isEmpty)
    }

    private func backupTrashSnapshot(_ item: TrashItem) -> BackupTrashItemSnapshot {
        BackupTrashItemSnapshot(
            trashItemId: item.trashItemId,
            kind: item.kind,
            deletedAt: item.deletedAt,
            originalProjectId: item.originalProjectId,
            originalProjectTitle: item.originalProjectTitle,
            originalProjectAccentColor: item.originalProjectAccentColor,
            originalProjectSymbolName: item.originalProjectSymbolName,
            originalParentTaskId: item.originalParentTaskId,
            originalParentTaskTitle: item.originalParentTaskTitle,
            originalOrderIndex: item.originalOrderIndex,
            payloadVersion: item.payloadVersion,
            payloadData: item.payloadData
        )
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

    @Test func updatingDisplayPreferencesDoesNotProcessOverdueProjectEntries() throws {
        var deliveredCount = 0
        let (service, _, context) = try makeServices { _, _ in
            deliveredCount += 1
        }
        let project = service.createProject(title: "Release")
        _ = service.addMilestone(to: project, title: "Review")
        let overdueDate = Date().addingTimeInterval(-60)
        project.reminder = Reminder(type: "single", fireTimestamp: overdueDate)
        context.insert(NotificationScheduleEntry(
            ownerId: project.projectId,
            ownerKind: "project",
            projectId: project.projectId,
            projectTitle: project.title,
            body: "Next: Review",
            fireDate: overdueDate
        ))
        try context.save()

        project.hideCompleted.toggle()
        service.updateProjectDisplayPreferences(project)

        #expect(deliveredCount == 0)
        #expect(fetchEntries(in: context).count == 1)
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
            TrashItem.self,
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
