import Testing
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
