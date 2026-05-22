import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

private let usesMilestoneListSafeMode = true
private let reminderColumnWidth: CGFloat = 28
private let reminderInfoColumnWidth: CGFloat = 210
private let subTaskLeadingIndent: CGFloat = 38
private let milestoneRowOuterVerticalPadding: CGFloat = 4

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
    @State private var scrollToBottomTrigger = 0

    private var projectService: ProjectService? {
        container.projectService
    }

    private var notificationScheduleService: NotificationScheduleService? {
        container.notificationScheduleService
    }

    // MARK: - Filtered Milestones

    private var visibleMilestones: [Milestone] {
        let sorted = project.milestones.sorted { $0.orderIndex < $1.orderIndex }
        guard project.hideCompleted else { return sorted }
        return sorted.filter { m in
            !m.isCompleted || m.subtasks.contains(where: { !$0.isCompleted })
        }
    }

    private var milestoneSnapshots: [MilestoneSnapshot] {
        visibleMilestones.map { milestone in
            let sortedSubtasks = milestone.subtasks.sorted { $0.orderIndex < $1.orderIndex }
            let visibleSubtasks = project.hideCompleted
                ? sortedSubtasks.filter { !$0.isCompleted }
                : sortedSubtasks

            return MilestoneSnapshot(
                id: milestone.milestoneId,
                title: milestone.title,
                isCompleted: milestone.isCompleted,
                hasReminder: milestone.reminder != nil,
                subtasks: visibleSubtasks.map {
                    SubTaskSnapshot(
                        id: $0.taskId,
                        title: $0.title,
                        isCompleted: $0.isCompleted,
                        hasReminder: $0.reminder != nil
                    )
                }
            )
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
                if milestoneSnapshots.isEmpty {
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

    @ViewBuilder
    private var milestoneList: some View {
        if usesMilestoneListSafeMode {
            SafeMilestoneListView(
                snapshots: milestoneSnapshots,
                onToggleMilestone: toggleMilestone(id:),
                onUpdateMilestoneTitle: updateMilestoneTitle(id:title:),
                onDeleteMilestone: deleteMilestone(id:),
                onMilestoneReminderChange: syncMilestoneReminder(id:reminder:),
                reminderBinding: milestoneReminderBinding(id:),
                onAddSubTask: addSubTask(milestoneID:title:),
                onToggleSubTask: toggleSubTask(id:),
                onUpdateSubTaskTitle: updateSubTaskTitle(id:title:),
                onDeleteSubTask: deleteSubTask(id:),
                onSubTaskReminderChange: syncSubTaskReminder(id:reminder:),
                scrollToBottomTrigger: scrollToBottomTrigger,
                onMoveMilestone: moveMilestone(id:targetID:placement:),
                onMoveSubTask: moveSubTask(id:targetMilestoneID:targetSubTaskID:placement:),
                subTaskReminderBinding: subTaskReminderBinding(id:)
            )
        } else {
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
        scrollToBottomTrigger += 1
    }

    private func toggleMilestone(id: UUID) {
        guard let milestone = project.milestones.first(where: { $0.milestoneId == id }) else { return }
        projectService?.toggleMilestoneComplete(milestone)
        syncMilestoneAndSubTaskReminders(milestone)
    }

    private func toggleSubTask(id: UUID) {
        for milestone in project.milestones {
            if let subtask = milestone.subtasks.first(where: { $0.taskId == id }) {
                projectService?.toggleSubTaskComplete(subtask)
                syncSubTaskReminder(subtask, project: project)
                syncMilestoneReminder(milestone, project: project)
                return
            }
        }
    }

    private func updateMilestoneTitle(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let milestone = project.milestones.first(where: { $0.milestoneId == id })
        else { return }

        milestone.title = trimmed
        projectService?.save()
        syncMilestoneReminder(milestone, project: project)
    }

    private func updateSubTaskTitle(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        for milestone in project.milestones {
            if let subtask = milestone.subtasks.first(where: { $0.taskId == id }) {
                subtask.title = trimmed
                projectService?.save()
                syncSubTaskReminder(subtask, project: project)
                return
            }
        }
    }

    private func deleteMilestone(id: UUID) {
        guard let milestone = project.milestones.first(where: { $0.milestoneId == id }) else { return }
        notificationScheduleService?.removeEntry(ownerId: milestone.milestoneId)
        milestone.subtasks.forEach { notificationScheduleService?.removeEntry(ownerId: $0.taskId) }
        projectService?.deleteMilestone(milestone)
    }

    private func deleteSubTask(id: UUID) {
        for milestone in project.milestones {
            if let subtask = milestone.subtasks.first(where: { $0.taskId == id }) {
                notificationScheduleService?.removeEntry(ownerId: subtask.taskId)
                projectService?.deleteSubTask(subtask)
                syncMilestoneReminder(milestone, project: project)
                return
            }
        }
    }

    private func moveMilestone(id: UUID, targetID: UUID?, placement: ReorderPlacement) {
        projectService?.reorderMilestones(in: project, movingID: id, targetID: targetID, placement: placement)
    }

    private func moveSubTask(id: UUID, targetMilestoneID: UUID, targetSubTaskID: UUID?, placement: ReorderPlacement) {
        projectService?.moveSubTask(id, to: targetMilestoneID, targetSubTaskID: targetSubTaskID, placement: placement)
    }

    @discardableResult
    private func addSubTask(milestoneID: UUID, title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let milestone = project.milestones.first(where: { $0.milestoneId == milestoneID })
        else { return false }

        projectService?.addSubTask(to: milestone, title: trimmed)
        return true
    }

    private func milestoneReminderBinding(id: UUID) -> Binding<Reminder?> {
        Binding(
            get: {
                project.milestones.first(where: { $0.milestoneId == id })?.reminder
            },
            set: { reminder in
                guard let milestone = project.milestones.first(where: { $0.milestoneId == id }) else { return }
                milestone.reminder = reminder
                projectService?.save()
                syncMilestoneReminder(milestone, project: project)
            }
        )
    }

    private func subTaskReminderBinding(id: UUID) -> Binding<Reminder?> {
        Binding(
            get: {
                for milestone in project.milestones {
                    if let subtask = milestone.subtasks.first(where: { $0.taskId == id }) {
                        return subtask.reminder
                    }
                }
                return nil
            },
            set: { reminder in
                for milestone in project.milestones {
                    if let subtask = milestone.subtasks.first(where: { $0.taskId == id }) {
                        subtask.reminder = reminder
                        projectService?.save()
                        syncSubTaskReminder(subtask, project: project)
                        return
                    }
                }
            }
        )
    }

    private var hasMilestoneDraft: Bool {
        !newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func syncMilestoneReminder(id: UUID, reminder: Reminder?) {
        guard let milestone = project.milestones.first(where: { $0.milestoneId == id }) else { return }
        if reminder == nil {
            notificationScheduleService?.removeEntry(ownerId: id)
        } else {
            syncMilestoneReminder(milestone, project: project)
        }
    }

    private func syncSubTaskReminder(id: UUID, reminder: Reminder?) {
        for milestone in project.milestones {
            if let subtask = milestone.subtasks.first(where: { $0.taskId == id }) {
                if reminder == nil {
                    notificationScheduleService?.removeEntry(ownerId: id)
                } else {
                    syncSubTaskReminder(subtask, project: project)
                }
                return
            }
        }
    }

    private func syncMilestoneAndSubTaskReminders(_ milestone: Milestone) {
        syncMilestoneReminder(milestone, project: project)
        milestone.subtasks.forEach { syncSubTaskReminder($0, project: project) }
    }

    private func syncMilestoneReminder(_ milestone: Milestone, project: Project) {
        notificationScheduleService?.syncMilestone(milestone, project: project)
    }

    private func syncSubTaskReminder(_ subtask: SubTask, project: Project) {
        notificationScheduleService?.syncSubTask(subtask, project: project)
    }
}

// MARK: - SafeMilestoneListView

private struct MilestoneSnapshot: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let hasReminder: Bool
    let subtasks: [SubTaskSnapshot]
}

private struct SubTaskSnapshot: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let hasReminder: Bool
}

private struct SafeMilestoneListView: View {
    let snapshots: [MilestoneSnapshot]
    let onToggleMilestone: (UUID) -> Void
    let onUpdateMilestoneTitle: (UUID, String) -> Void
    let onDeleteMilestone: (UUID) -> Void
    let onMilestoneReminderChange: (UUID, Reminder?) -> Void
    let reminderBinding: (UUID) -> Binding<Reminder?>
    let onAddSubTask: (UUID, String) -> Bool
    let onToggleSubTask: (UUID) -> Void
    let onUpdateSubTaskTitle: (UUID, String) -> Void
    let onDeleteSubTask: (UUID) -> Void
    let onSubTaskReminderChange: (UUID, Reminder?) -> Void
    let scrollToBottomTrigger: Int
    let onMoveMilestone: (UUID, UUID?, ReorderPlacement) -> Void
    let onMoveSubTask: (UUID, UUID, UUID?, ReorderPlacement) -> Void
    let subTaskReminderBinding: (UUID) -> Binding<Reminder?>

    @State private var addingSubTaskFor: UUID?
    @State private var draggingItem: TaskDragItem?
    @State private var dropTarget: TaskDropTarget?
    private let bottomAnchorID = "milestone-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(snapshots) { snapshot in
                    SafeMilestoneRowView(
                        snapshot: snapshot,
                        onToggleMilestone: onToggleMilestone,
                        onUpdateMilestoneTitle: onUpdateMilestoneTitle,
                        onDeleteMilestone: onDeleteMilestone,
                        reminder: reminderBinding(snapshot.id),
                        onReminderChange: { reminder in
                            onMilestoneReminderChange(snapshot.id, reminder)
                        },
                        onBeginAddSubTask: {
                            addingSubTaskFor = snapshot.id
                        },
                        draggingItem: $draggingItem,
                        dropTarget: $dropTarget,
                        onPerformDrop: performDrop(_:target:)
                    )
                    .safeListRow()

                    ForEach(snapshot.subtasks) { subtask in
                        SafeSubTaskRowView(
                            subtask: subtask,
                            parentID: snapshot.id,
                            leadingIndent: subTaskLeadingIndent,
                            reminder: subTaskReminderBinding(subtask.id),
                            onToggle: onToggleSubTask,
                            onUpdateTitle: onUpdateSubTaskTitle,
                            onDelete: onDeleteSubTask,
                            onReminderChange: { reminder in
                                onSubTaskReminderChange(subtask.id, reminder)
                            },
                            draggingItem: $draggingItem,
                            dropTarget: $dropTarget,
                            onPerformDrop: performDrop(_:target:)
                        )
                        .safeListRow()
                    }

                    if addingSubTaskFor == snapshot.id {
                        SafeSubTaskComposerView(
                            milestoneID: snapshot.id,
                            leadingIndent: subTaskLeadingIndent,
                            onAddSubTask: onAddSubTask,
                            onClose: {
                                addingSubTaskFor = nil
                            }
                        )
                        .safeListRow()
                    }
                }

                Color.clear
                    .frame(height: 96)
                    .id(bottomAnchorID)
                    .onDrop(
                        of: [.plainText],
                        delegate: TaskEndDropDelegate(
                            draggingItem: $draggingItem,
                            dropTarget: $dropTarget,
                            onMoveMilestone: onMoveMilestone
                        )
                    )
                    .safeListRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tint(Color(nsColor: .tertiaryLabelColor))
            .accentColor(Color(nsColor: .tertiaryLabelColor))
            .onChange(of: scrollToBottomTrigger) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func performDrop(_ item: TaskDragItem, target: TaskDropTarget) {
        switch (item, target) {
        case let (.milestone(movingID), .milestone(targetID, placement)):
            guard movingID != targetID else { return }
            onMoveMilestone(movingID, targetID, placement)
        case let (.subTask(movingID), .subTask(parentID: parentID, subTaskID: targetSubTaskID, placement: placement)):
            guard movingID != targetSubTaskID else { return }
            onMoveSubTask(movingID, parentID, targetSubTaskID, placement)
        case let (.subTask(movingID), .milestone(targetID, _)):
            onMoveSubTask(movingID, targetID, nil, .end)
        default:
            break
        }
    }
}

private extension View {
    func safeListRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled(true)
    }
}

private enum TaskDragItem: Equatable {
    case milestone(UUID)
    case subTask(UUID)

    var providerValue: String {
        switch self {
        case let .milestone(id):
            return "milestone:\(id.uuidString)"
        case let .subTask(id):
            return "subtask:\(id.uuidString)"
        }
    }
}

private enum TaskDropTarget: Equatable {
    case milestone(UUID, ReorderPlacement)
    case subTask(parentID: UUID, subTaskID: UUID?, placement: ReorderPlacement)
}

private struct TaskDropLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .offset(x: -3)
            }
            .allowsHitTesting(false)
    }
}

private struct TaskRowDropDelegate: DropDelegate {
    let target: TaskRowDropTarget
    let rowHeight: CGFloat
    @Binding var draggingItem: TaskDragItem?
    @Binding var dropTarget: TaskDropTarget?
    let onPerformDrop: (TaskDragItem, TaskDropTarget) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingItem != nil
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropTarget = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingItem = nil
            dropTarget = nil
        }

        guard let draggingItem,
              let dropTarget
        else { return false }

        onPerformDrop(draggingItem, dropTarget)
        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard let draggingItem else { return }

        let placement: ReorderPlacement = info.location.y < max(rowHeight / 2, 1) ? .before : .after
        switch (draggingItem, target) {
        case (.milestone, let .milestone(id)):
            dropTarget = .milestone(id, placement)
        case (.subTask, let .milestone(id)):
            dropTarget = .subTask(parentID: id, subTaskID: nil, placement: .end)
        case (.subTask, let .subTask(parentID: parentID, subTaskID: subTaskID)):
            dropTarget = .subTask(parentID: parentID, subTaskID: subTaskID, placement: placement)
        case (.milestone, .subTask):
            dropTarget = nil
        }
    }
}

private struct TaskEndDropDelegate: DropDelegate {
    @Binding var draggingItem: TaskDragItem?
    @Binding var dropTarget: TaskDropTarget?
    let onMoveMilestone: (UUID, UUID?, ReorderPlacement) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        if case .some(.milestone) = draggingItem {
            return true
        }
        return false
    }

    func dropEntered(info: DropInfo) {
        if case .some(.milestone) = draggingItem {
            dropTarget = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingItem = nil
            dropTarget = nil
        }
        guard case let .some(.milestone(id)) = draggingItem else { return false }
        onMoveMilestone(id, nil, .end)
        return true
    }
}

private enum TaskRowDropTarget {
    case milestone(UUID)
    case subTask(parentID: UUID, subTaskID: UUID)
}

private struct SafeMilestoneRowView: View {
    let snapshot: MilestoneSnapshot
    let onToggleMilestone: (UUID) -> Void
    let onUpdateMilestoneTitle: (UUID, String) -> Void
    let onDeleteMilestone: (UUID) -> Void
    @Binding var reminder: Reminder?
    let onReminderChange: (Reminder?) -> Void
    let onBeginAddSubTask: () -> Void
    @Binding var draggingItem: TaskDragItem?
    @Binding var dropTarget: TaskDropTarget?
    let onPerformDrop: (TaskDragItem, TaskDropTarget) -> Void

    @State private var isEditing = false
    @State private var titleDraft = ""
    @State private var isRowHovered = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        milestoneRow
        .padding(.leading)
        .padding(.vertical, milestoneRowOuterVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusable(false)
        .onChange(of: isTitleFocused) { _, focused in
            guard !focused else { return }
            commitTitleEdit()
        }
    }

    private var milestoneRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onToggleMilestone(snapshot.id)
            } label: {
                Image(systemName: snapshot.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(snapshot.isCompleted ? AnyShapeStyle(ViabarColor.success) : AnyShapeStyle(.secondary))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            milestoneTitle

            ReminderStatusView(
                reminder: $reminder,
                isCompleted: snapshot.isCompleted,
                isEditing: isEditing,
                iconFont: .body,
                textFont: .caption,
                onReminderChange: onReminderChange
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(isRowHovered ? 0.16 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .focusable(false)
        .onHover { isRowHovered = $0 }
        .onDrag {
            draggingItem = .milestone(snapshot.id)
            return NSItemProvider(object: TaskDragItem.milestone(snapshot.id).providerValue as NSString)
        } preview: {
            Image(systemName: "line.3.horizontal")
                .font(.title3)
                .padding(8)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onDrop(
                        of: [.plainText],
                        delegate: TaskRowDropDelegate(
                            target: .milestone(snapshot.id),
                            rowHeight: proxy.size.height,
                            draggingItem: $draggingItem,
                            dropTarget: $dropTarget,
                            onPerformDrop: onPerformDrop
                        )
                    )
            }
        }
        .overlay(alignment: dropLineAlignment) {
            if isCurrentMilestoneDropTarget {
                TaskDropLine()
            }
        }
        .contextMenu {
            Button {
                onBeginAddSubTask()
            } label: {
                Label("新增子任务", systemImage: "list.bullet.below.rectangle")
            }
            Divider()
            Button {
                beginTitleEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDeleteMilestone(snapshot.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var isCurrentMilestoneDropTarget: Bool {
        if case let .milestone(id, _) = dropTarget {
            return id == snapshot.id
        }
        if case let .subTask(parentID: parentID, subTaskID: nil, placement: _) = dropTarget {
            return parentID == snapshot.id
        }
        return false
    }

    private var dropLineAlignment: Alignment {
        switch dropTarget {
        case let .milestone(id, placement) where id == snapshot.id:
            return placement == .before ? .top : .bottom
        case let .subTask(parentID: parentID, subTaskID: nil, placement: _) where parentID == snapshot.id:
            return .bottom
        default:
            return .bottom
        }
    }

    @ViewBuilder
    private var milestoneTitle: some View {
        if isEditing {
            TextField("里程碑", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(nil)
                .font(.body)
                .focused($isTitleFocused)
                .onSubmit { commitTitleEdit() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        } else {
            Text(snapshot.title)
                .font(.body)
                .strikethrough(snapshot.isCompleted)
                .foregroundStyle(snapshot.isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .onTapGesture(count: 2) {
                    beginTitleEdit()
                }
        }
    }

    private func beginTitleEdit() {
        titleDraft = snapshot.title
        isEditing = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        guard isEditing else { return }
        onUpdateMilestoneTitle(snapshot.id, titleDraft)
        isEditing = false
    }

}

private struct SafeSubTaskComposerView: View {
    let milestoneID: UUID
    let leadingIndent: CGFloat
    let onAddSubTask: (UUID, String) -> Bool
    let onClose: () -> Void

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear
                .frame(width: leadingIndent)

            Image(systemName: "circle.dotted")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            TextField("新子任务…", text: $title)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)
                .onSubmit { commit(keepsOpen: true) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isFocused = true
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            commit(keepsOpen: false)
        }
    }

    private func commit(keepsOpen: Bool) {
        let hasDraft = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasDraft else {
            onClose()
            return
        }

        if onAddSubTask(milestoneID, title) {
            title = ""
            if keepsOpen {
                isFocused = true
            } else {
                onClose()
            }
        }
    }
}

private struct SafeSubTaskRowView: View {
    let subtask: SubTaskSnapshot
    let parentID: UUID
    let leadingIndent: CGFloat
    @Binding var reminder: Reminder?
    let onToggle: (UUID) -> Void
    let onUpdateTitle: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onReminderChange: (Reminder?) -> Void
    @Binding var draggingItem: TaskDragItem?
    @Binding var dropTarget: TaskDropTarget?
    let onPerformDrop: (TaskDragItem, TaskDropTarget) -> Void

    @State private var isEditing = false
    @State private var titleDraft = ""
    @State private var isRowHovered = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear
                .frame(width: leadingIndent)

            Button {
                onToggle(subtask.id)
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isCompleted ? AnyShapeStyle(ViabarColor.success) : AnyShapeStyle(.secondary))
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            subTaskTitle

            ReminderStatusView(
                reminder: $reminder,
                isCompleted: subtask.isCompleted,
                isEditing: isEditing,
                iconFont: .caption,
                textFont: .caption2,
                onReminderChange: onReminderChange
            )
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(isRowHovered ? 0.16 : 0))
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .focusable(false)
        .onHover { isRowHovered = $0 }
        .onDrag {
            draggingItem = .subTask(subtask.id)
            return NSItemProvider(object: TaskDragItem.subTask(subtask.id).providerValue as NSString)
        } preview: {
            Image(systemName: "circle.grid.cross")
                .font(.title3)
                .padding(8)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onDrop(
                        of: [.plainText],
                        delegate: TaskRowDropDelegate(
                            target: .subTask(parentID: parentID, subTaskID: subtask.id),
                            rowHeight: proxy.size.height,
                            draggingItem: $draggingItem,
                            dropTarget: $dropTarget,
                            onPerformDrop: onPerformDrop
                        )
                    )
            }
        }
        .overlay(alignment: dropLineAlignment) {
            if isCurrentSubTaskDropTarget {
                TaskDropLine()
                    .padding(.leading, leadingIndent)
            }
        }
        .contextMenu {
            Button {
                beginTitleEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete(subtask.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            guard !focused else { return }
            commitTitleEdit()
        }
    }

    private var isCurrentSubTaskDropTarget: Bool {
        if case let .subTask(parentID: _, subTaskID: subTaskID, placement: _) = dropTarget {
            return subTaskID == subtask.id
        }
        return false
    }

    private var dropLineAlignment: Alignment {
        if case let .subTask(parentID: _, subTaskID: subTaskID, placement: placement) = dropTarget,
           subTaskID == subtask.id {
            return placement == .before ? .top : .bottom
        }
        return .bottom
    }

    @ViewBuilder
    private var subTaskTitle: some View {
        if isEditing {
            TextField("子任务", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(nil)
                .font(.callout)
                .focused($isTitleFocused)
                .onSubmit { commitTitleEdit() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        } else {
            Text(subtask.title)
                .font(.callout)
                .strikethrough(subtask.isCompleted)
                .foregroundStyle(subtask.isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .onTapGesture(count: 2) {
                    beginTitleEdit()
                }
        }
    }

    private func beginTitleEdit() {
        titleDraft = subtask.title
        isEditing = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        guard isEditing else { return }
        onUpdateTitle(subtask.id, titleDraft)
        isEditing = false
    }
}

private struct ReminderStatusView: View {
    @Binding var reminder: Reminder?
    let isCompleted: Bool
    let isEditing: Bool
    let iconFont: Font
    let textFont: Font
    let onReminderChange: (Reminder?) -> Void

    @State private var isReminderPopoverPresented = false
    @State private var isPostponeButtonHovered = false

    private var hasReminder: Bool {
        reminder != nil
    }

    private var alarmColor: AnyShapeStyle {
        guard hasReminder else {
            return AnyShapeStyle(.tertiary)
        }

        guard !isCompleted else {
            return AnyShapeStyle(.secondary)
        }

        return AnyShapeStyle(.orange)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            reminderInfo

            Button {
                isReminderPopoverPresented = true
            } label: {
                Image(systemName: hasReminder ? "alarm.fill" : "alarm")
                    .font(iconFont)
                    .foregroundStyle(alarmColor)
                    .frame(width: reminderColumnWidth)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .popover(isPresented: $isReminderPopoverPresented, arrowEdge: .trailing) {
                ReminderSettingsPopover(reminder: $reminder, onReminderChange: onReminderChange)
            }
        }
        .frame(width: reminderColumnWidth + reminderInfoColumnWidth + 4, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var reminderInfo: some View {
        if let reminder {
            HStack(spacing: 5) {
                Spacer(minLength: 0)

                if reminder.isRepeating {
                    postponeButton(for: reminder)
                }

                Text(reminder.inlineReminderSummary)
                    .font(textFont)
                    .foregroundStyle(summaryColor(for: reminder))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .frame(width: reminderInfoColumnWidth, alignment: .trailing)
        } else {
            Color.clear
                .frame(width: reminderInfoColumnWidth)
        }
    }

    private func summaryColor(for reminder: Reminder) -> AnyShapeStyle {
        if isCompleted {
            return AnyShapeStyle(.secondary)
        }

        if reminder.isInlineReminderOverdue {
            return AnyShapeStyle(.red)
        }

        if reminder.isInlineReminderTodayPending {
            return AnyShapeStyle(.orange)
        }

        return AnyShapeStyle(.secondary)
    }

    private func postponeColor(for reminder: Reminder) -> AnyShapeStyle {
        if isCompleted {
            return AnyShapeStyle(.secondary)
        }

        if isPostponeButtonHovered {
            return AnyShapeStyle(MilestoneListStyle.sendButtonActive)
        }

        if reminder.isInlineReminderOverdue || reminder.isInlineReminderTodayPending {
            return AnyShapeStyle(.blue)
        }

        return AnyShapeStyle(.secondary)
    }

    private func postponeButton(for reminder: Reminder) -> some View {
        Button {
            guard !isCompleted else { return }
            postponeReminder(reminder)
        } label: {
            Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                .font(iconFont)
                .foregroundStyle(postponeColor(for: reminder))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("推迟一个循环周期")
        .onHover { hovering in
            guard !isCompleted else { return }
            isPostponeButtonHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func postponeReminder(_ reminder: Reminder) {
        guard let nextDate = reminder.postponedByOneCycle else { return }
        let updatedReminder = Reminder(
            type: reminder.type,
            fireTime: reminder.fireTime,
            fireTimestamp: nextDate,
            repeatIntervalDays: reminder.repeatIntervalDays
        )
        self.reminder = updatedReminder
        onReminderChange(updatedReminder)
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

private extension Reminder {
    var isRepeating: Bool {
        type == "repeating"
    }

    var inlineFireDate: Date? {
        fireTimestamp ?? nextRepeatingFireDate
    }

    var inlineReminderSummary: String {
        let time = formattedInlineReminderTime
        guard isRepeating else { return time }
        return "\(time) \(inlineRepeatTitle)"
    }

    var isInlineReminderOverdue: Bool {
        guard let date = inlineFireDate else { return false }
        return date < Date()
    }

    var isInlineReminderTodayPending: Bool {
        guard let date = inlineFireDate else { return false }
        return Calendar.current.isDateInToday(date) && date >= Date()
    }

    var formattedInlineReminderTime: String {
        guard let date = inlineFireDate else { return "--" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        if calendar.isDateInToday(date) {
            return "今天 \(formatter.string(from: date))"
        }

        if calendar.isDateInTomorrow(date) {
            return "明天 \(formatter.string(from: date))"
        }

        formatter.dateFormat = "M/d/yy HH:mm"
        return formatter.string(from: date)
    }

    var inlineRepeatTitle: String {
        guard isRepeating else { return "" }
        switch repeatIntervalDays {
        case 0: return "每小时"
        case 1: return "每天"
        case 2: return "每2天"
        case 3: return "每3天"
        case -1: return "工作日"
        case 7: return "每周"
        case 14: return "每两周"
        case 30: return "每月"
        case 90: return "每3个月"
        case 180: return "每6个月"
        case 365: return "每年"
        default: return "循环"
        }
    }

    var postponedByOneCycle: Date? {
        guard isRepeating, let baseDate = inlineFireDate else { return nil }

        let calendar = Calendar.current
        switch repeatIntervalDays {
        case 0:
            return calendar.date(byAdding: .hour, value: 1, to: baseDate)
        case -1:
            return nextWeekday(after: baseDate)
        case 30:
            return calendar.date(byAdding: .month, value: 1, to: baseDate)
        case 90:
            return calendar.date(byAdding: .month, value: 3, to: baseDate)
        case 180:
            return calendar.date(byAdding: .month, value: 6, to: baseDate)
        case 365:
            return calendar.date(byAdding: .year, value: 1, to: baseDate)
        default:
            return calendar.date(byAdding: .day, value: repeatIntervalDays ?? 1, to: baseDate)
        }
    }

    private var nextRepeatingFireDate: Date? {
        guard let fireTime else { return fireTimestamp }

        let parts = fireTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return fireTimestamp }

        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = 0

        guard let today = calendar.date(from: components) else { return fireTimestamp }
        if today >= now {
            return today
        }

        return calendar.date(byAdding: .day, value: repeatIntervalDays ?? 1, to: today)
    }

    private func nextWeekday(after date: Date) -> Date? {
        var candidate = Calendar.current.date(byAdding: .day, value: 1, to: date)
        while let current = candidate {
            let weekday = Calendar.current.component(.weekday, from: current)
            if weekday != 1 && weekday != 7 {
                return current
            }
            candidate = Calendar.current.date(byAdding: .day, value: 1, to: current)
        }
        return nil
    }
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
