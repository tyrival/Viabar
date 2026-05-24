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
