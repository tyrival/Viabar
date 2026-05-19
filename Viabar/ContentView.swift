import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selection: SidebarSelection? = .overview

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
            case .overview, .none:
                DashboardPlaceholderView()
            case .project(let project):
                MainSplitView(project: project)
            }
        }
    }
}

// MARK: - Dashboard Placeholder (Phase 2: DashboardView)

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
