import SwiftData
import SwiftUI
import AppKit

struct ContentView: View {
    @Query(sort: \Project.orderIndex) private var allProjects: [Project]
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @Query(sort: \NotificationScheduleEntry.fireDate) private var notificationScheduleEntries: [NotificationScheduleEntry]

    @State private var selection: SidebarSelection? = .overview
    @State private var isMemoDrawerVisible: Bool = true
    @State private var isOverviewReportDrawerVisible: Bool = true
    @State private var weekTodoOffset: Int = 0
    @State private var weekDoneOffset: Int = 0
    @State private var monthDoneOffset: Int = -1
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State private var hoveredToolbarButton: ToolbarButtonKind?
    @State private var overviewArchiveProject: Project?
    @State private var overviewEditProject: Project?
    @State private var overviewDeleteProject: Project?
    @State private var memoSearchDraft: String = ""
    @State private var activeMemoSearchQuery: String = ""
    @State private var isGlobalSearchPresented = false
    @State private var globalSearchQuery = ""
    @State private var highlightedSearchResultID: String?
    @State private var navigationRequest: GlobalSearchNavigationRequest?

    @Environment(ServiceContainer.self) private var container
    @Environment(AppRuntimeController.self) private var runtimeController
    @Environment(\.openWindow) private var openWindow

    private let memoDrawerWidth: CGFloat = 360
    private let toolbarButtonSize: CGFloat = 36
    private let toolbarButtonIconSize: CGFloat = 16
    private let toolbarEdgeInset: CGFloat = 8
    private let toolbarGradientHeight: CGFloat = 44

    private var memoToggleRowHeight: CGFloat {
        toolbarButtonSize + toolbarEdgeInset * 2
    }

    private var collapsedProjectToolbarTrailing: CGFloat {
        toolbarButtonSize + toolbarEdgeInset * 2
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationSplitView(columnVisibility: $splitVisibility) {
                SidebarView(
                    selection: $selection,
                    revealRequest: navigationRequest
                )
            } detail: {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        toolbarGradientMask
                            .padding(.trailing, visibleRightPanelWidth)
                            .ignoresSafeArea(.container, edges: .top)
                    }
                    .toolbarBackground(.hidden, for: .automatic)
                    .navigationTitle("")
            }

            if let project = selectedProject, isMemoDrawerVisible {
                memoDrawer(project: project)
                    .transition(.move(edge: .trailing))
            }

            if isOverviewSelected, isOverviewReportDrawerVisible {
                overviewReportDrawer
                    .transition(.move(edge: .trailing))
                    .zIndex(4)
            }

            if selectedProject != nil {
                memoToggleLayer
            }

            if isGlobalSearchPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissGlobalSearch()
                    }
                    .zIndex(2.5)
            }

            mainToolbarLayer
        }
        .animation(.easeInOut(duration: 0.2), value: isMemoDrawerVisible)
        .animation(.easeInOut(duration: 0.2), value: isOverviewReportDrawerVisible)
        .background {
            MainWindowReader { window in
                runtimeController.registerMainWindow(window)
            }
        }
        .environment(\.locale, effectiveLanguage.locale)
        .onAppear {
            runtimeController.registerMainWindowOpener {
                openWindow(id: "main")
            }
            presentPendingGlobalSearchIfNeeded()
            consumePendingNavigationIfNeeded()
        }
        .onChange(of: runtimeController.searchPresentationID) { _, _ in
            presentPendingGlobalSearchIfNeeded()
        }
        .onChange(of: runtimeController.navigationPresentationID) { _, _ in
            consumePendingNavigationIfNeeded()
        }
        .onChange(of: selectedProject?.projectId) { _, projectID in
            guard let navigationRequest, projectID != navigationRequest.projectID else { return }
            self.navigationRequest = nil
        }
        .sheet(item: $overviewEditProject) { project in
            NewProjectView(editingProject: project)
        }
        .alert(
            "删除项目？",
            isPresented: Binding(
                get: { overviewDeleteProject != nil },
                set: { if !$0 { overviewDeleteProject = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let project = overviewDeleteProject {
                    if selection == .project(project) {
                        selection = .overview
                    }
                    projectService?.deleteProject(project)
                }
                overviewDeleteProject = nil
            }
            Button("取消", role: .cancel) {
                overviewDeleteProject = nil
            }
        } message: {
            if let project = overviewDeleteProject {
                Text("“\(project.title)”将被永久删除，无法恢复。")
            }
        }
        .archiveFolderPicker(
            isPresented: Binding(
                get: { overviewArchiveProject != nil },
                set: { if !$0 { overviewArchiveProject = nil } }
            ),
            project: overviewArchiveProject ?? Project(title: ""),
            onConfirm: { folder in
                guard let project = overviewArchiveProject else { return }
                projectService?.archiveProject(project, to: folder)
                if selection == .project(project) {
                    selection = .overview
                }
                overviewArchiveProject = nil
            }
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .overview, .none:
            OverviewDashboardView(
                projects: allProjects,
                overviewScope: settingsRecords.first?.overviewScope,
                trailingPanelWidth: isOverviewReportDrawerVisible ? memoDrawerWidth : 0,
                onSelectProject: { project in
                    navigationRequest = GlobalSearchNavigationRequest(
                        projectID: project.projectId,
                        destination: navigationDestination(for: project)
                    )
                    selection = .project(project)
                },
                onEditProject: { overviewEditProject = $0 },
                onArchiveProject: { overviewArchiveProject = $0 },
                onDeleteProject: { overviewDeleteProject = $0 }
            )
        case let .project(project):
            MainSplitView(
                project: project,
                reservesMemoDrawer: isMemoDrawerVisible,
                memoPanelWidth: memoDrawerWidth,
                navigationRequest: navigationRequest
            )
        }
    }

    private var selectedProject: Project? {
        if case let .project(project) = selection {
            return project
        }
        return nil
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    private var isSidebarHidden: Bool {
        splitVisibility == .detailOnly
    }

    private var isOverviewSelected: Bool {
        switch selection {
        case .overview, .none:
            return true
        case .project:
            return false
        }
    }

    private var projectService: ProjectService? {
        container.projectService
    }

    private var globalSearchResults: [GlobalSearchResult] {
        GlobalSearchIndex.results(
            matching: globalSearchQuery,
            projects: allProjects,
            archiveLabel: AppLocalization.string("归档", language: effectiveLanguage),
            memoLabel: AppLocalization.string("备忘录", language: effectiveLanguage)
        )
    }

    private var overviewReportSections: [OverviewReportSection] {
        OverviewReportBuilder.makeReport(
            projects: allProjects,
            scheduleEntries: notificationScheduleEntries,
            weekTodoOffset: weekTodoOffset,
            weekDoneOffset: weekDoneOffset,
            monthDoneOffset: monthDoneOffset,
            now: Date()
        )
    }

    private func memoDrawer(project: Project) -> some View {
        HStack(spacing: 0) {
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    memoSearchField

                    Spacer(minLength: toolbarButtonSize + toolbarEdgeInset)
                }
                .padding(.leading, 12)
                .padding(.trailing, toolbarEdgeInset)
                .frame(height: memoToggleRowHeight)
                .background(memoDrawerPanelBackground)
                Divider()

                MemoTimelineView(
                    project: project,
                    searchDraft: $memoSearchDraft,
                    activeSearchQuery: $activeMemoSearchQuery,
                    navigationRequest: navigationRequest
                )
            }
            .frame(width: memoDrawerWidth)
        }
        .frame(maxHeight: .infinity)
        .background(ViabarColor.mainPanelBackground)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var memoDrawerPanelBackground: Color {
        ViabarColor.mainPanelMemoBackground
    }

    private var overviewReportDrawer: some View {
        HStack(spacing: 0) {
            Divider()
            OverviewReportDrawerView(
                sections: overviewReportSections,
                weekTodoOffset: $weekTodoOffset,
                weekDoneOffset: $weekDoneOffset,
                monthDoneOffset: $monthDoneOffset,
                onToggleVisibility: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isOverviewReportDrawerVisible = false
                    }
                }
            )
            .frame(width: memoDrawerWidth)
        }
        .frame(maxHeight: .infinity)
        .background(ViabarColor.mainPanelBackground)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var memoSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("查询备忘录", text: $memoSearchDraft)
                .textFieldStyle(.plain)
                .font(.caption)
                .submitLabel(.search)
                .onSubmit { commitMemoSearch() }

            if !memoSearchDraft.isEmpty || hasActiveMemoSearch {
                Button {
                    resetMemoSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("重置查询")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: toolbarButtonSize)
        .frame(maxWidth: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(ViabarColor.panelInputBackground)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }

    private var hasActiveMemoSearch: Bool {
        !activeMemoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commitMemoSearch() {
        activeMemoSearchQuery = memoSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetMemoSearch() {
        memoSearchDraft = ""
        activeMemoSearchQuery = ""
    }

    private var memoToggleLayer: some View {
        VStack {
            HStack {
                Spacer()
                memoToggleButton
                    .padding(.top, toolbarEdgeInset)
                    .padding(.trailing, toolbarEdgeInset)
            }
            Spacer()
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .zIndex(2)
    }

    private var memoToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isMemoDrawerVisible.toggle()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: toolbarButtonIconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(toolbarButtonBackground(isHovered: hoveredToolbarButton == .memoDrawer))
                .contentShape(Circle())
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .buttonStyle(.plain)
        .help(isMemoDrawerVisible ? Text("收起备忘录") : Text("展开备忘录"))
        .onHover { hoveredToolbarButton = $0 ? .memoDrawer : nil }
    }

    private var mainToolbarLayer: some View {
        VStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    HStack(spacing: 12) {
                        if isSidebarHidden, let project = selectedProject {
                            HStack(spacing: 8) {
                                Image(systemName: project.sfSymbolName)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Color(hex: project.accentColor))
                                Text(project.title)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                            }
                            .lineLimit(1)
                            .frame(maxWidth: 360, alignment: .leading)
                            .padding(.leading, 180)
                            .searchTargetHighlight(
                                triggerID: projectTitleHighlightRequestID(for: project),
                                isActive: projectTitleHighlightRequestID(for: project) != nil
                            )
                        }

                        Spacer()

                        GlobalSearchOverlay(
                            isPresented: $isGlobalSearchPresented,
                            query: $globalSearchQuery,
                            highlightedResultID: $highlightedSearchResultID,
                            results: globalSearchResults,
                            availableWidth: globalSearchWidth(for: proxy.size.width),
                            iconSize: toolbarButtonIconSize,
                            buttonSize: toolbarButtonSize,
                            onPresent: presentGlobalSearch,
                            onSelect: openSearchResult(_:)
                        )

                        if let project = selectedProject {
                            hideCompletedButton(project: project)
                        }

                        if isOverviewSelected, !isOverviewReportDrawerVisible {
                            overviewReportRevealButton
                        }
                    }
                    .padding(.trailing, toolbarTrailingPadding)
                    .padding(.top, toolbarEdgeInset)
                }
            }
            .frame(height: toolbarGradientHeight)

            Spacer()
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .zIndex(3)
    }

    private var toolbarTrailingPadding: CGFloat {
        if visibleRightPanelWidth > 0 {
            return visibleRightPanelWidth + toolbarEdgeInset
        }
        return selectedProject != nil ? collapsedProjectToolbarTrailing : toolbarEdgeInset
    }

    private var visibleRightPanelWidth: CGFloat {
        if selectedProject != nil, isMemoDrawerVisible {
            return memoDrawerWidth
        }
        if isOverviewSelected, isOverviewReportDrawerVisible {
            return memoDrawerWidth
        }
        return 0
    }

    private func globalSearchWidth(for toolbarWidth: CGFloat) -> CGFloat {
        let preferredWidth: CGFloat = isSidebarHidden ? 520 : 420
        let titleReservation: CGFloat = isSidebarHidden && selectedProject != nil ? 500 : 120
        let hasAdjacentControl = selectedProject != nil || (isOverviewSelected && !isOverviewReportDrawerVisible)
        let projectControls = hasAdjacentControl ? toolbarButtonSize + 12 : 0
        let usableWidth = toolbarWidth - toolbarTrailingPadding - titleReservation - projectControls
        return min(preferredWidth, max(260, usableWidth))
    }

    private var toolbarGradientMask: some View {
        LinearGradient(
            stops: [
                .init(color: ViabarColor.mainPanelBackground.opacity(0.96), location: 0),
                .init(color: ViabarColor.mainPanelBackground.opacity(0.82), location: 0.52),
                .init(color: ViabarColor.mainPanelBackground.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: toolbarGradientHeight, alignment: .top)
        .allowsHitTesting(false)
    }

    private func hideCompletedButton(project: Project) -> some View {
        Button {
            project.hideCompleted.toggle()
            projectService?.updateProject(project)
        } label: {
            Image(systemName: project.hideCompleted ? "eye.slash" : "eye")
                .font(.system(size: toolbarButtonIconSize, weight: .medium))
                .foregroundStyle(project.hideCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.blue))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(toolbarButtonBackground(isHovered: hoveredToolbarButton == .hideCompleted))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(project.hideCompleted ? Text("显示已完成里程碑") : Text("隐藏已完成里程碑"))
        .onHover { hoveredToolbarButton = $0 ? .hideCompleted : nil }
    }

    private var overviewReportRevealButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOverviewReportDrawerVisible = true
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: toolbarButtonIconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(toolbarButtonBackground(isHovered: hoveredToolbarButton == .overviewReport))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("展开汇总面板")
        .onHover { hoveredToolbarButton = $0 ? .overviewReport : nil }
    }

    private func openSearchResult(_ result: GlobalSearchResult) {
        navigationRequest = GlobalSearchNavigationRequest(
            projectID: result.project.projectId,
            destination: result.destination
        )
        selection = .project(result.project)

        if case .memo = result.destination {
            resetMemoSearch()
            isMemoDrawerVisible = true
        }

        dismissGlobalSearch()
    }

    private func projectTitleHighlightRequestID(for project: Project) -> UUID? {
        guard navigationRequest?.projectID == project.projectId,
              case .some(.project) = navigationRequest?.destination
        else { return nil }
        return navigationRequest?.id
    }

    private func navigationDestination(for project: Project) -> GlobalSearchDestination {
        guard let topMilestone = project.unfinishedMilestones.first else {
            return .project
        }
        if let subtask = topMilestone.subtasks.first(where: { !$0.isCompleted }) {
            return .subTask(milestoneID: topMilestone.milestoneId, subTaskID: subtask.taskId)
        }
        return .milestone(topMilestone.milestoneId)
    }

    private func dismissGlobalSearch() {
        isGlobalSearchPresented = false
        globalSearchQuery = ""
        highlightedSearchResultID = nil
    }

    private func presentGlobalSearch() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isGlobalSearchPresented = true
        }
    }

    private func presentPendingGlobalSearchIfNeeded() {
        guard runtimeController.consumePendingSearchPresentation() else { return }
        presentGlobalSearch()
    }

    private func consumePendingNavigationIfNeeded() {
        guard let request = runtimeController.consumePendingNavigationRequest(),
              let project = allProjects.first(where: { $0.projectId == request.projectID })
        else { return }

        navigationRequest = request
        selection = .project(project)
        if case .memo = request.destination {
            resetMemoSearch()
            isMemoDrawerVisible = true
        }
        dismissGlobalSearch()
    }

    private func toolbarButtonBackground(isHovered: Bool) -> some View {
        Circle()
            .fill(ViabarColor.panelInputBackground)
            .overlay {
                Circle()
                    .fill(.primary.opacity(isHovered ? 0.06 : 0))
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
    }
}

private enum ToolbarButtonKind: Equatable {
    case memoDrawer
    case overviewReport
    case hideCompleted
}

struct OverviewDashboardView: View {
    let projects: [Project]
    let overviewScope: String?
    let trailingPanelWidth: CGFloat
    let onSelectProject: (Project) -> Void
    let onEditProject: (Project) -> Void
    let onArchiveProject: (Project) -> Void
    let onDeleteProject: (Project) -> Void

    private let cardMinimumWidth: CGFloat = 320
    private let cardSpacing: CGFloat = 12
    private let contentPadding: CGFloat = 16

    private var visibleProjects: [Project] {
        OverviewScope.visibleProjects(from: projects, storedValue: overviewScope)
    }

    private var starredProjects: [Project] {
        visibleProjects.filter { $0.isFavorite }
    }

    private var otherProjects: [Project] {
        visibleProjects.filter { !$0.isFavorite }
    }

    var body: some View {
        GeometryReader { proxy in
            let columns = overviewColumns(for: proxy.size.width - trailingPanelWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !starredProjects.isEmpty {
                        sectionHeader(icon: "star.fill", title: "星标项目")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: cardSpacing) {
                            ForEach(starredProjects) { project in
                                OverviewProjectCard(
                                    project: project,
                                    onSelect: { onSelectProject(project) },
                                    onEdit: { onEditProject(project) },
                                    onArchive: { onArchiveProject(project) },
                                    onDelete: { onDeleteProject(project) }
                                )
                            }
                        }
                    }

                    if !otherProjects.isEmpty {
                        sectionHeader(icon: "list.bullet", title: "其他项目")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: cardSpacing) {
                            ForEach(otherProjects) { project in
                                OverviewProjectCard(
                                    project: project,
                                    onSelect: { onSelectProject(project) },
                                    onEdit: { onEditProject(project) },
                                    onArchive: { onArchiveProject(project) },
                                    onDelete: { onDeleteProject(project) }
                                )
                            }
                        }
                    }
                }
                .padding(contentPadding)
            }
            .padding(.trailing, trailingPanelWidth)
        }
        .background(ViabarColor.mainPanelBackground)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func overviewColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = max(1, width - contentPadding * 2)
        let rawCount = Int((availableWidth + cardSpacing) / (cardMinimumWidth + cardSpacing))
        let columnCount = max(1, rawCount)
        return Array(
            repeating: GridItem(.flexible(minimum: cardMinimumWidth), spacing: cardSpacing, alignment: .top),
            count: columnCount
        )
    }
}

private struct MainWindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowObservingView {
        WindowObservingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindow()
    }

    final class WindowObservingView: NSView {
        var onResolve: (NSWindow?) -> Void

        init(onResolve: @escaping (NSWindow?) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveWindow()
        }

        func resolveWindow() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onResolve(self.window)
            }
        }
    }
}

struct OverviewProjectCard: View {
    let project: Project
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(ServiceContainer.self) private var container
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var isHovering = false

    private let hoverAnimationDuration = 0.16
    private let progressRingSize: CGFloat = 28
    private let progressRingLineWidth: CGFloat = 7
    private let progressTextWidth: CGFloat = 40      // 百分比文本固定宽度，保证圆环对齐
    private let progressRingTextSpacing: CGFloat = 12 // 圆环与文本间距
    private let taskRowIndent: CGFloat = 4        // 任务行左侧缩进
    private let subtaskExtraIndent: CGFloat = 18  // 子任务相对任务行的额外缩进
    private let headerToTaskSpacing: CGFloat = 18 // 标题到任务行间距
    private let cardBottomPadding: CGFloat = 12   // 卡片底部内边距
    private let restingShadowRadius: CGFloat = 1 // 调整这里可改变默认阴影
    private let restingShadowYOffset: CGFloat = 2
    private let hoverShadowRadius: CGFloat = 10 // 调整这里可改变 hover 阴影
    private let hoverShadowYOffset: CGFloat = 5
    private let reminderTodayPendingColor = Color.orange
    private let reminderOverdueColor = Color.red

    private var projectService: ProjectService? {
        container.projectService
    }

    private var accentColor: Color {
        project.progress >= 1.0
            ? ViabarColor.success
            : Color(hex: project.accentColor)
    }

    private var topMilestone: Milestone? {
        project.unfinishedMilestones.first
    }

    private var displayedMilestoneReminder: Reminder? {
        topMilestone?.reminder
    }

    private var reminderDate: Date? {
        displayedMilestoneReminder?.overviewFireDate
    }

    private var savedDateFormat: String? {
        settingsRecords.first?.dateFormat
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.25, alpha: 0.54))
            : Color(nsColor: NSColor(calibratedWhite: 1, alpha: 1))
    }

    private var cardShadowColor: Color {
        let opacity = isHovering ? 0.14 : 0.08
        return colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity)
    }

    private var milestoneTextColor: Color {
        colorScheme == .dark ? Color(hex: "#C6CBD2") : Color(hex: "#4B5563")
    }

    /// 子任务文本颜色（深色/浅色模式在此处调整）
    private var subtaskTextColor: Color {
        colorScheme == .dark
            ? Color.gray.opacity(1)
            : Color.gray.opacity(1)
    }

    private var reminderTextColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.78) : Color.gray.opacity(0.88)
    }

    private var reminderForegroundColor: Color {
        guard let reminder = displayedMilestoneReminder else {
            return reminderTextColor
        }

        if reminder.isOverviewReminderOverdue {
            return reminderOverdueColor
        }

        if reminder.isOverviewReminderTodayPending {
            return reminderTodayPendingColor
        }

        return reminderTextColor
    }

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
                        .foregroundStyle(colorScheme == .dark ? ViabarColor.primaryPale : ViabarColor.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if project.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ViabarColor.warning)
                    }
                }

                Spacer().frame(height: headerToTaskSpacing)

                if let milestone = topMilestone {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.gray.opacity(0.55))
                            .frame(width: 16, alignment: .center)
                        Text(milestone.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(milestoneTextColor)
                            .lineLimit(1)
                    }
                    .padding(.leading, taskRowIndent)

                    if let subtask = milestone.subtasks.first(where: { !$0.isCompleted }) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.indent")
                                .font(.system(size: 11))
                                .foregroundStyle(subtaskTextColor)
                                .frame(width: 16, alignment: .center)
                            Text(subtask.title)
                                .font(.system(size: 12))
                                .foregroundStyle(subtaskTextColor)
                                .lineLimit(1)
                        }
                        .padding(.leading, taskRowIndent + subtaskExtraIndent)
                        .padding(.top, 10)
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    if let reminderDate, displayedMilestoneReminder != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "alarm.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(reminderForegroundColor)
                            Text(AppDateFormatter.string(from: reminderDate, pattern: savedDateFormat))
                                .font(.system(size: 11))
                                .foregroundStyle(reminderForegroundColor)
                        }.padding(.leading, 8)
                            .offset(y: -5)
                    }

                    Spacer(minLength: 8)

                    progressRing
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.top, 12)
            .padding(.bottom, cardBottomPadding)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(
            color: cardShadowColor,
            radius: isHovering ? hoverShadowRadius : restingShadowRadius,
            y: isHovering ? hoverShadowYOffset : restingShadowYOffset
        )
        .offset(y: isHovering ? -2 : 0)
        .animation(.easeOut(duration: hoverAnimationDuration), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                onArchive()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            Button {
                projectService?.toggleFavorite(project)
            } label: {
                if project.isFavorite {
                    Label("取消收藏", systemImage: "star.slash")
                } else {
                    Label("收藏", systemImage: "star")
                }
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var progressRing: some View {
        let ringTrackColor = Color(hex: "#00BBE1").opacity(0.2)
        let ringStartColor = Color(hex: "#00BBE1")
        let ringEndColor = Color(hex: "#00F9D0")
        let percentColor = Color(hex: "#00BBE1")

        return HStack(spacing: progressRingTextSpacing) {
            ZStack {
                Circle()
                    .stroke(ringTrackColor, lineWidth: progressRingLineWidth)
                    .frame(width: progressRingSize, height: progressRingSize)

                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, project.progress))))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [ringStartColor, ringEndColor, ringStartColor]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: progressRingLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: progressRingSize, height: progressRingSize)
            }

            Text("\(Int(project.progress * 100))%")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(percentColor)
                .monospacedDigit()
                .frame(width: progressTextWidth, alignment: .leading)
        }
    }
}

private extension Reminder {
    var overviewFireDate: Date? {
        displayFireDate
    }

    var isOverviewReminderOverdue: Bool {
        guard let date = overviewFireDate else { return false }
        return date < Date()
    }

    var isOverviewReminderTodayPending: Bool {
        guard let date = overviewFireDate else { return false }
        return Calendar.current.isDateInToday(date) && date >= Date()
    }

}

#Preview {
    ContentView()
        .environment(ServiceContainer())
        .environment(AppRuntimeController())
        .modelContainer(
            for: [
                Project.self,
                Milestone.self,
                SubTask.self,
                Memo.self,
                Reminder.self,
                ArchiveFolder.self,
                ProjectTemplate.self,
                TemplateMilestone.self,
                TemplateSubTask.self,
                AppSettings.self,
            ],
            inMemory: true
        )
}
