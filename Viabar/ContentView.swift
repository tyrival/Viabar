import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selection: SidebarSelection? = .overview
    @State private var isMemoDrawerVisible: Bool = true

    private let memoDrawerWidth: CGFloat = 360

    var body: some View {
        ZStack(alignment: .trailing) {
            NavigationSplitView {
                SidebarView(selection: $selection)
            } detail: {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbarBackground(.hidden, for: .automatic)
                    .toolbar(.hidden, for: .windowToolbar)
                    .navigationTitle("")
            }

            if let project = selectedProject, isMemoDrawerVisible {
                memoDrawer(project: project)
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectedProject != nil {
                memoToggleButton
                    .padding(.top, 16)
                    .padding(.trailing, 18)
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

    private func memoDrawer(project: Project) -> some View {
        HStack(spacing: 0) {
            Divider()
            MemoTimelineView(project: project)
                .frame(width: memoDrawerWidth)
        }
        .frame(maxHeight: .infinity)
        .background(.background)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    private var memoToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isMemoDrawerVisible.toggle()
            }
        } label: {
            Image(systemName: isMemoDrawerVisible ? "sidebar.trailing" : "sidebar.leading")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .help(isMemoDrawerVisible ? "收起备忘录" : "展开备忘录")
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
