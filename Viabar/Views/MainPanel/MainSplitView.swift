import SwiftUI
import SwiftData

// MARK: - MainSplitView

/// 主面板布局：里程碑列表占满，备忘录从右侧滑入/收起。
/// 右上角按钮切换备忘录面板的展开/收起状态。
struct MainSplitView: View {
    let project: Project
    var reservesMemoDrawer: Bool = false
    var memoPanelWidth: CGFloat = 360
    var navigationRequest: GlobalSearchNavigationRequest? = nil

    var body: some View {
        MilestoneListView(
            project: project,
            showsHeader: false,
            navigationRequest: navigationRequest
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, reservesMemoDrawer ? memoPanelWidth : 0)
    }
}

// MARK: - Preview

#Preview {
    MainSplitView(project: Project(title: "示例项目"), reservesMemoDrawer: true)
        .environment(ServiceContainer())
        .modelContainer(for: Project.self, inMemory: true)
}
