import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct IOSPersistentOverviewView: View {
    @Environment(ServiceContainer.self) private var services
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @Query(sort: \NotificationScheduleEntry.fireDate) private var notificationScheduleEntries: [NotificationScheduleEntry]
    @Bindable var coordinator: IOSPersistenceCoordinator
    let projects: [Project]
    let archiveFolders: [ArchiveFolder]

    @State private var editingProject: Project?
    @State private var archivePickerProject: Project?
    @State private var projectPendingDeletionID: UUID?
    @State private var projectAwaitingFinalDeletionID: UUID?
    @State private var isSettingsPresented = false
    @State private var isProjectCreationPresented = false
    @State private var archiveRootFolderCreationTrigger: UUID?
    @State private var isArchiveComposerPresented = false
    @State private var weekTodoOffset: Int = 0
    @State private var weekDoneOffset: Int = 0
    @State private var monthDoneOffset: Int = -1
    @State private var copiedReportKind: OverviewReportSectionKind?
    @State private var draggingProjectID: UUID?
    @State private var projectDropTarget: IOSProjectDropTarget?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissIOSPrototypeKeyboard()
                }

            Group {
                switch coordinator.homeTab {
                case .overview:
                    overview
                case .reports:
                    reports
                case .archive:
                    IOSPersistentArchiveView(
                        coordinator: coordinator,
                        projects: projects,
                        archiveFolders: archiveFolders,
                        rootFolderCreationTrigger: archiveRootFolderCreationTrigger,
                        isComposerPresented: $isArchiveComposerPresented
                    )
                }
            }

            footer
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
                .zIndex(10)
        }
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $isSettingsPresented) {
            IOSPersistentSettingsView()
        }
        .sheet(isPresented: $isProjectCreationPresented) {
            IOSPersistentProjectCreationView()
        }
        .sheet(item: $editingProject) { project in
            IOSPersistentProjectCreationView(editingProject: project)
        }
        .sheet(item: $archivePickerProject) { project in
            IOSPersistentArchiveFolderPicker(
                folders: archiveFolders,
                currentFolderID: nil,
                actionTitle: "归档"
            ) { folder in
                services.projectService?.archiveProject(project, to: folder)
            }
        }
        .alert("删除项目？", isPresented: firstDeletionConfirmation) {
            Button("继续", role: .destructive) {
                projectAwaitingFinalDeletionID = projectPendingDeletionID
                projectPendingDeletionID = nil
            }
            Button("取消", role: .cancel) {
                projectPendingDeletionID = nil
            }
        } message: {
            if let project = pendingDeletionProject {
                Text("“\(project.title)”包含 \(project.milestones.count) 条任务和 \(project.memos.count) 条备忘录。删除项目后不可恢复。")
            }
        }
        .alert("再次确认删除项目", isPresented: finalDeletionConfirmation) {
            Button("确认删除", role: .destructive) {
                guard let projectAwaitingFinalDeletionID,
                      let project = projects.first(where: { $0.projectId == projectAwaitingFinalDeletionID })
                else { return }
                services.projectService?.deleteProject(project)
                self.projectAwaitingFinalDeletionID = nil
            }
            Button("取消", role: .cancel) {
                projectAwaitingFinalDeletionID = nil
            }
        } message: {
            Text("是否确认永久删除这个项目？")
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if !isArchiveComposerPresented {
                if coordinator.isSearchPresented {
                    IOSPersistentSearchView(
                        coordinator: coordinator,
                        projects: projects,
                        effectiveLanguage: effectiveLanguage
                    )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    HStack(spacing: 10) {
                        IOSPersistentSearchField(coordinator: coordinator)
                        IOSPrototypeDetachedActionButton(symbol: "xmark") {
                            withAnimation(.snappy(duration: 0.22)) {
                                coordinator.isSearchPresented = false
                                coordinator.searchText = ""
                            }
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        IOSPrototypeHomeTabBar(selection: $coordinator.homeTab)
                            .frame(maxWidth: .infinity)
                        if coordinator.homeTab == .archive {
                            IOSPrototypeDetachedActionButton(symbol: "folder.badge.plus") {
                                archiveRootFolderCreationTrigger = UUID()
                            }
                        } else {
                            IOSPrototypeDetachedActionButton(symbol: "magnifyingglass") {
                                withAnimation(.snappy(duration: 0.22)) {
                                    coordinator.isSearchPresented = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var overview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    IOSPrototypeCircularIconButton(symbol: "gearshape.fill") {
                        isSettingsPresented = true
                    }
                    Spacer()
                    IOSPrototypeCircularIconButton(symbol: "plus.app") {
                        isProjectCreationPresented = true
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 4)

                if !favoriteProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        IOSPrototypeSectionLabel(title: "星标项目")
                        projectList(favoriteProjects)
                    }
                }

                if !regularProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        IOSPrototypeSectionLabel(title: "其他项目")
                            .padding(.top, 4)
                        projectList(regularProjects)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 112)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func projectList(_ projects: [Project]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(projects.enumerated()), id: \.element.projectId) { index, project in
                projectDropSeparator(targetID: project.projectId, placement: .before)
                projectCardLink(project)
                if index == projects.count - 1 {
                    projectDropSeparator(targetID: project.projectId, placement: .after)
                }
            }
        }
    }

    private var reports: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("报告")
                        .font(.title3.weight(.bold))
                    Spacer()
                }
                .padding(.top, 14)
                .padding(.bottom, 4)

                ForEach(reportSections) { section in
                    IOSPersistentReportSectionView(
                        section: section,
                        weekTodoOffset: $weekTodoOffset,
                        weekDoneOffset: $weekDoneOffset,
                        monthDoneOffset: $monthDoneOffset,
                        showsCopiedTag: copiedReportKind == section.kind,
                        onCopy: { copy(section) },
                        onNavigate: navigateFromReport(project:destination:)
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 112)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func projectCardLink(_ project: Project) -> some View {
        IOSPersistentOverviewProjectCard(
            project: project,
            onEdit: { editingProject = project },
            onArchive: { archivePickerProject = project },
            onToggleFavorite: { services.projectService?.toggleFavorite(project) },
            onDelete: { projectPendingDeletionID = project.projectId }
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            coordinator.selectProject(project)
        }
        .onDrag {
            draggingProjectID = project.projectId
            return NSItemProvider(object: IOSProjectDragPayload.project(project.projectId).rawValue as NSString)
        } preview: {
            IOSPersistentOverviewProjectCard(
                project: project,
                onEdit: {},
                onArchive: {},
                onToggleFavorite: {},
                onDelete: {}
            )
            .frame(width: 320)
        }
    }

    private func projectDropSeparator(targetID: UUID, placement: ReorderPlacement) -> some View {
        IOSReorderDropSeparator(isActive: projectDropTarget == IOSProjectDropTarget(id: targetID, placement: placement))
            .onDrop(
                of: [.text],
                delegate: IOSProjectReorderDropDelegate(
                    targetID: targetID,
                    placement: placement,
                    draggingProjectID: $draggingProjectID,
                    dropTarget: $projectDropTarget,
                    onMove: moveProject(id:targetID:placement:)
                )
            )
    }

    private var activeProjects: [Project] {
        OverviewScope.visibleProjects(
            from: projects,
            storedValue: settingsRecords.first?.overviewScope
        )
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    private var reportSections: [OverviewReportSection] {
        OverviewReportBuilder.makeReport(
            projects: projects,
            scheduleEntries: notificationScheduleEntries,
            weekTodoOffset: weekTodoOffset,
            weekDoneOffset: weekDoneOffset,
            monthDoneOffset: monthDoneOffset,
            now: Date(),
            weekStartDay: WeekStartDaySettingsStore.value()
        )
    }

    private var favoriteProjects: [Project] {
        activeProjects.filter(\.isFavorite)
    }

    private var regularProjects: [Project] {
        activeProjects.filter { !$0.isFavorite }
    }

    private var pendingDeletionProject: Project? {
        guard let projectPendingDeletionID else { return nil }
        return projects.first { $0.projectId == projectPendingDeletionID }
    }

    private var firstDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { projectPendingDeletionID != nil },
            set: { if !$0 { projectPendingDeletionID = nil } }
        )
    }

    private var finalDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { projectAwaitingFinalDeletionID != nil },
            set: { if !$0 { projectAwaitingFinalDeletionID = nil } }
        )
    }

    private func copy(_ section: OverviewReportSection) {
        guard !section.copyText.isEmpty else { return }
        copyIOSPrototypeText(section.copyText)
        withAnimation(.easeInOut(duration: 0.12)) {
            copiedReportKind = section.kind
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                if copiedReportKind == section.kind {
                    copiedReportKind = nil
                }
            }
        }
    }

    private func navigateFromReport(project: Project, destination: GlobalSearchDestination) {
        if project.isArchived {
            coordinator.revealArchiveAncestors(for: project)
        }
        coordinator.navigate(to: GlobalSearchNavigationRequest(
            projectID: project.projectId,
            destination: destination
        ))
    }

    private func moveProject(id: UUID, targetID: UUID, placement: ReorderPlacement) {
        guard id != targetID else { return }
        services.projectService?.reorderActiveProject(movingID: id, targetID: targetID, placement: placement)
    }
}

private struct IOSPersistentReportSectionView: View {
    let section: OverviewReportSection
    @Binding var weekTodoOffset: Int
    @Binding var weekDoneOffset: Int
    @Binding var monthDoneOffset: Int
    let showsCopiedTag: Bool
    let onCopy: () -> Void
    let onNavigate: (Project, GlobalSearchDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                periodPicker

                Spacer()

                if showsCopiedTag {
                    Text("已复制")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.14), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(section.cards.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.blue))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(section.cards.isEmpty)
            }

            if section.cards.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            } else {
                ForEach(section.cards) { card in
                    IOSPersistentReportCardView(
                        card: card,
                        isTodo: section.kind == .weekTodo,
                        onNavigate: onNavigate
                    )
                }
            }
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch section.kind {
        case .weekTodo: return "暂无待办提醒"
        case .weekDone, .monthDone: return "暂无完成内容"
        }
    }

    @ViewBuilder
    private var periodPicker: some View {
        switch section.kind {
        case .weekTodo:
            Picker("", selection: $weekTodoOffset) {
                Text("本周待办").tag(0)
                Text("下周待办").tag(1)
            }
            .iosReportCapsulePicker()

        case .weekDone:
            Picker("", selection: $weekDoneOffset) {
                Text("本周完成").tag(0)
                Text("上周完成").tag(-1)
            }
            .iosReportCapsulePicker()

        case .monthDone:
            Picker("", selection: $monthDoneOffset) {
                Text("本月完成").tag(0)
                Text("上月完成").tag(-1)
            }
            .iosReportCapsulePicker()
        }
    }
}

private struct IOSReportCapsulePickerStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .tint(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 28)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                IOSPrototypeSurfaceStyle.cardBackground(for: colorScheme),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.58 : 0.22), lineWidth: 1)
            }
    }
}

private extension View {
    func iosReportCapsulePicker() -> some View {
        modifier(IOSReportCapsulePickerStyle())
    }
}

private struct IOSPersistentReportCardView: View {
    let card: OverviewReportProjectCard
    let isTodo: Bool
    let onNavigate: (Project, GlobalSearchDestination) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: card.project.sfSymbolName)
                    .foregroundStyle(Color(hex: card.project.accentColor))

                Text(card.project.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(Color.primary) : AnyShapeStyle(ViabarColor.primary))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if isTodo, let projectReminder = card.projectReminderDate {
                    reminderLabel(projectReminder, fontSize: 10, iconSize: 9)
                }

                if card.project.isFavorite, !card.project.isArchived {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(ViabarColor.warning)
                }

                if card.project.isArchived {
                    Text("已归档")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onNavigate(card.project, .project)
            }

            ForEach(card.groups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    taskRow(title: group.title, reminderDate: group.reminderDate, isPrimary: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onNavigate(card.project, .milestone(group.milestoneID))
                        }

                    ForEach(group.subtasks) { subtask in
                        taskRow(title: subtask.title, reminderDate: subtask.reminderDate, isPrimary: false)
                            .padding(.leading, 12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onNavigate(card.project, .subTask(milestoneID: group.milestoneID, subTaskID: subtask.taskID))
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(reportCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.36 : 0.1), lineWidth: 1)
        }
    }

    private var reportCardBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.7)
            : .white
    }

    private func taskRow(title: String, reminderDate: Date?, isPrimary: Bool) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Circle()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            Group {
                if let reminderDate {
                    HStack(alignment: .center, spacing: 5) {
                        reminderLabel(reminderDate, fontSize: 13, iconSize: 8)
                        Text(title)
                            .font(.callout)
                            .foregroundStyle(isPrimary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    }
                } else {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(isPrimary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reminderLabel(_ date: Date, fontSize: CGFloat, iconSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 3) {
            Image(systemName: "alarm.fill")
                .font(.system(size: iconSize))
            Text(formatReminderDate(date))
                .font(.system(size: fontSize))
        }
        .foregroundStyle(IOSPrototypeReminderStyle.color(for: date))
        .fixedSize()
    }

    private func formatReminderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }
}

private struct IOSProjectDropTarget: Equatable {
    let id: UUID
    let placement: ReorderPlacement
}

private enum IOSProjectDragPayload {
    case project(UUID)

    var rawValue: String {
        switch self {
        case .project(let id):
            return "project:\(id.uuidString)"
        }
    }

    static func parse(_ value: String) -> IOSProjectDragPayload? {
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "project", let id = UUID(uuidString: parts[1]) else {
            return nil
        }
        return .project(id)
    }
}

private struct IOSProjectReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let placement: ReorderPlacement
    @Binding var draggingProjectID: UUID?
    @Binding var dropTarget: IOSProjectDropTarget?
    let onMove: (UUID, UUID, ReorderPlacement) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingProjectID != nil
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
            draggingProjectID = nil
            dropTarget = nil
        }
        guard let draggingProjectID else { return false }
        onMove(draggingProjectID, targetID, placement)
        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard draggingProjectID != nil else { return }
        dropTarget = IOSProjectDropTarget(id: targetID, placement: placement)
    }
}

private struct IOSReorderDropSeparator: View {
    let isActive: Bool

    var body: some View {
        ZStack(alignment: .center) {
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
}

struct IOSPersistentOverviewProjectCard: View {
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    let project: Project
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: project.sfSymbolName)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                    Text(project.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(Color.primary) : AnyShapeStyle(ViabarColor.primary))
                    Spacer()
                    if project.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ViabarColor.warning)
                    }
                }

                Spacer().frame(height: 18)

                if let milestone = topMilestone {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.gray.opacity(0.55))
                            .frame(width: 16)
                        Text(milestone.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color(hex: "#4B5563")))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)

                    if let subtask = milestone.subtasks
                        .sorted(by: { $0.orderIndex < $1.orderIndex })
                        .first(where: { !$0.isCompleted }) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.indent")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.gray)
                                .frame(width: 16)
                            Text(subtask.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.gray)
                                .lineLimit(1)
                        }
                        .padding(.leading, 22)
                        .padding(.top, 10)
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    if let reminder = topMilestone?.reminder {
                        IOSPersistentReminderSummary(
                            reminder: reminder,
                            dateFormatPattern: savedDateFormat,
                            language: effectiveLanguage,
                            font: .system(size: 11)
                        )
                            .padding(.leading, 8)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Text("\(Int(project.progress * 100))%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(IOSPrototypeProgressStyle.percentColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 44, alignment: .trailing)
                        IOSPrototypeProgressRing(progress: project.progress)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
        }
        .frame(height: 150)
        .iosPrototypeCardSurface(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button("归档", systemImage: "archivebox", action: onArchive)
            Button(LocalizedStringKey(project.isFavorite ? "取消收藏" : "收藏"), systemImage: project.isFavorite ? "star.slash" : "star", action: onToggleFavorite)
            Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var accentColor: Color {
        project.progress >= 1 ? ViabarColor.success : Color(hex: project.accentColor)
    }

    private var topMilestone: Milestone? {
        project.unfinishedMilestones.first
    }

    private var savedDateFormat: String? {
        settingsRecords.first?.dateFormat
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }
}

struct IOSPersistentSearchField: View {
    @Bindable var coordinator: IOSPersistenceCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索项目、任务或备忘录", text: $coordinator.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
            if !coordinator.searchText.isEmpty {
                Button {
                    coordinator.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: IOSPrototypeBottomBarMetrics.controlSize)
        .background(IOSPrototypeSurfaceStyle.inputBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18))
        .iosPrototypeInteractiveRoundedSurface(cornerRadius: 18)
        .onAppear {
            isFocused = true
        }
    }
}

struct IOSPersistentSearchView: View {
    @Bindable var coordinator: IOSPersistenceCoordinator
    let projects: [Project]
    let effectiveLanguage: EffectiveAppLanguage
    @Environment(\.colorScheme) private var colorScheme

    private var results: [GlobalSearchResult] {
        GlobalSearchIndex.results(
            matching: coordinator.searchText,
            projects: projects,
            archiveLabel: AppLocalization.string("归档", language: effectiveLanguage),
            memoLabel: AppLocalization.string("备忘录", language: effectiveLanguage)
        )
    }

    var body: some View {
        if !results.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button {
                            if result.project.isArchived {
                                coordinator.revealArchiveAncestors(for: result.project)
                            }
                            coordinator.navigate(to: result)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: result.project.sfSymbolName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color(hex: result.project.accentColor))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(result.path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(10)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < results.count - 1 {
                            Divider()
                                .padding(.leading, 39)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            .iosPrototypeCardSurface(cornerRadius: 14)
            .shadow(color: IOSPrototypeSurfaceStyle.shadow(for: colorScheme), radius: 14, y: 5)
        }
    }
}
