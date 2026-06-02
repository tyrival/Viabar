import SwiftUI

private enum IOSPrototypeDetailSession: Equatable {
    case idle
    case addMilestone
    case addSubtask(milestoneID: UUID)
    case addMemo
    case editMilestone(milestoneID: UUID)
    case editSubtask(milestoneID: UUID, subtaskID: UUID)
    case editMemo(memoID: UUID)
}

struct IOSPrototypeProjectDetailView: View {
    @Bindable var store: IOSPrototypeStore
    let projectID: UUID

    @State private var session: IOSPrototypeDetailSession = .idle
    @State private var composerText = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            if let project {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            projectHeader(project)

                            switch store.detailTab {
                            case .tasks:
                                IOSPrototypeTasksView(
                                    store: store,
                                    project: project,
                                    navigationRequest: store.navigationRequest,
                                    onEditMilestone: beginEditingMilestone,
                                    onEditSubtask: beginEditingSubtask,
                                    onAddSubtask: beginAddingSubtask
                                )
                            case .memos:
                                IOSPrototypeMemosView(
                                    store: store,
                                    project: project,
                                    navigationRequest: store.navigationRequest,
                                    onEditMemo: beginEditingMemo
                                )
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
                    .onChange(of: store.navigationRequest?.id) { _, _ in
                        scrollToNavigationTarget(using: proxy)
                    }
                }
            } else {
                IOSPlaceholderView(symbol: "exclamationmark.triangle", title: "项目不存在")
            }

            detailFooter
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let project {
                    HStack(spacing: 7) {
                        Image(systemName: project.symbol)
                            .foregroundStyle(accentColor(project))
                        Text(project.title)
                            .font(.subheadline.weight(.semibold))
                        if project.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(ViabarColor.warning)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let project {
                    Menu {
                        Button(LocalizedStringKey(project.isFavorite ? "取消收藏" : "收藏"), systemImage: project.isFavorite ? "star.slash" : "star") {
                            store.toggleFavorite(project.id)
                        }
                        Button(LocalizedStringKey(project.isArchived ? "取消归档" : "归档"), systemImage: project.isArchived ? "arrow.uturn.backward" : "archivebox") {
                            if project.isArchived {
                                store.unarchive(project.id)
                            } else {
                                store.archive(project.id)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onChange(of: store.detailTab) { _, _ in
            closeComposer()
        }
    }

    @ViewBuilder
    private var detailFooter: some View {
        HStack(spacing: 10) {
            if session == .idle {
                IOSPrototypeDetailTabBar(selection: $store.detailTab)
            } else {
                IOSPrototypeDetailComposer(
                    text: $composerText,
                    placeholder: composerPlaceholder
                )
            }

            IOSPrototypeDetachedActionButton(symbol: session == .idle ? "plus" : "paperplane.fill") {
                if session == .idle {
                    beginAddingCurrentTab()
                } else {
                    saveAndCloseActiveSession()
                }
            }
        }
    }

    private var project: IOSPrototypeProject? {
        store.projects.first { $0.id == projectID }
    }

    private func projectHeader(_ project: IOSPrototypeProject) -> some View {
        HStack {
            IOSPrototypeProgressRing(progress: project.progress)
            Text("\(Int(project.progress * 100))%")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IOSPrototypeProgressStyle.percentColor)
                .monospacedDigit()
            Spacer()
            if let reminderDate = project.reminderDate {
                Label(reminderDate.formatted(date: .numeric, time: .shortened), systemImage: "alarm.fill")
                    .font(.caption)
                    .foregroundStyle(IOSPrototypeReminderStyle.color(for: reminderDate))
            }
        }
        .padding(.vertical, 4)
    }

    private func accentColor(_ project: IOSPrototypeProject) -> Color {
        project.progress >= 1 ? ViabarColor.success : Color(prototypeHex: project.accentHex)
    }

    private var composerPlaceholder: LocalizedStringKey {
        switch session {
        case .addMilestone:
            return "新增里程碑"
        case .addSubtask:
            return "新增子任务"
        case .addMemo:
            return "新增备忘录"
        case .editMilestone:
            return "里程碑名称"
        case .editSubtask:
            return "子任务名称"
        case .editMemo:
            return "备忘录内容"
        case .idle:
            return ""
        }
    }

    private func beginAddingCurrentTab() {
        composerText = ""
        session = store.detailTab == .tasks ? .addMilestone : .addMemo
    }

    private func beginAddingSubtask(_ milestoneID: UUID) {
        composerText = ""
        session = .addSubtask(milestoneID: milestoneID)
    }

    private func beginEditingMilestone(_ milestone: IOSPrototypeMilestone) {
        composerText = milestone.title
        session = .editMilestone(milestoneID: milestone.id)
    }

    private func beginEditingSubtask(_ milestoneID: UUID, _ subtask: IOSPrototypeSubTask) {
        composerText = subtask.title
        session = .editSubtask(milestoneID: milestoneID, subtaskID: subtask.id)
    }

    private func beginEditingMemo(_ memo: IOSPrototypeMemo) {
        composerText = memo.content
        session = .editMemo(memoID: memo.id)
    }

    private func saveAndCloseActiveSession() {
        let trimmedText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch session {
        case .idle:
            return
        case .addMilestone:
            store.addMilestone(to: projectID, title: trimmedText)
        case let .addSubtask(milestoneID):
            store.addSubtask(to: milestoneID, in: projectID, title: trimmedText)
        case .addMemo:
            store.addMemo(to: projectID, content: trimmedText)
        case let .editMilestone(milestoneID):
            if trimmedText.isEmpty {
                store.deleteMilestone(milestoneID, in: projectID)
            } else {
                store.renameMilestone(milestoneID, in: projectID, title: trimmedText)
            }
        case let .editSubtask(milestoneID, subtaskID):
            if trimmedText.isEmpty {
                store.deleteSubtask(subtaskID, milestoneID: milestoneID, in: projectID)
            } else {
                store.renameSubtask(subtaskID, milestoneID: milestoneID, in: projectID, title: trimmedText)
            }
        case let .editMemo(memoID):
            if trimmedText.isEmpty {
                store.deleteMemo(memoID, in: projectID)
            } else {
                store.renameMemo(memoID, in: projectID, content: trimmedText)
            }
        }
        closeComposer()
    }

    private func closeComposer() {
        composerText = ""
        session = .idle
        dismissIOSPrototypeKeyboard()
    }

    private func scrollToNavigationTarget(using proxy: ScrollViewProxy) {
        guard let request = store.navigationRequest, request.projectID == projectID else { return }
        let targetID: UUID?
        switch request.target {
        case .project:
            targetID = nil
        case let .milestone(milestoneID):
            targetID = milestoneID
        case let .subtask(_, subtaskID):
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

struct IOSPrototypeTasksView: View {
    @Bindable var store: IOSPrototypeStore
    let project: IOSPrototypeProject
    let navigationRequest: IOSPrototypeNavigationRequest?
    let onEditMilestone: (IOSPrototypeMilestone) -> Void
    let onEditSubtask: (UUID, IOSPrototypeSubTask) -> Void
    let onAddSubtask: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(project.milestones.sorted(by: { $0.orderIndex < $1.orderIndex })) { milestone in
                IOSPrototypeMilestoneRow(
                    store: store,
                    projectID: project.id,
                    milestone: milestone,
                    highlightRequestID: milestoneHighlightID(milestone.id),
                    onEdit: { onEditMilestone(milestone) },
                    onAddSubtask: onAddSubtask
                )

                ForEach(milestone.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex })) { subtask in
                    IOSPrototypeSubtaskRow(
                        store: store,
                        projectID: project.id,
                        milestoneID: milestone.id,
                        subtask: subtask,
                        highlightRequestID: subtaskHighlightID(subtask.id),
                        onEdit: { onEditSubtask(milestone.id, subtask) }
                    )
                }
            }
        }
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
    }

    private func milestoneHighlightID(_ milestoneID: UUID) -> UUID? {
        guard navigationRequest?.projectID == project.id,
              case let .some(.milestone(targetID)) = navigationRequest?.target,
              targetID == milestoneID
        else { return nil }
        return navigationRequest?.id
    }

    private func subtaskHighlightID(_ subtaskID: UUID) -> UUID? {
        guard navigationRequest?.projectID == project.id,
              case let .some(.subtask(_, targetID)) = navigationRequest?.target,
              targetID == subtaskID
        else { return nil }
        return navigationRequest?.id
    }
}

struct IOSPrototypeMilestoneRow: View {
    @Bindable var store: IOSPrototypeStore
    let projectID: UUID
    let milestone: IOSPrototypeMilestone
    let highlightRequestID: UUID?
    let onEdit: () -> Void
    let onAddSubtask: (UUID) -> Void

    @State private var isSearchHighlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            completionButton
            Button(action: onEdit) {
                HStack(spacing: 10) {
                titleContent
                Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            reminder
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSearchHighlighted ? Color.orange : .clear)
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 48)
        }
        .contextMenu {
            Button("新增子任务", systemImage: "list.bullet.below.rectangle") {
                onAddSubtask(milestone.id)
            }
            Divider()
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(milestone.title)
            }
            Button("删除", systemImage: "trash", role: .destructive) {
                store.deleteMilestone(milestone.id, in: projectID)
            }
        }
        .id(milestone.id)
        .task(id: highlightRequestID) {
            guard store.consumeNavigationHighlight(highlightRequestID) else {
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

    private var completionButton: some View {
        Button {
            store.toggleMilestone(milestone.id, in: projectID)
        } label: {
            Image(systemName: milestone.score >= 1 ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(milestone.score >= 1 ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var titleContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(milestone.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .strikethrough(milestone.score >= 1)
            if let reminderDate = milestone.reminderDate {
                Text(reminderDate.formatted(date: .numeric, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(IOSPrototypeReminderStyle.color(for: reminderDate))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var reminder: some View {
        if let reminderDate = milestone.reminderDate {
            Image(systemName: "alarm.fill")
                .foregroundStyle(IOSPrototypeReminderStyle.color(for: reminderDate))
        } else {
            Image(systemName: "alarm")
                .foregroundStyle(.tertiary)
        }
    }
}

struct IOSPrototypeSubtaskRow: View {
    @Bindable var store: IOSPrototypeStore
    let projectID: UUID
    let milestoneID: UUID
    let subtask: IOSPrototypeSubTask
    let highlightRequestID: UUID?
    let onEdit: () -> Void

    @State private var isSearchHighlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggleSubtask(subtask.id, milestoneID: milestoneID, in: projectID)
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(subtask.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(subtask.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .strikethrough(subtask.isCompleted)
                    if let reminderDate = subtask.reminderDate {
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
            .buttonStyle(.plain)
            if let reminderDate = subtask.reminderDate {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(IOSPrototypeReminderStyle.color(for: reminderDate))
            } else {
                Image(systemName: "alarm")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 46)
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSearchHighlighted ? Color.orange : .clear)
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 76)
        }
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(subtask.title)
            }
            Button("删除", systemImage: "trash", role: .destructive) {
                store.deleteSubtask(subtask.id, milestoneID: milestoneID, in: projectID)
            }
        }
        .id(subtask.id)
        .task(id: highlightRequestID) {
            guard store.consumeNavigationHighlight(highlightRequestID) else {
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
}

struct IOSPrototypeMemosView: View {
    @Bindable var store: IOSPrototypeStore
    let project: IOSPrototypeProject
    let navigationRequest: IOSPrototypeNavigationRequest?
    let onEditMemo: (IOSPrototypeMemo) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(project.memos.sorted(by: { $0.createdAt > $1.createdAt })) { memo in
                IOSPrototypeMemoCard(
                    store: store,
                    projectID: project.id,
                    memo: memo,
                    highlightRequestID: memoHighlightID(memo.id),
                    onEdit: { onEditMemo(memo) }
                )
            }
        }
    }

    private func memoHighlightID(_ memoID: UUID) -> UUID? {
        guard navigationRequest?.projectID == project.id,
              case let .some(.memo(targetID)) = navigationRequest?.target,
              targetID == memoID
        else { return nil }
        return navigationRequest?.id
    }
}

struct IOSPrototypeMemoCard: View {
    @Bindable var store: IOSPrototypeStore
    let projectID: UUID
    let memo: IOSPrototypeMemo
    let highlightRequestID: UUID?
    let onEdit: () -> Void

    var body: some View {
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
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .iosPrototypeSearchOutlineHighlight(store: store, triggerID: highlightRequestID)
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button("复制", systemImage: "doc.on.doc") {
                copyIOSPrototypeText(memo.content)
            }
            Button("删除", systemImage: "trash", role: .destructive) {
                store.deleteMemo(memo.id, in: projectID)
            }
        }
        .id(memo.id)
    }
}
