import SwiftUI
import SwiftData

// MARK: - MilestoneListView

/// 左栏：垂直时间线流，两级结构（里程碑 → 核心子任务）。
/// 顶部常驻切换开关：显示/隐藏已完成。
struct MilestoneListView: View {
    let project: Project

    @Environment(ServiceContainer.self) private var container
    @State private var newMilestoneTitle: String = ""
    @State private var expandingSubtaskFor: UUID?

    private var projectService: ProjectService? {
        container.projectService
    }

    // MARK: - Filtered Milestones

    private var visibleMilestones: [Milestone] {
        let sorted = project.milestones.sorted { $0.orderIndex < $1.orderIndex }
        guard project.hideCompleted else { return sorted }
        return sorted.filter { m in
            !m.isCompleted || m.subtasks.contains(where: { !$0.isCompleted })
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visibleMilestones.isEmpty {
                emptyContent
            } else {
                milestoneList
            }
            Divider()
            addMilestoneBar
        }
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("里程碑", systemImage: "list.bullet.rectangle")
                .font(.headline)

            Spacer()

            Toggle(isOn: Binding(
                get: { project.hideCompleted },
                set: { project.hideCompleted = $0; projectService?.updateProject(project) }
            )) {
                Text("隐藏已完成")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Milestone List

    private var milestoneList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(visibleMilestones) { milestone in
                    MilestoneRowView(
                        milestone: milestone,
                        isExpandingSubtask: Binding(
                            get: { expandingSubtaskFor == milestone.milestoneId },
                            set: {
                                expandingSubtaskFor = $0 ? milestone.milestoneId : nil
                            }
                        )
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .scrollClipDisabled(false)
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "flag.slash")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("暂无里程碑")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text("在下方输入框中添加第一个里程碑")
                .font(.caption)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Add Milestone Bar

    private var addMilestoneBar: some View {
        HStack(spacing: 8) {
            TextField("新增里程碑…", text: $newMilestoneTitle)
                .textFieldStyle(.plain)
                .onSubmit { commitNewMilestone() }

            Button(action: commitNewMilestone) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(newMilestoneTitle.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.blue))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(newMilestoneTitle.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func commitNewMilestone() {
        guard !newMilestoneTitle.isEmpty else { return }
        projectService?.addMilestone(to: project, title: newMilestoneTitle)
        newMilestoneTitle = ""
    }
}

// MARK: - MilestoneRowView

struct MilestoneRowView: View {
    let milestone: Milestone
    @Binding var isExpandingSubtask: Bool

    @Environment(ServiceContainer.self) private var container
    @State private var newSubTaskTitle: String = ""

    private var projectService: ProjectService? {
        container.projectService
    }

    /// 已完成的 subtask 数量
    private var completedSubTaskCount: Int {
        milestone.subtasks.filter(\.isCompleted).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // 里程碑主行
            HStack(spacing: 10) {
                // 完成状态按钮
                Button {
                    projectService?.toggleMilestoneComplete(milestone)
                } label: {
                    Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(milestone.isCompleted ? ViabarColor.success : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)

                // 标题
                Text(milestone.title)
                    .font(.body)
                    .strikethrough(milestone.isCompleted)
                    .foregroundStyle(milestone.isCompleted ? .secondary : .primary)

                Spacer()

                // 子任务计数
                if !milestone.subtasks.isEmpty {
                    Text("\(completedSubTaskCount)/\(milestone.subtasks.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 展开添加子任务
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpandingSubtask.toggle()
                    }
                } label: {
                    Image(systemName: isExpandingSubtask ? "plus.circle.fill" : "plus.circle")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("添加子任务")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            // 子任务列表
            if !milestone.subtasks.isEmpty || isExpandingSubtask {
                VStack(spacing: 0) {
                    ForEach(
                        milestone.subtasks.sorted { $0.orderIndex < $1.orderIndex }
                    ) { subtask in
                        SubTaskRowView(subTask: subtask)
                    }

                    // 添加子任务输入框
                    if isExpandingSubtask {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.dotted")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            TextField("新子任务…", text: $newSubTaskTitle)
                                .textFieldStyle(.plain)
                                .onSubmit { commitNewSubTask() }

                            Button(action: commitNewSubTask) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(newSubTaskTitle.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.blue))
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .disabled(newSubTaskTitle.isEmpty)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    private func commitNewSubTask() {
        guard !newSubTaskTitle.isEmpty else { return }
        projectService?.addSubTask(to: milestone, title: newSubTaskTitle)
        newSubTaskTitle = ""
    }
}

// MARK: - SubTaskRowView

struct SubTaskRowView: View {
    let subTask: SubTask

    @Environment(ServiceContainer.self) private var container

    private var projectService: ProjectService? {
        container.projectService
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                projectService?.toggleSubTaskComplete(subTask)
            } label: {
                Image(systemName: subTask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subTask.isCompleted ? ViabarColor.success : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Text(subTask.title)
                .font(.callout)
                .strikethrough(subTask.isCompleted)
                .foregroundStyle(subTask.isCompleted ? .secondary : .primary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("删除") {
                projectService?.deleteSubTask(subTask)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let project = Project(title: "示例项目")
    let m1 = Milestone(title: "需求分析", orderIndex: 0)
    let m2 = Milestone(title: "UI 设计", orderIndex: 1, isCompleted: true)
    let m3 = Milestone(title: "开发实现", orderIndex: 2)
    m3.subtasks = [
        SubTask(title: "数据层", orderIndex: 0, isCompleted: true),
        SubTask(title: "网络层", orderIndex: 1, isCompleted: true),
        SubTask(title: "UI 层", orderIndex: 2),
    ]
    project.milestones = [m1, m2, m3]

    return MilestoneListView(project: project)
        .frame(width: 400, height: 500)
        .environment(ServiceContainer())
}
