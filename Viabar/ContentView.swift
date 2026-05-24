import SwiftData
import SwiftUI
import AppKit

struct ContentView: View {
    @Query(sort: \Project.orderIndex) private var allProjects: [Project]

    @State private var selection: SidebarSelection? = .overview
    @State private var isMemoDrawerVisible: Bool = true
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
                    .toolbarBackground(.hidden, for: .automatic)
                    .navigationTitle("")
            }

            if let project = selectedProject, isMemoDrawerVisible {
                memoDrawer(project: project)
                    .transition(.move(edge: .trailing))
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
            Text(overviewDeleteProject.map { "“\($0.title)”将被永久删除，无法恢复。" } ?? "")
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
                onSelectProject: { selection = .project($0) },
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

    private var isSidebarHidden: Bool {
        splitVisibility == .detailOnly
    }

    private var projectService: ProjectService? {
        container.projectService
    }

    private var globalSearchResults: [GlobalSearchResult] {
        GlobalSearchIndex.results(matching: globalSearchQuery, projects: allProjects)
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
        .background(.background)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var memoDrawerPanelBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 0.10, alpha: 1)
                : NSColor(calibratedWhite: 0.94, alpha: 1)
        })
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
                .fill(Color(nsColor: .controlBackgroundColor))
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
        .help(isMemoDrawerVisible ? "收起备忘录" : "展开备忘录")
        .onHover { hoveredToolbarButton = $0 ? .memoDrawer : nil }
    }

    private var mainToolbarLayer: some View {
        VStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    toolbarGradientMask
                        .padding(.trailing, selectedProject != nil && isMemoDrawerVisible ? memoDrawerWidth : 0)

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
                            onSelect: openSearchResult(_:)
                        )

                        if let project = selectedProject {
                            hideCompletedButton(project: project)
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
        guard selectedProject != nil else { return toolbarEdgeInset }
        return isMemoDrawerVisible
            ? memoDrawerWidth + toolbarEdgeInset
            : collapsedProjectToolbarTrailing
    }

    private func globalSearchWidth(for toolbarWidth: CGFloat) -> CGFloat {
        let preferredWidth: CGFloat = isSidebarHidden ? 520 : 420
        let titleReservation: CGFloat = isSidebarHidden && selectedProject != nil ? 500 : 120
        let projectControls = selectedProject == nil ? 0 : toolbarButtonSize + 12
        let usableWidth = toolbarWidth - toolbarTrailingPadding - titleReservation - projectControls
        return min(preferredWidth, max(260, usableWidth))
    }

    private var toolbarGradientMask: some View {
        LinearGradient(
            stops: [
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.96), location: 0),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.82), location: 0.52),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .help(project.hideCompleted ? "显示已完成里程碑" : "隐藏已完成里程碑")
        .onHover { hoveredToolbarButton = $0 ? .hideCompleted : nil }
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

    private func dismissGlobalSearch() {
        isGlobalSearchPresented = false
        globalSearchQuery = ""
        highlightedSearchResultID = nil
    }

    private func toolbarButtonBackground(isHovered: Bool) -> some View {
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                Circle()
                    .fill(.primary.opacity(isHovered ? 0.06 : 0))
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
    }
}

private enum ToolbarButtonKind: Equatable {
    case memoDrawer
    case hideCompleted
}

struct OverviewDashboardView: View {
    let projects: [Project]
    let onSelectProject: (Project) -> Void
    let onEditProject: (Project) -> Void
    let onArchiveProject: (Project) -> Void
    let onDeleteProject: (Project) -> Void

    private let cardMinimumWidth: CGFloat = 320
    private let cardSpacing: CGFloat = 12
    private let contentPadding: CGFloat = 16

    private var visibleProjects: [Project] {
        projects
            .filter { !$0.isArchived }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        GeometryReader { proxy in
            let columns = overviewColumns(for: proxy.size.width)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: cardSpacing) {
                    ForEach(visibleProjects) { project in
                        OverviewProjectCard(
                            project: project,
                            onSelect: { onSelectProject(project) },
                            onEdit: { onEditProject(project) },
                            onArchive: { onArchiveProject(project) },
                            onDelete: { onDeleteProject(project) }
                        )
                    }
                }
                .padding(contentPadding)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

struct OverviewProjectCard: View {
    let project: Project
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(ServiceContainer.self) private var container
    @State private var isHovering = false

    private let cardHorizontalPadding: CGFloat = 18
    private let headerHeight: CGFloat = 42
    private let bodyHeight: CGFloat = 120
    private let iconFrameSize: CGFloat = 24
    private let milestoneRowHeight: CGFloat = 24
    private let reminderRowHeight: CGFloat = 18
    private let progressRowHeight: CGFloat = 14
    private let milestoneReminderSpacing: CGFloat = 12
    private let reminderProgressSpacing: CGFloat = 14
    private let progressStepCount = 22 // 调整这里可改变底部进度点数量
    private let progressDotSize: CGFloat = 5
    private let progressDotSpacing: CGFloat = 5
    private let progressPercentWidth: CGFloat = 38
    private let hoverAnimationDuration = 0.16 // 调整这里可改变卡片悬浮动画时长
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

    private var filledStepCount: Int {
        let raw = Int((project.progress * Double(progressStepCount)).rounded(.down))
        return max(0, min(progressStepCount, raw))
    }

    private var progressPercentText: String {
        "\(Int((project.progress * 100).rounded()))%"
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color(nsColor: .controlBackgroundColor)
    }

    private var headerBackground: Color {
        accentColor
    }

    private var cardShadowColor: Color {
        let opacity = isHovering ? 0.14 : 0.08
        return colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity)
    }

    private var cardBorderColor: Color {
        accentColor.opacity(colorScheme == .dark ? 0.24 : 0.16)
    }

    private var milestoneTextColor: Color {
        colorScheme == .dark ? Color(hex: "#C6CBD2") : Color(hex: "#4B5563")
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

    private var progressTintColor: Color {
        progressColor(at: project.progress)
    }

    private var progressDotsWidth: CGFloat {
        CGFloat(progressStepCount) * progressDotSize + CGFloat(max(progressStepCount - 1, 0)) * progressDotSpacing
    }

    private func progressColor(at value: Double) -> Color {
        let progress = max(0, min(1, value))
        let start = (red: 0x2B, green: 0xB7, blue: 0xFD)
        let end = (red: 0x09, green: 0xCC, blue: 0x9B)
        let red = Double(start.red) + (Double(end.red) - Double(start.red)) * progress
        let green = Double(start.green) + (Double(end.green) - Double(start.green)) * progress
        let blue = Double(start.blue) + (Double(end.blue) - Double(start.blue)) * progress
        return Color(
            red: red / 255,
            green: green / 255,
            blue: blue / 255
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: project.sfSymbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: iconFrameSize, height: iconFrameSize)

                Text(project.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if project.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ViabarColor.warning)
                }
            }
            .padding(.horizontal, cardHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: headerHeight, maxHeight: headerHeight, alignment: .center)
            .background(headerBackground)

            VStack(alignment: .leading, spacing: 0) {
                if let milestone = topMilestone {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ViabarColor.warning)
                            .frame(width: iconFrameSize, height: iconFrameSize, alignment: .center)

                        Text(milestone.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(milestoneTextColor)
                            .lineLimit(1)
                    }
                    .frame(height: milestoneRowHeight)
                } else {
                    Color.clear
                        .frame(height: milestoneRowHeight)
                }

                Color.clear
                    .frame(height: milestoneReminderSpacing)

                if let reminderDate, displayedMilestoneReminder != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "alarm.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(reminderForegroundColor)
                            .frame(width: iconFrameSize, height: 18, alignment: .center)

                        Text(reminderDate.formattedOverviewReminder(relativeTo: Date()))
                            .font(.callout)
                            .foregroundStyle(reminderForegroundColor)
                    }
                    .frame(height: reminderRowHeight)
                } else {
                    Color.clear
                        .frame(height: reminderRowHeight)
                }

                Color.clear
                    .frame(height: reminderProgressSpacing)

                HStack {
                    Spacer(minLength: 0)

                    HStack(alignment: .center, spacing: 10) {
                        HStack(spacing: progressDotSpacing) {
                            let stepCount = max(progressStepCount - 1, 1)
                            ForEach(0..<progressStepCount, id: \.self) { index in
                                let colorProgress = Double(index) / Double(stepCount)
                                Circle()
                                    .fill(index < filledStepCount ? progressColor(at: colorProgress) : Color.gray.opacity(0.22))
                                    .frame(width: progressDotSize, height: progressDotSize)
                            }
                        }
                        .frame(width: progressDotsWidth, height: progressDotSize, alignment: .leading)

                        Text(progressPercentText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(progressTintColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: progressPercentWidth, alignment: .trailing)
                    }
                }
                .frame(height: progressRowHeight)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, cardHorizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, minHeight: bodyHeight, maxHeight: bodyHeight, alignment: .topLeading)
            .background(cardBackground)
        }
        .frame(height: headerHeight + bodyHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(
            color: cardShadowColor,
            radius: isHovering ? hoverShadowRadius : restingShadowRadius,
            y: isHovering ? hoverShadowYOffset : restingShadowYOffset
        )
        .offset(y: isHovering ? -2 : 0)
        .animation(.easeOut(duration: hoverAnimationDuration), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Label(project.isFavorite ? "取消收藏" : "收藏", systemImage: project.isFavorite ? "star.slash" : "star")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

private extension Reminder {
    var overviewFireDate: Date? {
        fireTimestamp ?? nextOverviewRepeatingFireDate
    }

    var isOverviewReminderOverdue: Bool {
        guard let date = overviewFireDate else { return false }
        return date < Date()
    }

    var isOverviewReminderTodayPending: Bool {
        guard let date = overviewFireDate else { return false }
        return Calendar.current.isDateInToday(date) && date >= Date()
    }

    private var nextOverviewRepeatingFireDate: Date? {
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
}

private extension Date {
    func formattedOverviewReminder(relativeTo now: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        if calendar.isDate(self, inSameDayAs: now) {
            return "今天 \(timeFormatter.string(from: self))"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(self, inSameDayAs: tomorrow) {
            return "明天 \(timeFormatter.string(from: self))"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}

#Preview {
    ContentView()
        .environment(ServiceContainer())
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
            ],
            inMemory: true
        )
}
