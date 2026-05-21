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

    @Environment(ServiceContainer.self) private var container

    private let memoDrawerWidth: CGFloat = 360
    private let toolbarButtonSize: CGFloat = 36
    private let toolbarButtonIconSize: CGFloat = 16
    private let toolbarEdgeInset: CGFloat = 8
    private let toolbarGradientHeight: CGFloat = 44

    private var memoToggleRowHeight: CGFloat {
        toolbarButtonSize + toolbarEdgeInset * 2
    }

    private var collapsedHideCompletedTrailing: CGFloat {
        toolbarButtonSize + toolbarEdgeInset * 2
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationSplitView(columnVisibility: $splitVisibility) {
                SidebarView(selection: $selection)
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

            if let project = selectedProject {
                mainToolbarLayer(project: project)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isMemoDrawerVisible)
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
                memoPanelWidth: memoDrawerWidth
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
                    activeSearchQuery: $activeMemoSearchQuery
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

    private func mainToolbarLayer(project: Project) -> some View {
        VStack {
            ZStack(alignment: .top) {
                toolbarGradientMask
                    .padding(.trailing, isMemoDrawerVisible ? memoDrawerWidth : 0)

                HStack(spacing: 12) {
                    if isSidebarHidden {
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
                    }

                    Spacer()

                    hideCompletedButton(project: project)
                        .padding(.trailing, isMemoDrawerVisible ? memoDrawerWidth + toolbarEdgeInset : collapsedHideCompletedTrailing)
                }
                .padding(.top, toolbarEdgeInset)
            }
            .frame(height: toolbarGradientHeight)

            Spacer()
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .zIndex(1)
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

    private let cardMinimumWidth: CGFloat = 280
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

    private let cardHorizontalPadding: CGFloat = 18
    private let headerHeight: CGFloat = 42
    private let iconFrameSize: CGFloat = 24
    private let progressStepCount = 22
    private let progressDotSize: CGFloat = 8

    private var accentColor: Color {
        project.progress >= 1.0
            ? ViabarColor.success
            : Color(hex: project.accentColor)
    }

    private var topMilestone: Milestone? {
        project.unfinishedMilestones.first
    }

    private var reminderDate: Date? {
        if let milestoneReminder = topMilestone?.reminder,
           let date = milestoneReminder.nextFireDate {
            return date
        }
        return project.reminder?.nextFireDate
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

    private var cardShadowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.16)
    }

    private var reminderTextColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.78) : Color.gray.opacity(0.88)
    }

    private var progressTintColor: Color {
        progressColor(at: project.progress)
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
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: iconFrameSize, height: iconFrameSize)

                Text(project.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, cardHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: headerHeight, maxHeight: headerHeight, alignment: .center)
            .background(accentColor)

            VStack(alignment: .leading, spacing: 8) {
                if let milestone = topMilestone {
                    HStack(spacing: 4) {
                        Image(systemName: "star.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                            .frame(width: iconFrameSize, height: iconFrameSize, alignment: .center)

                        Text(milestone.title)
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                } else {
                    HStack { Spacer() }
                        .frame(height: iconFrameSize)
                }

                if let reminderDate {
                    HStack(spacing: 4) {
                        Image(systemName: "alarm")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.72))
                            .frame(width: iconFrameSize, height: 18, alignment: .center)

                        Text(reminderDate.formattedOverviewReminder)
                            .font(.callout)
                            .foregroundStyle(reminderTextColor)
                    }
                    .frame(height: 18)
                } else {
                    HStack { Spacer() }
                        .frame(height: 18)
                }

                HStack(alignment: .center, spacing: 10) {
                    GeometryReader { proxy in
                        let stepCount = max(progressStepCount - 1, 1)
                        let availableWidth = max(0, proxy.size.width - progressDotSize)
                        let stepSpacing = availableWidth / CGFloat(stepCount)

                        ZStack(alignment: .leading) {
                            ForEach(0..<progressStepCount, id: \.self) { index in
                                let colorProgress = Double(index) / Double(stepCount)
                                Circle()
                                    .fill(index < filledStepCount ? progressColor(at: colorProgress) : Color.gray.opacity(0.22))
                                    .frame(width: progressDotSize, height: progressDotSize)
                                    .offset(x: CGFloat(index) * stepSpacing)
                            }
                        }
                    }
                    .frame(height: progressDotSize)

                    Text(progressPercentText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(progressTintColor)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, cardHorizontalPadding)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cardBackground)
        }
        .frame(height: 142)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: cardShadowColor, radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    var nextFireDate: Date? {
        if type == "single" {
            return fireTimestamp
        }

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
    var formattedOverviewReminder: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}

#Preview {
    ContentView()
        .environment(ServiceContainer())
        .modelContainer(for: Project.self, inMemory: true)
}
