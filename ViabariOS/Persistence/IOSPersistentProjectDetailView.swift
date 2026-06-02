import SwiftUI

private enum IOSPersistentDetailSession: Equatable {
    case idle
    case addMilestone
    case addSubtask(milestoneID: UUID)
    case addMemo
    case editMilestone(milestoneID: UUID)
    case editSubtask(milestoneID: UUID, subtaskID: UUID)
    case editMemo(memoID: UUID)
}

struct IOSPersistentProjectDetailView: View {
    @Environment(ServiceContainer.self) private var services
    @Bindable var coordinator: IOSPersistenceCoordinator
    let project: Project

    @State private var session: IOSPersistentDetailSession = .idle
    @State private var composerText = ""

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
                            services.projectService?.updateProject(project)
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
    }

    private var projectHeader: some View {
        HStack {
            IOSPrototypeProgressRing(progress: project.progress)
            Text("\(Int(project.progress * 100))%")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IOSPrototypeProgressStyle.percentColor)
                .monospacedDigit()
            Spacer()
            if let reminderDate = project.reminder?.displayFireDate {
                Label(reminderDate.formatted(date: .numeric, time: .shortened), systemImage: "alarm.fill")
                    .font(.caption)
                    .foregroundStyle(IOSPrototypeReminderStyle.color(for: reminderDate))
            }
        }
        .padding(.vertical, 4)
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            ForEach(sortedMilestones, id: \.milestoneId) { milestone in
                milestoneRow(milestone)

                ForEach(visibleSubtasks(for: milestone), id: \.taskId) { subtask in
                    subtaskRow(subtask, milestone: milestone)
                }
            }
        }
        .iosPrototypeCardSurface(cornerRadius: 14)
    }

    private var memoList: some View {
        VStack(spacing: 10) {
            ForEach(sortedMemos, id: \.memoId) { memo in
                memoCard(memo)
            }
        }
    }

    private func milestoneRow(_ milestone: Milestone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            milestoneCompletionControl(milestone)
            milestoneTitleControl(milestone)

            reminderIcon(milestone.reminder)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .background {
            IOSPersistentRowHighlight(
                consume: coordinator.consumeHighlight,
                triggerID: highlightID(for: milestone)
            )
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 48)
        }
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(milestone.title)
            }
            if !project.isArchived {
                Button("新增子任务", systemImage: "list.bullet.below.rectangle") {
                    composerText = ""
                    session = .addSubtask(milestoneID: milestone.milestoneId)
                }
                Button("编辑", systemImage: "pencil") {
                    beginEditing(milestone)
                }
                Button("删除", systemImage: "trash", role: .destructive) {
                    services.projectService?.deleteMilestone(milestone)
                }
            }
        }
        .id(milestone.milestoneId)
    }

    private func subtaskRow(_ subtask: SubTask, milestone: Milestone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            subtaskCompletionControl(subtask)
            subtaskTitleControl(subtask, milestone: milestone)

            reminderIcon(subtask.reminder)
        }
        .padding(.leading, 46)
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .background {
            IOSPersistentRowHighlight(
                consume: coordinator.consumeHighlight,
                triggerID: highlightID(for: subtask)
            )
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 76)
        }
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(subtask.title)
            }
            if !project.isArchived {
                Button("编辑", systemImage: "pencil") {
                    beginEditing(subtask, milestone: milestone)
                }
                Button("删除", systemImage: "trash", role: .destructive) {
                    services.projectService?.deleteSubTask(subtask)
                }
            }
        }
        .id(subtask.taskId)
    }

    private func memoCard(_ memo: Memo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(memo.createdAt.formatted(date: .numeric, time: .shortened))
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
        .contentShape(Rectangle())
        .onTapGesture {
            if !project.isArchived {
                beginEditing(memo)
            }
        }
        .iosPrototypeSearchOutlineHighlight(
            consume: coordinator.consumeHighlight,
            triggerID: highlightID(for: memo)
        )
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(memo.content)
            }
            if !project.isArchived {
                Button("编辑", systemImage: "pencil") {
                    beginEditing(memo)
                }
                Button("删除", systemImage: "trash", role: .destructive) {
                    services.projectService?.deleteMemo(memo)
                }
            }
        }
        .id(memo.memoId)
    }

    private func titleContent(_ title: String, reminder: Reminder?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let reminderDate = reminder?.displayFireDate {
                    Text(reminderDate.formatted(date: .numeric, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(IOSPrototypeReminderStyle.color(for: reminderDate))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func milestoneCompletionControl(_ milestone: Milestone) -> some View {
        let icon = milestone.score >= 1 ? "checkmark.circle.fill" : "circle"
        let color = milestone.score >= 1 ? Color.accentColor : Color.secondary
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
    private func milestoneTitleControl(_ milestone: Milestone) -> some View {
        if project.isArchived {
            titleContent(milestone.title, reminder: milestone.reminder)
        } else {
            Button {
                beginEditing(milestone)
            } label: {
                titleContent(milestone.title, reminder: milestone.reminder)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func subtaskCompletionControl(_ subtask: SubTask) -> some View {
        let icon = subtask.isCompleted ? "checkmark.circle.fill" : "circle"
        let color = subtask.isCompleted ? Color.accentColor : Color.secondary
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
    private func subtaskTitleControl(_ subtask: SubTask, milestone: Milestone) -> some View {
        if project.isArchived {
            titleContent(subtask.title, reminder: subtask.reminder)
        } else {
            Button {
                beginEditing(subtask, milestone: milestone)
            } label: {
                titleContent(subtask.title, reminder: subtask.reminder)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func reminderIcon(_ reminder: Reminder?) -> some View {
        if let reminderDate = reminder?.displayFireDate {
            Image(systemName: "alarm.fill")
                .foregroundStyle(IOSPrototypeReminderStyle.color(for: reminderDate))
        } else {
            Image(systemName: "alarm")
                .foregroundStyle(.tertiary)
        }
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

    private var sortedMemos: [Memo] {
        project.memos.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.createdAt > $1.createdAt
            }
            return $0.orderIndex < $1.orderIndex
        }
    }

    private var accentColor: Color {
        project.progress >= 1 ? ViabarColor.success : Color(hex: project.accentColor)
    }

    private func toggleArchive() {
        guard let projectService = services.projectService else { return }
        if project.isArchived {
            projectService.unarchiveProject(project)
            return
        }
        let folder = projectService.fetchRootFolders().first
            ?? projectService.createArchiveFolder(name: "默认归档")
        projectService.archiveProject(project, to: folder)
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

private struct IOSPersistentRowHighlight: View {
    let consume: (UUID?) -> Bool
    let triggerID: UUID?

    @State private var isHighlighted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHighlighted ? Color.orange : .clear)
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
