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
    var navigationRequest: GlobalSearchNavigationRequest? = nil

    @Environment(ServiceContainer.self) private var container
    @State private var newMilestoneTitle: String = ""
    @FocusState private var isNewMilestoneFocused: Bool
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

    private var targetedMilestoneID: UUID? {
        guard navigationRequest?.projectID == project.projectId else { return nil }
        switch navigationRequest?.destination {
        case let .some(.milestone(id)):
            return id
        case let .some(.subTask(milestoneID, _)):
            return milestoneID
        default:
            return nil
        }
    }

    private var targetedSubTaskID: UUID? {
        guard navigationRequest?.projectID == project.projectId,
              case let .some(.subTask(_, subTaskID)) = navigationRequest?.destination
        else { return nil }
        return subTaskID
    }

    private var scrollTargetID: UUID? {
        targetedSubTaskID ?? targetedMilestoneID
    }

    // MARK: - Filtered Milestones

    private var visibleMilestones: [Milestone] {
        let sorted = project.milestones.sorted { $0.orderIndex < $1.orderIndex }
        guard project.hideCompleted else { return sorted }
        return sorted.filter { m in
            m.milestoneId == targetedMilestoneID
                || !m.isCompleted
                || m.subtasks.contains(where: { !$0.isCompleted || $0.taskId == targetedSubTaskID })
        }
    }

    private var milestoneSnapshots: [MilestoneSnapshot] {
        visibleMilestones.map { milestone in
            let sortedSubtasks = milestone.subtasks.sorted { $0.orderIndex < $1.orderIndex }
            let visibleSubtasks = project.hideCompleted
                ? sortedSubtasks.filter { !$0.isCompleted || $0.taskId == targetedSubTaskID }
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
        .background(ViabarColor.mainPanelBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("里程碑", systemImage: "list.bullet.rectangle")
                .font(.headline)

            Spacer()

            Toggle(isOn: Binding(
                get: { project.hideCompleted },
                set: { project.hideCompleted = $0; projectService?.updateProjectDisplayPreferences(project) }
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
                subTaskReminderBinding: subTaskReminderBinding(id:),
                scrollTargetID: scrollTargetID,
                navigationRequestID: navigationRequest?.id
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
                    .focused($isNewMilestoneFocused)
                    .onSubmit { commitNewMilestone() }
                    .padding(.leading, 12)
                    .padding(.trailing, 40)
                    .padding(.vertical, 10)
                    .frame(minHeight: 68, maxHeight: 68, alignment: .topLeading)
                    .contentShape(Rectangle())

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
            .onTapGesture { isNewMilestoneFocused = true }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ViabarColor.panelInputBackground)
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
                    ViabarColor.mainPanelBackground.opacity(0),
                    ViabarColor.mainPanelBackground.opacity(0.9)
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
                projectService?.updateReminder(reminder, for: milestone)
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
                        projectService?.updateReminder(reminder, for: subtask)
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
    let scrollTargetID: UUID?
    let navigationRequestID: UUID?

    @State private var addingSubTaskFor: UUID?
    @State private var draggingItem: TaskDragItem?
    @State private var dropTarget: TaskDropTarget?
    private let bottomAnchorID = "milestone-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(taskRows.enumerated()), id: \.element.id) { index, row in
                    taskRow(row)
                        .overlay(alignment: .top) {
                            taskDropSeparator(
                                topTaskDropZone(for: row, index: index),
                                edge: .top,
                                showsLine: index == 0
                            )
                        }
                        .overlay(alignment: .bottom) {
                            taskDropSeparator(
                                bottomTaskDropZone(
                                    for: row,
                                    nextRow: index < taskRows.count - 1 ? taskRows[index + 1] : nil
                                ),
                                edge: .bottom,
                                showsLine: true
                            )
                        }
                        .id(row.id)
                        .safeListRow()

                    if case let .milestone(snapshot) = row,
                       addingSubTaskFor == snapshot.id {
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
                    .safeListRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tint(Color(nsColor: .tertiaryLabelColor))
            .accentColor(Color(nsColor: .tertiaryLabelColor))
            .onChange(of: scrollToBottomTrigger) { _, _ in
                scrollToBottom(proxy)
            }
            .onAppear {
                scrollToTarget(proxy)
            }
            .onChange(of: navigationRequestID) { _, _ in
                scrollToTarget(proxy)
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

    private func scrollToTarget(_ proxy: ScrollViewProxy) {
        guard let scrollTargetID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(scrollTargetID, anchor: .center)
            }
        }
    }

    private var firstVisibleTaskID: UUID? {
        snapshots.first?.id
    }

    private var lastVisibleTaskID: UUID? {
        guard let lastSnapshot = snapshots.last else { return nil }
        return lastSnapshot.subtasks.last?.id ?? lastSnapshot.id
    }

    private var taskRows: [SafeTaskRow] {
        snapshots.flatMap { snapshot -> [SafeTaskRow] in
            [.milestone(snapshot)] + snapshot.subtasks.map { .subTask($0, parentID: snapshot.id) }
        }
    }

    private func highlightCornerStyle(for id: UUID) -> TaskHighlightCornerStyle {
        switch (id == firstVisibleTaskID, id == lastVisibleTaskID) {
        case (true, true):
            return .all
        case (true, false):
            return .top
        case (false, true):
            return .bottom
        case (false, false):
            return .middle
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

    @ViewBuilder
    private func taskRow(_ row: SafeTaskRow) -> some View {
        switch row {
        case let .milestone(snapshot):
            SafeMilestoneRowView(
                snapshot: snapshot,
                highlightRequestID: snapshot.id == scrollTargetID ? navigationRequestID : nil,
                highlightCornerStyle: highlightCornerStyle(for: snapshot.id),
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
                draggingItem: $draggingItem
            )
        case let .subTask(subtask, parentID):
            SafeSubTaskRowView(
                subtask: subtask,
                parentID: parentID,
                leadingIndent: subTaskLeadingIndent,
                highlightRequestID: subtask.id == scrollTargetID ? navigationRequestID : nil,
                highlightCornerStyle: highlightCornerStyle(for: subtask.id),
                reminder: subTaskReminderBinding(subtask.id),
                onToggle: onToggleSubTask,
                onUpdateTitle: onUpdateSubTaskTitle,
                onDelete: onDeleteSubTask,
                onReminderChange: { reminder in
                    onSubTaskReminderChange(subtask.id, reminder)
                },
                draggingItem: $draggingItem
            )
        }
    }

    private func topTaskDropZone(for row: SafeTaskRow, index: Int) -> TaskDropZone? {
        guard let draggingItem else { return nil }

        switch (draggingItem, row) {
        case (.milestone, let .milestone(snapshot)):
            return TaskDropZone(target: .milestone(snapshot.id, .before), leadingPadding: 0)
        case (.subTask, let .subTask(subtask, parentID)):
            return TaskDropZone(
                target: .subTask(parentID: parentID, subTaskID: subtask.id, placement: .before),
                leadingPadding: subTaskLeadingIndent
            )
        default:
            return nil
        }
    }

    private func bottomTaskDropZone(for row: SafeTaskRow, nextRow: SafeTaskRow?) -> TaskDropZone? {
        guard let draggingItem else { return nil }

        switch draggingItem {
        case .milestone:
            guard row.isLastVisibleRowInMilestoneGroup(nextRow: nextRow),
                  let milestoneID = row.milestoneID
            else { return nil }

            if case let .milestone(nextSnapshot)? = nextRow {
                return TaskDropZone(target: .milestone(nextSnapshot.id, .before), leadingPadding: 0)
            }
            return TaskDropZone(target: .milestone(milestoneID, .after), leadingPadding: 0)
        case .subTask:
            switch row {
            case let .milestone(snapshot):
                if case let .subTask(nextSubtask, parentID)? = nextRow,
                   parentID == snapshot.id {
                    return TaskDropZone(
                        target: .subTask(parentID: snapshot.id, subTaskID: nextSubtask.id, placement: .before),
                        leadingPadding: subTaskLeadingIndent
                    )
                }
                return TaskDropZone(
                    target: .subTask(parentID: snapshot.id, subTaskID: nil, placement: .end),
                    leadingPadding: subTaskLeadingIndent
                )
            case let .subTask(_, parentID):
                if case let .subTask(nextSubtask, nextParentID)? = nextRow,
                   nextParentID == parentID {
                    return TaskDropZone(
                        target: .subTask(parentID: parentID, subTaskID: nextSubtask.id, placement: .before),
                        leadingPadding: subTaskLeadingIndent
                    )
                }
                return TaskDropZone(
                    target: .subTask(parentID: parentID, subTaskID: nil, placement: .end),
                    leadingPadding: subTaskLeadingIndent
                )
            }
        }
    }

    @ViewBuilder
    private func taskDropSeparator(_ zone: TaskDropZone?, edge: TaskDropSeparatorEdge, showsLine: Bool) -> some View {
        if let zone {
            TaskReorderDropSeparator(
                isActive: dropTarget == zone.target,
                leadingPadding: zone.leadingPadding,
                edge: edge,
                showsLine: showsLine
            )
            .onDrop(
                of: [.plainText],
                delegate: TaskSeparatorDropDelegate(
                    target: zone.target,
                    draggingItem: $draggingItem,
                    dropTarget: $dropTarget,
                    onPerformDrop: performDrop(_:target:)
                )
            )
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

private enum SafeTaskRow: Identifiable, Equatable {
    case milestone(MilestoneSnapshot)
    case subTask(SubTaskSnapshot, parentID: UUID)

    var id: UUID {
        switch self {
        case let .milestone(snapshot):
            return snapshot.id
        case let .subTask(snapshot, _):
            return snapshot.id
        }
    }

    var milestoneID: UUID? {
        switch self {
        case let .milestone(snapshot):
            return snapshot.id
        case let .subTask(_, parentID):
            return parentID
        }
    }

    func isLastVisibleRowInMilestoneGroup(nextRow: SafeTaskRow?) -> Bool {
        guard let nextRow else { return true }
        return milestoneID != nextRow.milestoneID
    }
}

private struct TaskDropZone {
    let target: TaskDropTarget
    let leadingPadding: CGFloat
}

private struct TaskDropLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(height: 2)
            .allowsHitTesting(false)
    }
}

private enum TaskDropSeparatorEdge {
    case top
    case bottom
}

private struct TaskReorderDropSeparator: View {
    let isActive: Bool
    let leadingPadding: CGFloat
    let edge: TaskDropSeparatorEdge
    let showsLine: Bool

    var body: some View {
        ZStack(alignment: alignment) {
            Color.primary.opacity(0.001)
            if isActive && showsLine {
                TaskDropLine()
                    .padding(.leading, leadingPadding)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
        .contentShape(Rectangle())
    }

    private var alignment: Alignment {
        switch edge {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
}

private struct TaskSeparatorDropDelegate: DropDelegate {
    let target: TaskDropTarget
    @Binding var draggingItem: TaskDragItem?
    @Binding var dropTarget: TaskDropTarget?
    let onPerformDrop: (TaskDragItem, TaskDropTarget) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggingItem else { return false }
        switch (draggingItem, target) {
        case (.milestone, .milestone):
            return true
        case (.milestone, .subTask):
            return false
        case (.subTask, .subTask):
            return true
        case (.subTask, .milestone):
            return false
        }
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

        guard let draggingItem else { return false }

        onPerformDrop(draggingItem, target)
        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        dropTarget = target
    }
}

private enum TaskHighlightCornerStyle {
    case all
    case top
    case bottom
    case middle

    var radii: RectangleCornerRadii {
        switch self {
        case .all:
            return RectangleCornerRadii(topLeading: 8, bottomLeading: 8, bottomTrailing: 8, topTrailing: 8)
        case .top:
            return RectangleCornerRadii(topLeading: 8, bottomLeading: 0, bottomTrailing: 0, topTrailing: 8)
        case .bottom:
            return RectangleCornerRadii(topLeading: 0, bottomLeading: 8, bottomTrailing: 8, topTrailing: 0)
        case .middle:
            return RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0)
        }
    }
}

private struct TaskRowBackground: View {
    let isSearchHighlighted: Bool
    let isRowHovered: Bool
    let highlightCornerStyle: TaskHighlightCornerStyle

    var body: some View {
        if isSearchHighlighted {
            UnevenRoundedRectangle(cornerRadii: highlightCornerStyle.radii, style: .continuous)
                .fill(.orange)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(isRowHovered ? 0.16 : 0))
        }
    }
}

private struct SafeMilestoneRowView: View {
    let snapshot: MilestoneSnapshot
    let highlightRequestID: UUID?
    let highlightCornerStyle: TaskHighlightCornerStyle
    let onToggleMilestone: (UUID) -> Void
    let onUpdateMilestoneTitle: (UUID, String) -> Void
    let onDeleteMilestone: (UUID) -> Void
    @Binding var reminder: Reminder?
    let onReminderChange: (Reminder?) -> Void
    let onBeginAddSubTask: () -> Void
    @Binding var draggingItem: TaskDragItem?

    @State private var isEditing = false
    @State private var titleDraft = ""
    @State private var isRowHovered = false
    @State private var isSearchHighlighted = false
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
        .task(id: highlightRequestID) {
            guard highlightRequestID != nil else {
                isSearchHighlighted = false
                return
            }

            isSearchHighlighted = true
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                isSearchHighlighted = false
            }
        }
    }

    private var milestoneRow: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    onToggleMilestone(snapshot.id)
                } label: {
                    Image(systemName: snapshot.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            isSearchHighlighted
                                ? AnyShapeStyle(.white)
                                : snapshot.isCompleted ? AnyShapeStyle(ViabarColor.success) : AnyShapeStyle(.secondary)
                        )
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)

                milestoneTitle
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { beginTitleEdit() }

            ReminderStatusView(
                reminder: $reminder,
                isCompleted: snapshot.isCompleted,
                isEditing: isEditing,
                iconFont: .body,
                textFont: .caption,
                usesInvertedForeground: isSearchHighlighted,
                onReminderChange: onReminderChange
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            TaskRowBackground(
                isSearchHighlighted: isSearchHighlighted,
                isRowHovered: isRowHovered,
                highlightCornerStyle: highlightCornerStyle
            )
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

    @ViewBuilder
    private var milestoneTitle: some View {
        if isEditing {
            TextField("里程碑", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(nil)
                .font(.body)
                .foregroundStyle(.primary)
                .focused($isTitleFocused)
                .onSubmit { commitTitleEdit() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        } else {
            Text(snapshot.title)
                .font(.body)
                .strikethrough(snapshot.isCompleted)
                .foregroundStyle(
                    isSearchHighlighted
                        ? AnyShapeStyle(.white)
                        : snapshot.isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
                )
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
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
                .contentShape(Rectangle())
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
    var highlightRequestID: UUID? = nil
    let highlightCornerStyle: TaskHighlightCornerStyle
    @Binding var reminder: Reminder?
    let onToggle: (UUID) -> Void
    let onUpdateTitle: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onReminderChange: (Reminder?) -> Void
    @Binding var draggingItem: TaskDragItem?

    @State private var isEditing = false
    @State private var titleDraft = ""
    @State private var isRowHovered = false
    @State private var isSearchHighlighted = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear
                .frame(width: leadingIndent)

            HStack(alignment: .top, spacing: 8) {
                Button {
                    onToggle(subtask.id)
                } label: {
                    Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            isSearchHighlighted
                                ? AnyShapeStyle(.white)
                                : subtask.isCompleted ? AnyShapeStyle(ViabarColor.success) : AnyShapeStyle(.secondary)
                        )
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                subTaskTitle
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { beginTitleEdit() }

            ReminderStatusView(
                reminder: $reminder,
                isCompleted: subtask.isCompleted,
                isEditing: isEditing,
                iconFont: .caption,
                textFont: .caption2,
                usesInvertedForeground: isSearchHighlighted,
                onReminderChange: onReminderChange
            )
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            TaskRowBackground(
                isSearchHighlighted: isSearchHighlighted,
                isRowHovered: isRowHovered,
                highlightCornerStyle: highlightCornerStyle
            )
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
        .task(id: highlightRequestID) {
            guard highlightRequestID != nil else {
                isSearchHighlighted = false
                return
            }

            isSearchHighlighted = true
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                isSearchHighlighted = false
            }
        }
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
                .foregroundStyle(
                    isSearchHighlighted
                        ? AnyShapeStyle(.white)
                        : subtask.isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
                )
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
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
    var usesInvertedForeground: Bool = false
    let onReminderChange: (Reminder?) -> Void

    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var isReminderPopoverPresented = false
    @State private var isPostponeButtonHovered = false

    private var hasReminder: Bool {
        reminder != nil
    }

    private var savedDateFormat: String? {
        settingsRecords.first?.dateFormat
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    private var alarmColor: AnyShapeStyle {
        if usesInvertedForeground {
            return AnyShapeStyle(.white)
        }

        guard hasReminder else {
            return AnyShapeStyle(.tertiary)
        }

        if isCompleted {
            return AnyShapeStyle(.secondary)
        }

        return AnyShapeStyle(.orange)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
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

                Text(reminder.displaySummary(dateFormatPattern: savedDateFormat, language: effectiveLanguage))
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
        if usesInvertedForeground {
            return AnyShapeStyle(.white)
        }

        if isCompleted {
            return AnyShapeStyle(.secondary)
        }

        if reminder.isOverdue(at: Date()) {
            return AnyShapeStyle(.red)
        }

        if reminder.isTodayPending(at: Date()) {
            return AnyShapeStyle(.orange)
        }

        return AnyShapeStyle(.secondary)
    }

    private func postponeColor(for reminder: Reminder) -> AnyShapeStyle {
        if usesInvertedForeground {
            return AnyShapeStyle(.white)
        }

        if isCompleted {
            return AnyShapeStyle(.secondary)
        }

        if isPostponeButtonHovered {
            return AnyShapeStyle(MilestoneListStyle.sendButtonActive)
        }

        if reminder.isOverdue(at: Date()) || reminder.isTodayPending(at: Date()) {
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
    @Environment(\.locale) private var locale
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
                        Text(completionTimestampLabel(completedAt, language: .resolve(locale: locale)))
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
    @Environment(\.locale) private var locale
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
        let language = EffectiveAppLanguage.resolve(locale: locale)
        return AppLocalization.format(
            "%@（%@）",
            language: language,
            subTask.title,
            formatCompletionTimestamp(completedAt, language: language)
        )
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

private func completionTimestampLabel(_ date: Date, language: EffectiveAppLanguage) -> String {
    AppLocalization.format("（%@）", language: language, formatCompletionTimestamp(date, language: language))
}

private func formatCompletionTimestamp(_ date: Date, language: EffectiveAppLanguage) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()

    if calendar.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    if calendar.isDateInYesterday(date) {
        formatter.dateFormat = "HH:mm"
        return AppLocalization.format("昨天 %@", language: language, formatter.string(from: date))
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
        .modelContainer(for: AppSettings.self, inMemory: true)
}
