import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selection: SidebarSelection? = .overview
    @State private var isMemoDrawerVisible: Bool = true
    @State private var splitVisibility: NavigationSplitViewVisibility = .all

    @Environment(ServiceContainer.self) private var container

    private let memoDrawerWidth: CGFloat = 360
    private let memoToggleButtonSize: CGFloat = 44
    private let memoToggleInset: CGFloat = 6

    private var memoToggleRowHeight: CGFloat {
        memoToggleButtonSize + memoToggleInset * 2
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
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .overview, .none:
            DashboardPlaceholderView()
        case .project(let project):
            MainSplitView(
                project: project,
                reservesMemoDrawer: isMemoDrawerVisible,
                memoPanelWidth: memoDrawerWidth
            )
        }
    }

    private var selectedProject: Project? {
        if case .project(let project) = selection {
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
                    .padding(.top, memoToggleInset)
                    .padding(.trailing, memoToggleInset)
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
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: memoToggleButtonSize, height: memoToggleButtonSize)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .buttonStyle(.plain)
        .help(isMemoDrawerVisible ? "收起备忘录" : "展开备忘录")
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
                        .padding(.trailing, isMemoDrawerVisible ? memoDrawerWidth + 6 : 56)
                }
                .padding(.top, 6)
            }
            .frame(height: 80)

            Spacer()
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .zIndex(1)
    }

    private var toolbarGradientMask: some View {
        LinearGradient(
            stops: [
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.96), location: 0),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.72), location: 0.52),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0), location: 1)
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
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(project.hideCompleted ? .blue : .secondary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .help(project.hideCompleted ? "显示已完成里程碑" : "隐藏已完成里程碑")
    }
}

struct DashboardPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("总览")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Dashboard 将在 Phase 2 中实现")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    ContentView()
        .environment(ServiceContainer())
        .modelContainer(for: Project.self, inMemory: true)
}
