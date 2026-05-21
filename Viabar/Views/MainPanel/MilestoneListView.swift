import SwiftUI
import SwiftData

// MARK: - MilestoneListView

/// 左栏：垂直时间线流，两级结构（里程碑 → 核心子任务）。
/// 顶部常驻切换开关：显示/隐藏已完成。
struct MilestoneListView: View {
    let project: Project
    var showsHeader: Bool = true

    @Environment(ServiceContainer.self) private var container
    @State private var newMilestoneTitle: String = ""
    @State private var expandingSubtaskFor: UUID?
    @State private var selectedMilestoneID: UUID?
    @State private var selectedSubTaskID: UUID?

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
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if showsHeader {
                    header
                    Divider()
                }
                if visibleMilestones.isEmpty {
                    emptyContent
                } else {
                    milestoneList
                }
            }

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
                        isSelected: selectedMilestoneID == milestone.milestoneId,
                        hidesCompleted: project.hideCompleted,
                        isExpandingSubtask: Binding(
                            get: { expandingSubtaskFor == milestone.milestoneId },
                            set: {
                                expandingSubtaskFor = $0 ? milestone.milestoneId : nil
                            }
                        ),
                        selectedSubTaskID: $selectedSubTaskID,
                        onSelect: {
                            selectedMilestoneID = milestone.milestoneId
                            selectedSubTaskID = nil
                        },
                        onSelectSubTask: { subTaskID in
                            selectedMilestoneID = nil
                            selectedSubTaskID = subTaskID
                        }
                    )
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 96)
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
        .padding(.bottom, 96)
    }

    // MARK: - Add Milestone Bar

    private var addMilestoneBar: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                TextField("", text: $newMilestoneTitle, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3)
                    .submitLabel(.done)
                    .onSubmit { commitNewMilestone() }
                    .padding(.leading, 12)
                    .padding(.trailing, 40)
                    .padding(.vertical, 10)
                    .frame(minHeight: 68, maxHeight: 68, alignment: .topLeading)

                Button(action: commitNewMilestone) {
                    Image(systemName: "paperplane.fill")
                        .font(.callout)
                        .foregroundStyle(hasMilestoneDraft ? MilestoneListStyle.sendButtonActive : MilestoneListStyle.sendButtonInactive)
                }
                .buttonStyle(.plain)
                .disabled(!hasMilestoneDraft)
                .help("添加里程碑")
                .padding(.trailing, 12)
                .padding(.bottom, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0),
                    Color(nsColor: .windowBackgroundColor).opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func commitNewMilestone() {
        let title = newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        projectService?.addMilestone(to: project, title: title)
        newMilestoneTitle = ""
    }

    private var hasMilestoneDraft: Bool {
        !newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - MilestoneRowView

struct MilestoneRowView: View {
    let milestone: Milestone
    let isSelected: Bool
    let hidesCompleted: Bool
    @Binding var isExpandingSubtask: Bool
    @Binding var selectedSubTaskID: UUID?
    let onSelect: () -> Void
    let onSelectSubTask: (UUID) -> Void

    @Environment(ServiceContainer.self) private var container
    @State private var newSubTaskTitle: String = ""
    @State private var editingTitle = false
    @State private var titleDraft: String = ""
    @State private var showingReminderPopover = false
    @State private var isHovering = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNewSubTaskFocused: Bool

    private var projectService: ProjectService? {
        container.projectService
    }

    /// 已完成的 subtask 数量
    private var completedSubTaskCount: Int {
        milestone.subtasks.filter(\.isCompleted).count
    }

    private var visibleSubtasks: [SubTask] {
        let sorted = milestone.subtasks.sorted { $0.orderIndex < $1.orderIndex }
        guard hidesCompleted else { return sorted }
        return sorted.filter { !$0.isCompleted }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                projectService?.toggleMilestoneComplete(milestone)
            } label: {
                Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(milestone.isCompleted ? ViabarColor.success : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(spacing: 0) {
                milestoneContentRow

                if !milestone.subtasks.isEmpty || isExpandingSubtask {
                    subtaskList
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .onChange(of: isExpandingSubtask) { _, expanded in
            if expanded {
                isNewSubTaskFocused = true
            } else {
                newSubTaskTitle = ""
                isNewSubTaskFocused = false
            }
        }
        .onHover { isHovering = $0 }
    }

    private var milestoneContentRow: some View {
        HStack(alignment: .top, spacing: 10) {
            editableTitle

            milestoneTrailingControls
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            startEditing()
        }
        .contextMenu {
            Button {
                onSelect()
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpandingSubtask = true
                }
            } label: {
                Label("新子任务", systemImage: "list.bullet.below.rectangle")
            }
            Button {
                onSelect()
                startEditing()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                projectService?.deleteMilestone(milestone)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var milestoneTrailingControls: some View {
        HStack(alignment: .top, spacing: 10) {
            if !milestone.subtasks.isEmpty {
                Text("\(completedSubTaskCount)/\(milestone.subtasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .fixedSize(horizontal: true, vertical: true)
            }

            if isSelected {
                Button {
                    onSelect()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpandingSubtask.toggle()
                    }
                } label: {
                    Image(systemName: "list.bullet.below.rectangle")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("添加子任务")
                .fixedSize()
            }

            if isSelected || milestone.reminder != nil {
                Button {
                    onSelect()
                    showingReminderPopover.toggle()
                } label: {
                    Image(systemName: milestone.reminder == nil ? "alarm" : "alarm.fill")
                        .foregroundStyle(milestone.reminder == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("设置提醒")
                .popover(isPresented: $showingReminderPopover, arrowEdge: .trailing) {
                    ReminderSettingsPopover(reminder: Binding(
                        get: { milestone.reminder },
                        set: {
                            milestone.reminder = $0
                            projectService?.save()
                        }
                    ))
                }
                .fixedSize()
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private var subtaskList: some View {
        VStack(spacing: 0) {
            ForEach(
                visibleSubtasks,
                id: \.taskId
            ) { subtask in
                SubTaskRowView(
                    subTask: subtask,
                    isSelected: selectedSubTaskID == subtask.taskId,
                    onNewSubtask: {
                        onSelect()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpandingSubtask = true
                        }
                    },
                    onSelect: {
                        onSelectSubTask(subtask.taskId)
                    }
                )
            }

            if isExpandingSubtask {
                HStack(spacing: 8) {
                    Image(systemName: "circle.dotted")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    TextField("新子任务…", text: $newSubTaskTitle)
                        .textFieldStyle(.plain)
                        .focused($isNewSubTaskFocused)
                        .onSubmit { commitNewSubTask() }
                        .onAppear { isNewSubTaskFocused = true }
                        .onChange(of: isNewSubTaskFocused) { _, focused in
                            guard !focused else { return }
                            commitOrCloseSubTaskComposer()
                        }

                    Button(action: commitNewSubTask) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(newSubTaskTitle.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(newSubTaskTitle.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .padding(.top, 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func commitNewSubTask() {
        let title = newSubTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        projectService?.addSubTask(to: milestone, title: title)
        newSubTaskTitle = ""
        withAnimation(.easeInOut(duration: 0.15)) {
            isExpandingSubtask = false
        }
    }

    private func commitOrCloseSubTaskComposer() {
        let title = newSubTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            projectService?.addSubTask(to: milestone, title: title)
            newSubTaskTitle = ""
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            isExpandingSubtask = false
        }
    }

    private var editableTitle: some View {
        Group {
            if editingTitle {
                TextField("里程碑", text: $titleDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(nil)
                    .font(.body)
                    .focused($isTitleFocused)
                    .onSubmit { commitTitleEdit() }
                    .onAppear { isTitleFocused = true }
                    .onChange(of: isTitleFocused) { _, focused in
                        guard !focused else { return }
                        commitTitleEdit()
                    }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(milestone.title)
                        .font(.body)
                        .strikethrough(milestone.isCompleted)
                        .foregroundStyle(milestone.isCompleted ? .secondary : .primary)

                    if isHovering, milestone.isCompleted, let completedAt = milestone.completedAt {
                        Text("（\(formatCompletionTimestamp(completedAt))）")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                }
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }

    private func startEditing() {
        titleDraft = milestone.title
        editingTitle = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            milestone.title = title
            projectService?.save()
        }
        editingTitle = false
    }

}

// MARK: - SubTaskRowView

struct SubTaskRowView: View {
    let subTask: SubTask
    let isSelected: Bool
    let onNewSubtask: () -> Void
    let onSelect: () -> Void

    @Environment(ServiceContainer.self) private var container
    @State private var editingTitle = false
    @State private var titleDraft: String = ""
    @State private var showingReminderPopover = false
    @State private var isHovering = false
    @FocusState private var isTitleFocused: Bool

    private var projectService: ProjectService? {
        container.projectService
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                projectService?.toggleSubTaskComplete(subTask)
            } label: {
                Image(systemName: subTask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subTask.isCompleted ? ViabarColor.success : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            editableTitle

            if isSelected || subTask.reminder != nil {
                Button {
                    onSelect()
                    showingReminderPopover.toggle()
                } label: {
                    Image(systemName: subTask.reminder == nil ? "alarm" : "alarm.fill")
                        .font(.callout)
                        .foregroundStyle(subTask.reminder == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }
                .buttonStyle(.plain)
                .help("设置提醒")
                .popover(isPresented: $showingReminderPopover, arrowEdge: .trailing) {
                    ReminderSettingsPopover(reminder: Binding(
                        get: { subTask.reminder },
                        set: {
                            subTask.reminder = $0
                            projectService?.save()
                        }
                    ))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            startEditing()
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button {
                onSelect()
                onNewSubtask()
            } label: {
                Label("新子任务", systemImage: "list.bullet.below.rectangle")
            }
            Button {
                onSelect()
                startEditing()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                projectService?.deleteSubTask(subTask)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var editableTitle: some View {
        Group {
            if editingTitle {
                TextField("子任务", text: $titleDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(nil)
                    .font(.callout)
                    .focused($isTitleFocused)
                    .onSubmit { commitTitleEdit() }
                    .onAppear { isTitleFocused = true }
                    .onChange(of: isTitleFocused) { _, focused in
                        guard !focused else { return }
                        commitTitleEdit()
                    }
            } else {
                Text(subTaskDisplayTitle)
                    .font(.callout)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .strikethrough(subTask.isCompleted)
                    .foregroundStyle(subTask.isCompleted ? .secondary : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private func startEditing() {
        titleDraft = subTask.title
        editingTitle = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            subTask.title = title
            projectService?.save()
        }
        editingTitle = false
    }

    private var subTaskDisplayTitle: String {
        guard isHovering, subTask.isCompleted, let completedAt = subTask.completedAt else {
            return subTask.title
        }
        return "\(subTask.title)（\(formatCompletionTimestamp(completedAt))）"
    }
}

private enum MilestoneListStyle {
    static let sendButtonActive = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedRed: 0.46, green: 0.72, blue: 1.0, alpha: 1)
            : NSColor(calibratedRed: 0.32, green: 0.68, blue: 1.0, alpha: 1)
    })
    static let sendButtonInactive = Color(nsColor: .tertiaryLabelColor)
}

private func formatCompletionTimestamp(_ date: Date) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()

    if calendar.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    if calendar.isDateInYesterday(date) {
        formatter.dateFormat = "HH:mm"
        return "昨天 \(formatter.string(from: date))"
    }

    if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
        formatter.dateFormat = "M/d HH:mm"
    } else {
        formatter.dateFormat = "yyyy/M/d HH:mm"
    }

    return formatter.string(from: date)
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
