import SwiftUI
import SwiftData

// MARK: - MainSplitView

/// 主面板双栏平铺骨架：
/// 左栏 —— 里程碑与子任务列表，
/// 右栏 —— 流式备忘录及输入框。
/// 与左侧 Sidebar 组合后构成三栏式全局布局。
struct MainSplitView: View {
    let project: Project

    @State private var leftFraction: CGFloat = 0.55

    var body: some View {
        GeometryReader { geo in
            let dividerWidth: CGFloat = 1
            let leftWidth = max(220, min(geo.size.width - 220, geo.size.width * leftFraction))
            let rightWidth = max(220, geo.size.width - leftWidth - dividerWidth)

            HStack(spacing: 0) {
                MilestoneListView(project: project)
                    .frame(width: leftWidth)

                // 可拖拽分隔线
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: dividerWidth)
                    .overlay(
                        // 扩大拖拽热区
                        Rectangle()
                            .fill(.clear)
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let newLeft = leftWidth + value.translation.width
                                        leftFraction = newLeft / geo.size.width
                                    }
                            )
                    )

                MemoTimelineView(project: project)
                    .frame(width: rightWidth)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainSplitView(project: Project(title: "示例项目"))
        .environment(ServiceContainer())
        .modelContainer(for: Project.self, inMemory: true)
}
