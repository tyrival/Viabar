import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let iosProjectReorderLogStart = Date()

private func iosProjectReorderLog(_ message: String) {
    let elapsed = Date().timeIntervalSince(iosProjectReorderLogStart)
    print(String(format: "[IOSProjectReorder +%.3fs] %@", elapsed, message))
}

struct IOSGlassView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        view.alpha = 0.3
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct IOSPersistentOverviewView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var projectDisplayOrderBySection: [IOSProjectSection: [UUID]] = [:]
    @State private var projectDragSessionID: UUID?
    @State private var projectDragSessionSawDropEvent = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ViabarColor.mainPanelBackground
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
            IOSPersistentSettingsView(systemColorScheme: colorScheme)
                .id(colorScheme)
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
                        projectList(favoriteProjects, section: .favorites)
                    }
                }

                if !regularProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        IOSPrototypeSectionLabel(title: "其他项目")
                            .padding(.top, 4)
                        projectList(regularProjects, section: .regular)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 112)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: draggingProjectID) { _, newValue in
            iosProjectReorderLog("draggingProjectID changed to \(newValue?.uuidString ?? "nil")")
        }
    }

    private func projectList(_ projects: [Project], section: IOSProjectSection) -> some View {
        let displayedProjects = displayedProjects(projects, section: section)

        return VStack(spacing: IOSProjectReorderMetrics.cardSpacing) {
            ForEach(displayedProjects, id: \.projectId) { project in
                projectCardLink(project)
            }
        }
        .padding(.vertical, IOSProjectReorderMetrics.verticalInset)
        .animation(IOSProjectReorderMetrics.animation, value: displayedProjects.map(\.projectId))
        .overlay {
            IOSProjectReorderDropOverlay(
                projects: displayedProjects,
                section: section,
                draggingProjectID: draggingProjectID,
                draggingProjectIDBinding: $draggingProjectID,
                displayOrderBySection: $projectDisplayOrderBySection,
                onDropEvent: markProjectDragDropEvent,
                onCommit: persistProjectOrder(_:)
            )
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
            iosProjectReorderLog("tap project=\(project.title) id=\(project.projectId) dragging=\(draggingProjectID?.uuidString ?? "nil")")
            coordinator.selectProject(project)
        }
        .onDrag {
            draggingProjectID = project.projectId
            let sessionID = UUID()
            projectDragSessionID = sessionID
            projectDragSessionSawDropEvent = false
            iosProjectReorderLog("drag start project=\(project.title) id=\(project.projectId)")
            scheduleProjectDragFallbackReset(projectID: project.projectId, sessionID: sessionID)
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

    private var activeProjects: [Project] {
        OverviewScope.visibleProjects(
            from: projects,
            storedValue: settingsRecords.first?.overviewScope
        )
    }

    private var orderableActiveProjects: [Project] {
        projects
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.orderIndex == rhs.orderIndex {
                    return lhs.projectId.uuidString < rhs.projectId.uuidString
                }
                return lhs.orderIndex < rhs.orderIndex
            }
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

    private func displayedProjects(_ projects: [Project], section: IOSProjectSection) -> [Project] {
        guard let displayOrder = projectDisplayOrderBySection[section] else {
            return projects
        }

        let projectIDs = Set(projects.map(\.projectId))
        guard displayOrder.count == projects.count, Set(displayOrder) == projectIDs else {
            return projects
        }

        var projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0) })
        return displayOrder.compactMap { projectsByID.removeValue(forKey: $0) }
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

    private func persistProjectOrder(_ orderedSectionProjects: [Project]) {
        guard !orderedSectionProjects.isEmpty else { return }

        let sectionIDs = Set(orderedSectionProjects.map(\.projectId))
        let sectionSlots = orderableActiveProjects.indices.filter { index in
            sectionIDs.contains(orderableActiveProjects[index].projectId)
        }
        guard sectionSlots.count == orderedSectionProjects.count else { return }

        var orderedActiveProjects = orderableActiveProjects
        for (slot, project) in zip(sectionSlots, orderedSectionProjects) {
            orderedActiveProjects[slot] = project
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            for (index, project) in orderedActiveProjects.enumerated() where project.orderIndex != index {
                project.orderIndex = index
            }
        }
        services.projectService?.save()
    }

    private func markProjectDragDropEvent() {
        projectDragSessionSawDropEvent = true
    }

    private func scheduleProjectDragFallbackReset(projectID: UUID, sessionID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard projectDragSessionID == sessionID,
                  draggingProjectID == projectID,
                  !projectDragSessionSawDropEvent
            else { return }

            iosProjectReorderLog("fallback reset orphan drag project=\(projectID) session=\(sessionID)")
            draggingProjectID = nil
            projectDisplayOrderBySection.removeAll()
            projectDragSessionID = nil
        }
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

private enum IOSProjectSection: Hashable {
    case favorites
    case regular

    var logName: String {
        switch self {
        case .favorites:
            return "favorites"
        case .regular:
            return "regular"
        }
    }
}

private enum IOSProjectReorderMetrics {
    static let cardHeight: CGFloat = 118
    static let cardSpacing: CGFloat = 8
    static let verticalInset: CGFloat = 4
    static let animation: Animation = .easeInOut(duration: 0.12)
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

private struct IOSProjectReorderDropOverlay: View {
    let projects: [Project]
    let section: IOSProjectSection
    let draggingProjectID: UUID?
    @Binding var draggingProjectIDBinding: UUID?
    @Binding var displayOrderBySection: [IOSProjectSection: [UUID]]
    let onDropEvent: () -> Void
    let onCommit: ([Project]) -> Void

    private var isDraggingProjectInSection: Bool {
        guard let draggingProjectID else { return false }
        return projects.contains { $0.projectId == draggingProjectID }
    }

    var body: some View {
        GeometryReader { proxy in
            Color.primary.opacity(0.001)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .onDrop(
                    of: [.text],
                    delegate: IOSProjectReorderDropDelegate(
                        projects: projects,
                        section: section,
                        draggingProjectID: $draggingProjectIDBinding,
                        displayOrderBySection: $displayOrderBySection,
                        onDropEvent: onDropEvent,
                        onCommit: onCommit
                    )
                )
        }
        .allowsHitTesting(isDraggingProjectInSection)
        .onChange(of: isDraggingProjectInSection) { _, newValue in
            iosProjectReorderLog(
                "overlay hitTesting section=\(section.logName) enabled=\(newValue) dragging=\(draggingProjectID?.uuidString ?? "nil") projects=\(projects.map(\.projectId.uuidString))"
            )
        }
    }
}

private struct IOSProjectDropTarget {
    let project: Project
    let placement: ReorderPlacement
}

private struct IOSProjectReorderDropDelegate: DropDelegate {
    let projects: [Project]
    let section: IOSProjectSection
    @Binding var draggingProjectID: UUID?
    @Binding var displayOrderBySection: [IOSProjectSection: [UUID]]
    let onDropEvent: () -> Void
    let onCommit: ([Project]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        onDropEvent()
        guard let draggingProjectID else {
            iosProjectReorderLog("validate=false section=\(section.logName) reason=no draggingProjectID")
            return false
        }
        let isValid = projects.contains { $0.projectId == draggingProjectID }
        iosProjectReorderLog("validate=\(isValid) section=\(section.logName) dragging=\(draggingProjectID)")
        return isValid
    }

    func dropEntered(info: DropInfo) {
        onDropEvent()
        iosProjectReorderLog("dropEntered section=\(section.logName) y=\(info.location.y) dragging=\(draggingProjectID?.uuidString ?? "nil")")
        updateDisplayOrder(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onDropEvent()
        iosProjectReorderLog("dropUpdated section=\(section.logName) y=\(info.location.y) dragging=\(draggingProjectID?.uuidString ?? "nil")")
        updateDisplayOrder(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onDropEvent()
        iosProjectReorderLog("dropExited section=\(section.logName) y=\(info.location.y)")
        resetDragState()
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropEvent()
        iosProjectReorderLog("performDrop begin section=\(section.logName) y=\(info.location.y) dragging=\(draggingProjectID?.uuidString ?? "nil")")
        updateDisplayOrder(info: info)
        guard let finalProjects = finalDisplayProjects() else {
            iosProjectReorderLog("performDrop=false section=\(section.logName) reason=no finalProjects")
            resetDragState()
            return false
        }

        defer {
            resetDragState()
        }
        onCommit(finalProjects)
        iosProjectReorderLog("performDrop=true section=\(section.logName) final=\(finalProjects.map(\.projectId.uuidString))")
        return true
    }

    private func updateDisplayOrder(info: DropInfo) {
        guard let draggingProjectID,
              let target = dropTarget(for: info.location.y),
              draggingProjectID != target.project.projectId,
              let sourceIndex = projects.firstIndex(where: { $0.projectId == draggingProjectID }),
              let targetIndex = projects.firstIndex(where: { $0.projectId == target.project.projectId })
        else {
            iosProjectReorderLog("update skipped section=\(section.logName) y=\(info.location.y) dragging=\(draggingProjectID?.uuidString ?? "nil")")
            return
        }

        let destination = insertionIndex(
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            placement: target.placement
        )
        guard sourceIndex != destination else {
            iosProjectReorderLog("update skipped section=\(section.logName) reason=same destination source=\(sourceIndex) destination=\(destination)")
            return
        }

        var reorderedProjects = projects
        let movingProject = reorderedProjects.remove(at: sourceIndex)
        reorderedProjects.insert(movingProject, at: destination)
        let reorderedIDs = reorderedProjects.map(\.projectId)
        guard displayOrderBySection[section] != reorderedIDs else {
            iosProjectReorderLog("update skipped section=\(section.logName) reason=order unchanged")
            return
        }

        iosProjectReorderLog(
            "update order section=\(section.logName) source=\(sourceIndex) target=\(targetIndex) destination=\(destination) placement=\(target.placement) ids=\(reorderedIDs.map(\.uuidString))"
        )
        withAnimation(IOSProjectReorderMetrics.animation) {
            displayOrderBySection[section] = reorderedIDs
        }
    }

    private func dropTarget(for y: CGFloat) -> IOSProjectDropTarget? {
        guard !projects.isEmpty else { return nil }

        for (index, project) in projects.enumerated() {
            let midpoint = IOSProjectReorderMetrics.verticalInset
                + CGFloat(index) * (IOSProjectReorderMetrics.cardHeight + IOSProjectReorderMetrics.cardSpacing)
                + IOSProjectReorderMetrics.cardHeight / 2
            if y < midpoint {
                return IOSProjectDropTarget(project: project, placement: .before)
            }
        }

        guard let lastProject = projects.last else { return nil }
        return IOSProjectDropTarget(project: lastProject, placement: .after)
    }

    private func finalDisplayProjects() -> [Project]? {
        guard let displayOrder = displayOrderBySection[section] else {
            return projects
        }

        var projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0) })
        let finalProjects = displayOrder.compactMap { projectsByID.removeValue(forKey: $0) }
        guard finalProjects.count == projects.count else { return nil }
        return finalProjects
    }

    private func insertionIndex(
        sourceIndex: Int,
        targetIndex: Int,
        placement: ReorderPlacement
    ) -> Int {
        var insertionIndex = targetIndex
        if sourceIndex < targetIndex {
            insertionIndex -= 1
        }
        if placement == .after {
            insertionIndex += 1
        }
        return min(max(insertionIndex, 0), projects.count - 1)
    }

    private func resetDragState() {
        iosProjectReorderLog("reset section=\(section.logName) draggingBefore=\(draggingProjectID?.uuidString ?? "nil")")
        draggingProjectID = nil
        displayOrderBySection[section] = nil
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: project.sfSymbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(accentColor)
                Text(project.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if project.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ViabarColor.warning)
                }
            }

            Spacer().frame(height: 10)

            if let milestone = topMilestone {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.gray.opacity(0.55))
                        .frame(width: 16, alignment: .center)
                    Text(milestone.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(milestoneTitleColor(milestone.markerColor))
                        .lineLimit(1)
                }
                .padding(.leading, 4)

                if let subtask = milestone.subtasks
                    .sorted(by: { $0.orderIndex < $1.orderIndex })
                    .first(where: { !$0.isCompleted }) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.gray.opacity(0.55))
                            .frame(width: 16, alignment: .center)
                        Text(subtask.title)
                            .font(.system(size: 12))
                            .foregroundStyle(subtaskTitleColor(subtask.markerColor))
                            .lineLimit(1)
                    }
                    .padding(.leading, 22)
                    .padding(.top, 4)
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
                        .offset(y: -5)
                }
                Spacer(minLength: 8)
                progressRing
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(height: IOSProjectReorderMetrics.cardHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: colorScheme == .dark
                            ? [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color.white.opacity(0.24), location: 0.15),
                                .init(color: Color.white.opacity(0.24), location: 0.85),
                                .init(color: .clear, location: 1.0)
                              ]
                            : [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color.black.opacity(0.10), location: 0.15),
                                .init(color: Color.black.opacity(0.10), location: 0.85),
                                .init(color: .clear, location: 1.0)
                              ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    lineWidth: colorScheme == .dark ? 0.8 : 0.7
                )
        )
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.01) : Color.white)
                    .shadow(
                        color: colorScheme == .dark
                            ? Color.black.opacity(0.40)
                            : Color(hex: "#0F172A").opacity(0.05),
                        radius: 6,
                        x: 0,
                        y: 2.5
                    )

                IOSGlassView()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                        .allowsHitTesting(false)
                }
            }
        }
        .contextMenu {
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button(LocalizedStringKey(project.isFavorite ? "取消收藏" : "收藏"), systemImage: project.isFavorite ? "star.slash" : "star", action: onToggleFavorite)
            Button("归档", systemImage: "archivebox", action: onArchive)
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

    private func milestoneTitleColor(_ markerColor: String?) -> Color {
        if let marker = TaskMarkerColor.resolve(markerColor) {
            return ViabarColor.taskMarker(marker)
        }
        return colorScheme == .dark ? Color(hex: "#C6CBD2") : Color(hex: "#4B5563")
    }

    private func subtaskTitleColor(_ markerColor: String?) -> Color {
        if let marker = TaskMarkerColor.resolve(markerColor) {
            return ViabarColor.taskMarker(marker)
        }
        return .gray
    }

    private var progressRing: some View {
        let ringTrackColor = Color(hex: "#00BBE1").opacity(0.2)
        let ringStartColor = Color(hex: "#00BBE1")
        let ringEndColor = Color(hex: "#00F9D0")

        return ZStack {
            Circle()
                .stroke(ringTrackColor, lineWidth: 5)
                .frame(width: 24, height: 24)

            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, project.progress))))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [ringStartColor, ringEndColor, ringStartColor]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 24, height: 24)
        }
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
