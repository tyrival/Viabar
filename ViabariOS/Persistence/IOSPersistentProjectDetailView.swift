import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let iosMemoReorderLogStart = Date()

private func iosMemoReorderLog(_ message: String) {
    let elapsed = Date().timeIntervalSince(iosMemoReorderLogStart)
    print(String(format: "[IOSMemoReorder +%.3fs] %@", elapsed, message))
}

private enum IOSPersistentDetailSession: Equatable {
    case idle
    case addMilestone
    case addSubtask(milestoneID: UUID)
    case addMemo
    case editMilestone(milestoneID: UUID)
    case editSubtask(milestoneID: UUID, subtaskID: UUID)
    case editMemo(memoID: UUID)
}

private enum IOSPersistentReminderEditorTarget: Identifiable {
    case milestone(Milestone)
    case subtask(SubTask)

    var id: UUID {
        switch self {
        case .milestone(let milestone): milestone.milestoneId
        case .subtask(let subtask): subtask.taskId
        }
    }

    var reminder: Reminder? {
        switch self {
        case .milestone(let milestone): milestone.reminder
        case .subtask(let subtask): subtask.reminder
        }
    }
}

struct IOSPersistentProjectDetailView: View {
    @Environment(ServiceContainer.self) private var services
    @Query(sort: \ArchiveFolder.orderIndex) private var archiveFolders: [ArchiveFolder]
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @Bindable var coordinator: IOSPersistenceCoordinator
    let project: Project

    @State private var session: IOSPersistentDetailSession = .idle
    @State private var composerText = ""
    @State private var isArchiveFolderPickerPresented = false
    @State private var reminderEditorTarget: IOSPersistentReminderEditorTarget?
    @State private var draggingTaskItem: IOSPersistentTaskDragItem?
    @State private var taskDropTarget: IOSPersistentDropIndicator?
    @State private var draggingMemoID: UUID?
    @State private var memoDisplayOrderOverride: [UUID]?
    @State private var memoDragSessionID: UUID?
    @State private var memoDragSessionSawDropEvent = false
    @State private var memoDragEventCounter = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        projectHeader

                        switch coordinator.detailTab {
                        case .tasks:
                            taskList
                        case .memos:
                            memoList
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    scrollToNavigationTarget(using: proxy)
                }
                .onChange(of: coordinator.navigationRequest?.id) { _, _ in
                    scrollToNavigationTarget(using: proxy)
                }
            }

            detailFooter
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
                .zIndex(10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.accentColor)
        .onChange(of: draggingMemoID) { _, newValue in
            iosMemoReorderLog("draggingMemoID changed to \(newValue?.uuidString ?? "nil")")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    Image(systemName: project.sfSymbolName)
                        .foregroundStyle(accentColor)
                    Text(project.title)
                        .font(.subheadline.weight(.semibold))
                    if project.isFavorite && !project.isArchived {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(ViabarColor.warning)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !project.isArchived {
                        Button(LocalizedStringKey(project.isFavorite ? "取消收藏" : "收藏"), systemImage: project.isFavorite ? "star.slash" : "star") {
                            services.projectService?.toggleFavorite(project)
                        }
                    }
                    Button(LocalizedStringKey(project.isArchived ? "取消归档" : "归档"), systemImage: project.isArchived ? "arrow.uturn.backward" : "archivebox") {
                        toggleArchive()
                    }
                    if !project.isArchived {
                        Button(LocalizedStringKey(project.hideCompleted ? "显示已完成任务" : "隐藏已完成任务"), systemImage: project.hideCompleted ? "eye" : "eye.slash") {
                            project.hideCompleted.toggle()
                            services.projectService?.updateProjectDisplayPreferences(project)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onChange(of: coordinator.detailTab) { _, _ in
            closeComposer()
        }
        .onChange(of: project.isArchived) { _, isArchived in
            if isArchived {
                closeComposer()
            }
        }
        .sheet(isPresented: $isArchiveFolderPickerPresented) {
            IOSPersistentArchiveFolderPicker(
                folders: archiveFolders,
                currentFolderID: nil,
                actionTitle: "归档"
            ) { folder in
                services.projectService?.archiveProject(project, to: folder)
            }
        }
        .sheet(item: $reminderEditorTarget) { target in
            IOSPersistentReminderEditor(reminder: target.reminder) { reminder in
                switch target {
                case .milestone(let milestone):
                    services.projectService?.updateReminder(reminder, for: milestone)
                case .subtask(let subtask):
                    services.projectService?.updateReminder(reminder, for: subtask)
                }
            }
        }
    }

    private var projectHeader: some View {
        HStack {
            IOSPrototypeProgressRing(progress: project.progress)
            Text("\(Int(project.progress * 100))%")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IOSPrototypeProgressStyle.percentColor)
                .monospacedDigit()
            Spacer()
            if let reminder = project.reminder {
                IOSPersistentReminderSummary(
                    reminder: reminder,
                    dateFormatPattern: savedDateFormat,
                    language: effectiveLanguage
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var taskList: some View {
        let rows = taskRows
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                taskRowWithDropZones(
                    row,
                    index: index,
                    count: rows.count,
                    nextRow: index < rows.count - 1 ? rows[index + 1] : nil
                )
            }
        }
        .iosPrototypeCardSurface(cornerRadius: 14)
    }

    private var memoList: some View {
        let displayedMemos = displayOrderedMemos

        return VStack(spacing: IOSPersistentMemoReorderMetrics.cardSpacing) {
            ForEach(displayedMemos, id: \.memoId) { memo in
                memoCard(memo)
                    .modifier(IOSPersistentMemoCardDropModifier(
                        targetID: memo.memoId,
                        draggingMemoID: $draggingMemoID,
                        onDropEvent: markMemoDragDropEvent,
                        onDropExit: scheduleMemoDragExitFallback,
                        onUpdateDisplayOrder: updateMemoDisplayOrder(movingID:targetID:placement:),
                        onCommitDisplayOrder: commitMemoDisplayOrder
                    ))
            }
        }
        .animation(IOSPersistentMemoReorderMetrics.animation, value: displayedMemos.map(\.memoId))
    }

    private func milestoneRow(_ milestone: Milestone, highlightCorners: UIRectCorner) -> some View {
        IOSPersistentHighlightedRow(
            consume: coordinator.consumeHighlight,
            triggerID: highlightID(for: milestone),
            highlightCorners: highlightCorners
        ) { isHighlighted in
            taskRowContent {
                milestoneCompletionControl(milestone, isHighlighted: isHighlighted)
                milestoneTitleControl(milestone, isHighlighted: isHighlighted)

                reminderControl(milestone.reminder, isCompleted: milestone.score >= 1, isHighlighted: isHighlighted) {
                    reminderEditorTarget = .milestone(milestone)
                }
            }
        }
        .contentShape(Rectangle())
        .onDrag {
            draggingTaskItem = .milestone(milestone.milestoneId)
            return NSItemProvider(object: IOSPersistentTaskDragItem.milestone(milestone.milestoneId).providerValue as NSString)
        } preview: {
            taskRowContent {
                milestoneCompletionControl(milestone, isHighlighted: false)
                milestoneTitleControl(milestone, isHighlighted: false)
                reminderControl(milestone.reminder, isCompleted: milestone.score >= 1, isHighlighted: false) {}
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(width: 320)
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 48)
        }
        .contextMenu {
            if !project.isArchived {
                Button("编辑", systemImage: "pencil") {
                    beginEditing(milestone)
                }
                Button("新增子任务", systemImage: "list.bullet.below.rectangle") {
                    composerText = ""
                    session = .addSubtask(milestoneID: milestone.milestoneId)
                }
            }
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(milestone.title)
            }
            if !project.isArchived {
                Button("删除", systemImage: "trash", role: .destructive) {
                    services.projectService?.deleteMilestone(milestone)
                }
            }
        }
        .id(milestone.milestoneId)
    }

    private func subtaskRow(_ subtask: SubTask, milestone: Milestone, highlightCorners: UIRectCorner) -> some View {
        IOSPersistentHighlightedRow(
            consume: coordinator.consumeHighlight,
            triggerID: highlightID(for: subtask),
            highlightCorners: highlightCorners
        ) { isHighlighted in
            taskRowContent {
                subtaskCompletionControl(subtask, isHighlighted: isHighlighted)
                subtaskTitleControl(subtask, milestone: milestone, isHighlighted: isHighlighted)

                reminderControl(subtask.reminder, isCompleted: subtask.isCompleted, isHighlighted: isHighlighted) {
                    reminderEditorTarget = .subtask(subtask)
                }
            }
            .padding(.leading, 32)
        }
        .contentShape(Rectangle())
        .onDrag {
            draggingTaskItem = .subtask(subtask.taskId)
            return NSItemProvider(object: IOSPersistentTaskDragItem.subtask(subtask.taskId).providerValue as NSString)
        } preview: {
            taskRowContent {
                subtaskCompletionControl(subtask, isHighlighted: false)
                subtaskTitleControl(subtask, milestone: milestone, isHighlighted: false)
                reminderControl(subtask.reminder, isCompleted: subtask.isCompleted, isHighlighted: false) {}
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(width: 320)
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 76)
        }
        .contextMenu {
            if !project.isArchived {
                Button("编辑", systemImage: "pencil") {
                    beginEditing(subtask, milestone: milestone)
                }
            }
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(subtask.title)
            }
            if !project.isArchived {
                Button("删除", systemImage: "trash", role: .destructive) {
                    services.projectService?.deleteSubTask(subtask)
                }
            }
        }
        .id(subtask.taskId)
    }

    private func memoCard(_ memo: Memo) -> some View {
        memoCardContent(memo)
        .contentShape(Rectangle())
        .onTapGesture {
            iosMemoReorderLog("tap memo=\(memo.memoId) dragging=\(draggingMemoID?.uuidString ?? "nil")")
            if !project.isArchived {
                beginEditing(memo)
            }
        }
        .iosPrototypeSearchOutlineHighlight(
            consume: coordinator.consumeHighlight,
            triggerID: highlightID(for: memo)
        )
        .onDrag {
            draggingMemoID = memo.memoId
            memoDisplayOrderOverride = nil
            let sessionID = UUID()
            memoDragSessionID = sessionID
            memoDragSessionSawDropEvent = false
            iosMemoReorderLog("drag start memo=\(memo.memoId) session=\(sessionID)")
            scheduleMemoDragFallbackReset(memoID: memo.memoId, sessionID: sessionID)
            return NSItemProvider(object: "memo:\(memo.memoId.uuidString)" as NSString)
        } preview: {
            memoCardContent(memo)
                .frame(width: 320)
        }
        .contextMenu {
            if !project.isArchived {
                Button("编辑", systemImage: "pencil") {
                    beginEditing(memo)
                }
            }
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(memo.content)
            }
            if !project.isArchived {
                Button("删除", systemImage: "trash", role: .destructive) {
                    services.projectService?.deleteMemo(memo)
                }
            }
        }
        .id(memo.memoId)
    }

    private func memoCardContent(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(AppDateFormatter.string(from: memo.createdAt, pattern: savedDateFormat))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(memo.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .iosPrototypeCardSurface(cornerRadius: 14)
    }

    private func taskRowContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func taskRowWithDropZones(
        _ row: IOSPersistentTaskRow,
        index: Int,
        count: Int,
        nextRow: IOSPersistentTaskRow?
    ) -> some View {
        let zones = taskDropZones(for: row, index: index, nextRow: nextRow)

        switch row {
        case let .milestone(milestone):
            milestoneRow(
                milestone,
                highlightCorners: highlightCorners(for: index, count: count)
            )
            .overlay(alignment: .top) {
                if let topZone = zones.top {
                    taskDropZoneOverlay(topZone, edge: .top)
                }
            }
            .overlay(alignment: .bottom) {
                if let bottomZone = zones.bottom {
                    taskDropZoneOverlay(bottomZone, edge: .bottom)
                }
            }
        case let .subtask(subtask, milestone):
            subtaskRow(
                subtask,
                milestone: milestone,
                highlightCorners: highlightCorners(for: index, count: count)
            )
            .overlay(alignment: .top) {
                if let topZone = zones.top {
                    taskDropZoneOverlay(topZone, edge: .top)
                }
            }
            .overlay(alignment: .bottom) {
                if let bottomZone = zones.bottom {
                    taskDropZoneOverlay(bottomZone, edge: .bottom)
                }
            }
        }
    }

    private func taskDropZoneOverlay(_ zone: IOSPersistentTaskDropZone, edge: IOSPersistentDropSeparatorEdge) -> some View {
        IOSPersistentReorderDropSeparator(
            isActive: taskDropTarget == IOSPersistentDropIndicator(id: zone.target.id, placement: zone.placement),
            edge: edge
        )
            .onDrop(
                of: [.text],
                delegate: IOSPersistentTaskDropDelegate(
                    target: zone.target,
                    placement: zone.placement,
                    draggingTaskItem: $draggingTaskItem,
                    dropTarget: $taskDropTarget,
                    onMove: moveTask(_:to:placement:)
                )
            )
    }

    private func taskDropZones(
        for row: IOSPersistentTaskRow,
        index: Int,
        nextRow: IOSPersistentTaskRow?
    ) -> IOSPersistentTaskDropZones {
        guard let draggingTaskItem else {
            return .empty
        }

        switch draggingTaskItem {
        case .milestone:
            return milestoneDropZones(for: row, index: index, nextRow: nextRow)
        case .subtask:
            return subtaskDropZones(for: row, nextRow: nextRow)
        }
    }

    private func milestoneDropZones(
        for row: IOSPersistentTaskRow,
        index: Int,
        nextRow: IOSPersistentTaskRow?
    ) -> IOSPersistentTaskDropZones {
        let top: IOSPersistentTaskDropZone?
        if index == 0, case let .milestone(milestone) = row {
            top = IOSPersistentTaskDropZone(target: .milestone(milestone.milestoneId), placement: .before)
        } else {
            top = nil
        }

        guard isLastVisibleRowInMilestoneGroup(row, nextRow: nextRow) else {
            return IOSPersistentTaskDropZones(top: top, bottom: nil)
        }

        let bottom: IOSPersistentTaskDropZone?
        if case let .milestone(nextMilestone)? = nextRow {
            bottom = IOSPersistentTaskDropZone(target: .milestone(nextMilestone.milestoneId), placement: .before)
        } else if let milestoneID = row.milestoneID {
            bottom = IOSPersistentTaskDropZone(target: .milestone(milestoneID), placement: .after)
        } else {
            bottom = nil
        }
        return IOSPersistentTaskDropZones(top: top, bottom: bottom)
    }

    private func subtaskDropZones(
        for row: IOSPersistentTaskRow,
        nextRow: IOSPersistentTaskRow?
    ) -> IOSPersistentTaskDropZones {
        let bottom: IOSPersistentTaskDropZone?
        switch row {
        case let .milestone(milestone):
            if case let .subtask(subtask, nextMilestone)? = nextRow,
               nextMilestone.milestoneId == milestone.milestoneId {
                bottom = IOSPersistentTaskDropZone(
                    target: .subtask(parentID: milestone.milestoneId, subtaskID: subtask.taskId),
                    placement: .before
                )
            } else {
                bottom = IOSPersistentTaskDropZone(target: .milestone(milestone.milestoneId), placement: .end)
            }
        case let .subtask(_, milestone):
            if case let .subtask(nextSubtask, nextMilestone)? = nextRow,
               nextMilestone.milestoneId == milestone.milestoneId {
                bottom = IOSPersistentTaskDropZone(
                    target: .subtask(parentID: milestone.milestoneId, subtaskID: nextSubtask.taskId),
                    placement: .before
                )
            } else {
                bottom = IOSPersistentTaskDropZone(target: .milestone(milestone.milestoneId), placement: .end)
            }
        }
        return IOSPersistentTaskDropZones(top: nil, bottom: bottom)
    }

    private func isLastVisibleRowInMilestoneGroup(_ row: IOSPersistentTaskRow, nextRow: IOSPersistentTaskRow?) -> Bool {
        guard let nextRow else { return true }
        return row.milestoneID != nextRow.milestoneID
    }

    private func titleContent(_ title: String, reminder: Reminder?, isCompleted: Bool, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                if let reminder {
                    Text(reminder.displaySummary(
                        dateFormatPattern: savedDateFormat,
                        language: effectiveLanguage
                    ))
                        .font(.caption2)
                        .foregroundStyle(isHighlighted ? .white : reminderSummaryColor(for: reminder, isCompleted: isCompleted))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func milestoneCompletionControl(_ milestone: Milestone, isHighlighted: Bool) -> some View {
        let icon = milestone.score >= 1 ? "checkmark.circle.fill" : "circle"
        let color = isHighlighted ? Color.white : milestone.score >= 1 ? Color.accentColor : Color.secondary
        if project.isArchived {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
        } else {
            Button {
                services.projectService?.toggleMilestoneComplete(milestone)
            } label: {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func milestoneTitleControl(_ milestone: Milestone, isHighlighted: Bool) -> some View {
        if project.isArchived {
            titleContent(milestone.title, reminder: milestone.reminder, isCompleted: milestone.score >= 1, isHighlighted: isHighlighted)
        } else {
            Button {
                beginEditing(milestone)
            } label: {
                titleContent(milestone.title, reminder: milestone.reminder, isCompleted: milestone.score >= 1, isHighlighted: isHighlighted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func subtaskCompletionControl(_ subtask: SubTask, isHighlighted: Bool) -> some View {
        let icon = subtask.isCompleted ? "checkmark.circle.fill" : "circle"
        let color = isHighlighted ? Color.white : subtask.isCompleted ? Color.accentColor : Color.secondary
        if project.isArchived {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
        } else {
            Button {
                services.projectService?.toggleSubTaskComplete(subtask)
            } label: {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func subtaskTitleControl(_ subtask: SubTask, milestone: Milestone, isHighlighted: Bool) -> some View {
        if project.isArchived {
            titleContent(subtask.title, reminder: subtask.reminder, isCompleted: subtask.isCompleted, isHighlighted: isHighlighted)
        } else {
            Button {
                beginEditing(subtask, milestone: milestone)
            } label: {
                titleContent(subtask.title, reminder: subtask.reminder, isCompleted: subtask.isCompleted, isHighlighted: isHighlighted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func reminderControl(
        _ reminder: Reminder?,
        isCompleted: Bool,
        isHighlighted: Bool,
        onEdit: @escaping () -> Void
    ) -> some View {
        let icon = reminder == nil ? "alarm" : "alarm.fill"
        let color = reminderControlColor(reminder, isCompleted: isCompleted, isHighlighted: isHighlighted)
        if project.isArchived {
            Image(systemName: icon)
                .foregroundStyle(color)
        } else {
            Button(action: onEdit) {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
        }
    }

    private func reminderControlColor(_ reminder: Reminder?, isCompleted: Bool, isHighlighted: Bool) -> AnyShapeStyle {
        if isHighlighted {
            return AnyShapeStyle(.white)
        }
        if reminder != nil, isCompleted {
            return AnyShapeStyle(.secondary)
        }
        return reminder?.displayFireDate
            .map { AnyShapeStyle(IOSPrototypeReminderStyle.color(for: $0)) }
            ?? AnyShapeStyle(.tertiary)
    }

    private var detailFooter: some View {
        Group {
            if project.isArchived {
                IOSPrototypeDetailTabBar(selection: $coordinator.detailTab)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    if session == .idle {
                        IOSPrototypeDetailTabBar(selection: $coordinator.detailTab)
                    } else {
                        IOSPrototypeDetailComposer(text: $composerText, placeholder: composerPlaceholder)
                    }

                    IOSPrototypeDetachedActionButton(symbol: session == .idle ? "plus" : "paperplane.fill") {
                        if session == .idle {
                            composerText = ""
                            session = coordinator.detailTab == .tasks ? .addMilestone : .addMemo
                        } else {
                            saveAndClose()
                        }
                    }
                }
            }
        }
    }

    private var composerPlaceholder: LocalizedStringKey {
        switch session {
        case .addMilestone: "新增里程碑"
        case .addSubtask: "新增子任务"
        case .addMemo: "新增备忘录"
        case .editMilestone: "里程碑名称"
        case .editSubtask: "子任务名称"
        case .editMemo: "备忘录内容"
        case .idle: ""
        }
    }

    private var sortedMilestones: [Milestone] {
        project.milestones
            .filter { !project.hideCompleted || !$0.isCompleted }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func visibleSubtasks(for milestone: Milestone) -> [SubTask] {
        milestone.subtasks
            .filter { !project.hideCompleted || !$0.isCompleted }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private var taskRows: [IOSPersistentTaskRow] {
        sortedMilestones.flatMap { milestone -> [IOSPersistentTaskRow] in
            [.milestone(milestone)] + visibleSubtasks(for: milestone).map { .subtask($0, milestone: milestone) }
        }
    }

    private func highlightCorners(for index: Int, count: Int) -> UIRectCorner {
        var corners: UIRectCorner = []
        if index == 0 {
            corners.formUnion([.topLeft, .topRight])
        }
        if index == count - 1 {
            corners.formUnion([.bottomLeft, .bottomRight])
        }
        return corners
    }

    private var sortedMemos: [Memo] {
        project.memos.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.createdAt > $1.createdAt
            }
            return $0.orderIndex < $1.orderIndex
        }
    }

    private var displayOrderedMemos: [Memo] {
        guard let memoDisplayOrderOverride else {
            return sortedMemos
        }

        let memoIDs = Set(sortedMemos.map(\.memoId))
        guard memoDisplayOrderOverride.count == sortedMemos.count,
              Set(memoDisplayOrderOverride) == memoIDs
        else {
            return sortedMemos
        }

        var memosByID = Dictionary(uniqueKeysWithValues: sortedMemos.map { ($0.memoId, $0) })
        return memoDisplayOrderOverride.compactMap { memosByID.removeValue(forKey: $0) }
    }

    private var savedDateFormat: String? {
        settingsRecords.first?.dateFormat
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    private func reminderSummaryColor(for reminder: Reminder, isCompleted: Bool) -> Color {
        if isCompleted {
            return .secondary
        }
        return reminder.displayFireDate.map { IOSPrototypeReminderStyle.color(for: $0) } ?? .gray
    }

    private var accentColor: Color {
        project.progress >= 1 ? ViabarColor.success : Color(hex: project.accentColor)
    }

    private func moveTask(
        _ item: IOSPersistentTaskDragItem,
        to target: IOSPersistentTaskDropTarget,
        placement: ReorderPlacement
    ) {
        guard !project.isArchived else { return }
        switch (item, target) {
        case let (.milestone(movingID), .milestone(targetID)):
            guard movingID != targetID else { return }
            services.projectService?.reorderMilestones(in: project, movingID: movingID, targetID: targetID, placement: placement)
        case let (.subtask(movingID), .subtask(parentID, targetID)):
            guard movingID != targetID else { return }
            services.projectService?.moveSubTask(movingID, to: parentID, targetSubTaskID: targetID, placement: placement)
        case let (.subtask(movingID), .milestone(targetID)):
            services.projectService?.moveSubTask(movingID, to: targetID, targetSubTaskID: nil, placement: .end)
        case (.milestone, .subtask):
            return
        }
    }

    private func updateMemoDisplayOrder(movingID: UUID, targetID: UUID, placement: ReorderPlacement) {
        guard !project.isArchived, movingID != targetID else { return }

        var memos = displayOrderedMemos
        guard let sourceIndex = memos.firstIndex(where: { $0.memoId == movingID }),
              let targetIndex = memos.firstIndex(where: { $0.memoId == targetID })
        else {
            iosMemoReorderLog("update skipped reason=missing index moving=\(movingID) target=\(targetID) ids=\(memos.map(\.memoId.uuidString))")
            return
        }

        let destination = memoInsertionIndex(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            placement: placement,
            count: memos.count
        )
        guard sourceIndex != destination else {
            iosMemoReorderLog("update skipped reason=same destination source=\(sourceIndex) target=\(targetIndex) destination=\(destination) placement=\(placement)")
            return
        }

        let movingMemo = memos.remove(at: sourceIndex)
        memos.insert(movingMemo, at: destination)
        let reorderedIDs = memos.map(\.memoId)
        guard memoDisplayOrderOverride != reorderedIDs else {
            iosMemoReorderLog("update skipped reason=order unchanged")
            return
        }

        iosMemoReorderLog("update order source=\(sourceIndex) target=\(targetIndex) destination=\(destination) placement=\(placement) ids=\(reorderedIDs.map(\.uuidString))")
        withAnimation(IOSPersistentMemoReorderMetrics.animation) {
            memoDisplayOrderOverride = reorderedIDs
        }
    }

    private func commitMemoDisplayOrder() {
        guard !project.isArchived else {
            iosMemoReorderLog("commit skipped reason=archived")
            resetMemoDragState()
            return
        }

        let finalMemos = displayOrderedMemos
        iosMemoReorderLog("commit begin final=\(finalMemos.map(\.memoId.uuidString))")
        resetMemoDragState(restoresDisplayOrder: false)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            for (index, memo) in finalMemos.enumerated() where memo.orderIndex != index {
                memo.orderIndex = index
            }
        }
        services.projectService?.save()
        memoDisplayOrderOverride = nil
        iosMemoReorderLog("commit end")
    }

    private func memoInsertionIndex(
        sourceIndex: Int,
        targetIndex: Int,
        placement: ReorderPlacement,
        count: Int
    ) -> Int {
        var insertionIndex = targetIndex
        if sourceIndex < targetIndex {
            insertionIndex -= 1
        }
        if placement == .after {
            insertionIndex += 1
        }
        return min(max(insertionIndex, 0), count - 1)
    }

    private func markMemoDragDropEvent() {
        memoDragSessionSawDropEvent = true
        memoDragEventCounter += 1
        iosMemoReorderLog("drop event counter=\(memoDragEventCounter) dragging=\(draggingMemoID?.uuidString ?? "nil")")
    }

    private func scheduleMemoDragFallbackReset(memoID: UUID, sessionID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard memoDragSessionID == sessionID,
                  draggingMemoID == memoID,
                  !memoDragSessionSawDropEvent
            else { return }

            iosMemoReorderLog("fallback reset orphan drag memo=\(memoID) session=\(sessionID)")
            resetMemoDragState()
        }
    }

    private func scheduleMemoDragExitFallback() {
        let counter = memoDragEventCounter
        let memoID = draggingMemoID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard draggingMemoID == memoID,
                  draggingMemoID != nil,
                  memoDragEventCounter == counter
            else { return }

            if memoDisplayOrderOverride != nil {
                iosMemoReorderLog("exit fallback commit memo=\(memoID?.uuidString ?? "nil") counter=\(counter)")
                commitMemoDisplayOrder()
            } else {
                iosMemoReorderLog("exit fallback reset memo=\(memoID?.uuidString ?? "nil") counter=\(counter)")
                resetMemoDragState()
            }
        }
    }

    private func resetMemoDragState(restoresDisplayOrder: Bool = true) {
        iosMemoReorderLog("reset draggingBefore=\(draggingMemoID?.uuidString ?? "nil") restoresDisplayOrder=\(restoresDisplayOrder)")
        draggingMemoID = nil
        memoDragSessionID = nil
        memoDragSessionSawDropEvent = false
        memoDragEventCounter += 1
        if restoresDisplayOrder {
            memoDisplayOrderOverride = nil
        }
    }

    private func toggleArchive() {
        guard let projectService = services.projectService else { return }
        if project.isArchived {
            projectService.unarchiveProject(project)
            return
        }
        isArchiveFolderPickerPresented = true
    }

    private func beginEditing(_ milestone: Milestone) {
        composerText = milestone.title
        session = .editMilestone(milestoneID: milestone.milestoneId)
    }

    private func beginEditing(_ subtask: SubTask, milestone: Milestone) {
        composerText = subtask.title
        session = .editSubtask(milestoneID: milestone.milestoneId, subtaskID: subtask.taskId)
    }

    private func beginEditing(_ memo: Memo) {
        composerText = memo.content
        session = .editMemo(memoID: memo.memoId)
    }

    private func saveAndClose() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch session {
        case .idle:
            return
        case .addMilestone:
            if !text.isEmpty {
                services.projectService?.addMilestone(to: project, title: text)
            }
        case let .addSubtask(milestoneID):
            if !text.isEmpty, let milestone = milestone(id: milestoneID) {
                services.projectService?.addSubTask(to: milestone, title: text)
            }
        case .addMemo:
            if !text.isEmpty {
                services.projectService?.addMemo(to: project, content: text)
            }
        case let .editMilestone(milestoneID):
            guard let milestone = milestone(id: milestoneID) else { break }
            if text.isEmpty {
                services.projectService?.deleteMilestone(milestone)
            } else {
                milestone.title = text
                services.projectService?.updateProject(project)
            }
        case let .editSubtask(milestoneID, subtaskID):
            guard let subtask = milestone(id: milestoneID)?.subtasks.first(where: { $0.taskId == subtaskID }) else { break }
            if text.isEmpty {
                services.projectService?.deleteSubTask(subtask)
            } else {
                subtask.title = text
                services.projectService?.updateProject(project)
            }
        case let .editMemo(memoID):
            guard let memo = project.memos.first(where: { $0.memoId == memoID }) else { break }
            if text.isEmpty {
                services.projectService?.deleteMemo(memo)
            } else {
                memo.content = text
                services.projectService?.updateProject(project)
            }
        }
        closeComposer()
    }

    private func closeComposer() {
        composerText = ""
        session = .idle
        dismissIOSPrototypeKeyboard()
    }

    private func milestone(id: UUID) -> Milestone? {
        project.milestones.first { $0.milestoneId == id }
    }

    private func highlightID(for milestone: Milestone) -> UUID? {
        guard let request = coordinator.navigationRequest,
              request.projectID == project.projectId,
              request.destination == .milestone(milestone.milestoneId)
        else { return nil }
        return request.id
    }

    private func highlightID(for subtask: SubTask) -> UUID? {
        guard let request = coordinator.navigationRequest,
              request.projectID == project.projectId,
              case let .subTask(_, subtaskID) = request.destination,
              subtaskID == subtask.taskId
        else { return nil }
        return request.id
    }

    private func highlightID(for memo: Memo) -> UUID? {
        guard let request = coordinator.navigationRequest,
              request.projectID == project.projectId,
              request.destination == .memo(memo.memoId)
        else { return nil }
        return request.id
    }

    private func scrollToNavigationTarget(using proxy: ScrollViewProxy) {
        guard let request = coordinator.navigationRequest, request.projectID == project.projectId else { return }
        let targetID: UUID?
        switch request.destination {
        case .project:
            targetID = nil
        case let .milestone(milestoneID):
            targetID = milestoneID
        case let .subTask(_, subtaskID):
            targetID = subtaskID
        case let .memo(memoID):
            targetID = memoID
        }
        guard let targetID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }
}

private enum IOSPersistentTaskRow: Identifiable {
    case milestone(Milestone)
    case subtask(SubTask, milestone: Milestone)

    var id: UUID {
        switch self {
        case let .milestone(milestone):
            return milestone.milestoneId
        case let .subtask(subtask, _):
            return subtask.taskId
        }
    }

    var milestoneID: UUID? {
        switch self {
        case let .milestone(milestone):
            return milestone.milestoneId
        case let .subtask(_, milestone):
            return milestone.milestoneId
        }
    }
}

private enum IOSPersistentTaskDragItem: Equatable {
    case milestone(UUID)
    case subtask(UUID)

    var providerValue: String {
        switch self {
        case let .milestone(id):
            return "milestone:\(id.uuidString)"
        case let .subtask(id):
            return "subtask:\(id.uuidString)"
        }
    }
}

private enum IOSPersistentTaskDropTarget {
    case milestone(UUID)
    case subtask(parentID: UUID, subtaskID: UUID)

    var id: UUID {
        switch self {
        case let .milestone(id):
            return id
        case let .subtask(_, subtaskID):
            return subtaskID
        }
    }
}

private struct IOSPersistentTaskDropZone {
    let target: IOSPersistentTaskDropTarget
    let placement: ReorderPlacement
}

private struct IOSPersistentTaskDropZones {
    let top: IOSPersistentTaskDropZone?
    let bottom: IOSPersistentTaskDropZone?

    static let empty = IOSPersistentTaskDropZones(top: nil, bottom: nil)
}

private struct IOSPersistentDropIndicator: Equatable {
    let id: UUID
    let placement: ReorderPlacement
}

private struct IOSPersistentTaskDropDelegate: DropDelegate {
    let target: IOSPersistentTaskDropTarget
    let placement: ReorderPlacement
    @Binding var draggingTaskItem: IOSPersistentTaskDragItem?
    @Binding var dropTarget: IOSPersistentDropIndicator?
    let onMove: (IOSPersistentTaskDragItem, IOSPersistentTaskDropTarget, ReorderPlacement) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggingTaskItem else { return false }
        switch (draggingTaskItem, target) {
        case (.milestone, .milestone):
            return true
        case (.milestone, .subtask):
            return false
        case (.subtask, _):
            return true
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
            draggingTaskItem = nil
            dropTarget = nil
        }
        guard let draggingTaskItem else { return false }
        onMove(draggingTaskItem, target, placement)
        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        dropTarget = IOSPersistentDropIndicator(id: target.id, placement: placement)
    }
}

private enum IOSPersistentMemoReorderMetrics {
    static let cardSpacing: CGFloat = 8
    static let animation: Animation = .easeInOut(duration: 0.12)
}

private struct IOSPersistentMemoCardDropModifier: ViewModifier {
    let targetID: UUID
    @Binding var draggingMemoID: UUID?
    let onDropEvent: () -> Void
    let onDropExit: () -> Void
    let onUpdateDisplayOrder: (UUID, UUID, ReorderPlacement) -> Void
    let onCommitDisplayOrder: () -> Void

    private var allowsMemoDropHitTesting: Bool {
        draggingMemoID != nil && draggingMemoID != targetID
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        memoDropZone(height: proxy.size.height / 2, placement: .before)
                        memoDropZone(height: proxy.size.height / 2, placement: .after)
                    }
                }
                .allowsHitTesting(allowsMemoDropHitTesting)
            }
            .onChange(of: allowsMemoDropHitTesting) { _, newValue in
                iosMemoReorderLog("drop overlay target=\(targetID) hitTesting=\(newValue) dragging=\(draggingMemoID?.uuidString ?? "nil")")
            }
    }

    private func memoDropZone(height: CGFloat, placement: ReorderPlacement) -> some View {
        Color.primary.opacity(0.001)
            .frame(maxWidth: .infinity)
            .frame(height: max(height, 1))
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: IOSPersistentMemoCardDropDelegate(
                    targetID: targetID,
                    placement: placement,
                    draggingMemoID: $draggingMemoID,
                    onDropEvent: onDropEvent,
                    onDropExit: onDropExit,
                    onUpdateDisplayOrder: onUpdateDisplayOrder,
                    onCommitDisplayOrder: onCommitDisplayOrder
                )
            )
    }
}

private struct IOSPersistentMemoCardDropDelegate: DropDelegate {
    let targetID: UUID
    let placement: ReorderPlacement
    @Binding var draggingMemoID: UUID?
    let onDropEvent: () -> Void
    let onDropExit: () -> Void
    let onUpdateDisplayOrder: (UUID, UUID, ReorderPlacement) -> Void
    let onCommitDisplayOrder: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        onDropEvent()
        let isValid = draggingMemoID != nil && draggingMemoID != targetID
        iosMemoReorderLog("validate=\(isValid) target=\(targetID) placement=\(placement) dragging=\(draggingMemoID?.uuidString ?? "nil")")
        return isValid
    }

    func dropEntered(info: DropInfo) {
        iosMemoReorderLog("dropEntered target=\(targetID) placement=\(placement) dragging=\(draggingMemoID?.uuidString ?? "nil")")
        updateDisplayOrder()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        iosMemoReorderLog("dropUpdated target=\(targetID) placement=\(placement) dragging=\(draggingMemoID?.uuidString ?? "nil")")
        updateDisplayOrder()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onDropEvent()
        iosMemoReorderLog("dropExited target=\(targetID) placement=\(placement) dragging=\(draggingMemoID?.uuidString ?? "nil")")
        onDropExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropEvent()
        iosMemoReorderLog("performDrop target=\(targetID) placement=\(placement) dragging=\(draggingMemoID?.uuidString ?? "nil")")
        guard draggingMemoID != nil else { return false }
        onCommitDisplayOrder()
        return true
    }

    private func updateDisplayOrder() {
        onDropEvent()
        guard let draggingMemoID, draggingMemoID != targetID else {
            iosMemoReorderLog("delegate update skipped target=\(targetID) placement=\(placement) dragging=\(draggingMemoID?.uuidString ?? "nil")")
            return
        }
        onUpdateDisplayOrder(draggingMemoID, targetID, placement)
    }
}

private enum IOSPersistentDropSeparatorEdge {
    case center
    case top
    case bottom
}

private struct IOSPersistentReorderDropSeparator: View {
    let isActive: Bool
    var edge: IOSPersistentDropSeparatorEdge = .center

    var body: some View {
        ZStack(alignment: alignment) {
            Color.primary.opacity(0.001)
            if isActive {
                Rectangle()
                    .fill(Color.blue)
                    .frame(height: 2)
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: -3)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .contentShape(Rectangle())
    }

    private var alignment: Alignment {
        switch edge {
        case .center:
            return .center
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
}

private struct IOSPersistentHighlightedRow<Content: View>: View {
    let consume: (UUID?) -> Bool
    let triggerID: UUID?
    let highlightCorners: UIRectCorner
    @ViewBuilder var content: (Bool) -> Content

    @State private var isHighlighted = false

    var body: some View {
        content(isHighlighted)
            .background {
                IOSPersistentHighlightShape(corners: highlightCorners, radius: 14)
                    .fill(isHighlighted ? Color.orange : .clear)
            }
            .task(id: triggerID) {
                guard consume(triggerID) else {
                    isHighlighted = false
                    return
                }
                isHighlighted = true
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    isHighlighted = false
                }
            }
    }
}

private struct IOSPersistentHighlightShape: Shape {
    let corners: UIRectCorner
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(
            UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath
        )
    }
}
