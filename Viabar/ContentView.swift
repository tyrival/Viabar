import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \Project.orderIndex) private var allProjects: [Project]

    @State private var selection: SidebarSelection? = .overview
    @State private var isMemoDrawerVisible: Bool = true
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State private var hoveredToolbarButton: ToolbarButtonKind?
    @State private var overviewArchiveProject: Project?
    @State private var overviewEditProject: Project?
    @State private var overviewDeleteProject: Project?

    @Environment(ServiceContainer.self) private var container

    private let memoDrawerWidth: CGFloat = 360
    private let toolbarButtonSize: CGFloat = 36
    private let toolbarButtonIconSize: CGFloat = 16
    private let toolbarEdgeInset: CGFloat = 8
    private let toolbarGradientHeight: CGFloat = 72

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
                Color.clear
                    .frame(height: memoToggleRowHeight)
                Divider()

                MemoTimelineView(project: project)
            }
            .frame(width: memoDrawerWidth)
        }
        .frame(maxHeight: .infinity)
        .background(.background)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
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

    private let cardMinimumWidth: CGFloat = 320
    private let cardSpacing: CGFloat = 14
    private let contentPadding: CGFloat = 18

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

    private let progressStepCount = 30

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: project.sfSymbolName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)

                Text(project.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accentColor)

            VStack(alignment: .leading, spacing: 12) {
                if let milestone = topMilestone {
                    HStack(spacing: 10) {
                        Image(systemName: "star.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                            .frame(width: 24, alignment: .center)

                        Text(milestone.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                } else {
                    HStack { Spacer() }
                        .frame(height: 24)
                }

                if let reminderDate {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.red.opacity(0.88)))

                        Text(reminderDate.formattedOverviewReminder)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                } else {
                    HStack { Spacer() }
                        .frame(height: 24)
                }

                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 3) {
                        ForEach(0..<progressStepCount, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(index < filledStepCount ? ViabarColor.success : Color.gray.opacity(0.22))
                                .frame(width: 4, height: 20)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(progressPercentText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ViabarColor.success)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("编辑项目…", systemImage: "pencil")
            }
            Button {
                onArchive()
            } label: {
                Label("归档…", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除项目", systemImage: "trash")
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
