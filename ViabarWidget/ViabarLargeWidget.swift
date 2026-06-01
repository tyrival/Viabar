import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

enum ViabarWidgetState {
    case needsProjectSelection
    case unavailableProject
    case unreadableData
    case content(WidgetProjectContent)
}

struct ViabarWidgetEntry: TimelineEntry {
    let date: Date
    let state: ViabarWidgetState
    let dateFormatPattern: String?
}

struct ViabarWidgetProvider: AppIntentTimelineProvider {
    let rowBudget: Int

    init(rowBudget: Int) {
        self.rowBudget = rowBudget
    }

    func placeholder(in context: Context) -> ViabarWidgetEntry {
        ViabarWidgetEntry(
            date: .now,
            state: .needsProjectSelection,
            dateFormatPattern: nil
        )
    }

    func snapshot(
        for configuration: SelectWidgetProjectIntent,
        in context: Context
    ) async -> ViabarWidgetEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: SelectWidgetProjectIntent,
        in context: Context
    ) async -> Timeline<ViabarWidgetEntry> {
        let entry = await entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    @MainActor
    private func entry(for configuration: SelectWidgetProjectIntent) -> ViabarWidgetEntry {
        guard let selectedID = configuration.project?.id else {
            return ViabarWidgetEntry(
                date: .now,
                state: .needsProjectSelection,
                dateFormatPattern: nil
            )
        }

        do {
            let container = try SharedModelContainer.makeWidgetContainer()
            let context = container.mainContext
            let projects = try context.fetch(FetchDescriptor<Project>())
            let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
            guard let project = WidgetContentBuilder.activeProjects(from: projects)
                .first(where: { $0.projectId == selectedID })
            else {
                return ViabarWidgetEntry(
                    date: .now,
                    state: .unavailableProject,
                    dateFormatPattern: settings?.dateFormat
                )
            }

            return ViabarWidgetEntry(
                date: .now,
                state: .content(
                    WidgetContentBuilder.content(
                        for: project,
                        rowBudget: rowBudget,
                        now: .now
                    )
                ),
                dateFormatPattern: settings?.dateFormat
            )
        } catch {
            return ViabarWidgetEntry(
                date: .now,
                state: .unreadableData,
                dateFormatPattern: nil
            )
        }
    }
}

struct ViabarMediumWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SharedModelContainer.mediumWidgetKind,
            intent: SelectWidgetProjectIntent.self,
            provider: ViabarWidgetProvider(
                rowBudget: WidgetContentBuilder.mediumWidgetRowBudget
            )
        ) { entry in
            ViabarWidgetView(entry: entry)
        }
        .configurationDisplayName("Viabar 中号项目")
        .description("在桌面查看并完成项目任务")
        .supportedFamilies([.systemMedium])
    }
}

struct ViabarLargeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SharedModelContainer.largeWidgetKind,
            intent: SelectWidgetProjectIntent.self,
            provider: ViabarWidgetProvider(
                rowBudget: WidgetContentBuilder.largeWidgetRowBudget
            )
        ) { entry in
            ViabarWidgetView(entry: entry)
        }
        .configurationDisplayName("Viabar 大号项目")
        .description("在桌面查看并完成项目任务")
        .supportedFamilies([.systemLarge])
    }
}

struct ViabarWidgetView: View {
    let entry: ViabarWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .needsProjectSelection:
                emptyState("请选择项目", detail: "右键小组件 > 编辑小组件")
            case .unavailableProject:
                emptyState("项目不可用，请重新选择项目", detail: "右键小组件 > 编辑小组件")
            case .unreadableData:
                emptyState("暂时无法读取数据", detail: nil)
            case .content(let content):
                contentView(content)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func contentView(_ content: WidgetProjectContent) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header(content)
            Divider()

            if content.visibleItems.isEmpty, content.hiddenItemCount == 0 {
                emptyState("当前没有未完成任务", detail: nil)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(content.visibleItems) { item in
                        taskRow(item, projectID: content.projectID)
                    }
                }

                if content.hiddenItemCount > 0 {
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("还有 %lld 项未完成", comment: ""),
                            Int64(content.hiddenItemCount)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: 0)
        }
        .widgetURL(ViabarWidgetNavigationURL.project(content.projectID))
    }

    private func header(_ content: WidgetProjectContent) -> some View {
        HStack(spacing: 7) {
            Image(systemName: content.sfSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: content.accentColor))

            Text(content.title)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)

            Spacer(minLength: 10)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "#00BBE1").opacity(0.2))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#00BBE1"),
                                    Color(hex: "#00F9D0"),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * max(0, min(1, content.progress))
                        )
                }
            }
            .frame(width: 72, height: 5)

            Text("\(Int(content.progress * 100))%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)

            Button(intent: RefreshWidgetIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("刷新任务列表")
        }
    }

    private func taskRow(_ item: WidgetTaskItem, projectID: UUID) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Button(intent: ToggleWidgetTaskIntent(kind: item.kind, taskID: item.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Link(destination: taskURL(for: item, projectID: projectID)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: item.kind == .subTask ? 12 : 14))
                        .lineLimit(1)

                    if let reminderDate = item.reminderDate {
                        Text(
                            AppDateFormatter.string(
                                from: reminderDate,
                                pattern: entry.dateFormatPattern
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(reminderColor(item.reminderTone))
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, item.isIndented ? 16 : 0)
    }

    private func taskURL(for item: WidgetTaskItem, projectID: UUID) -> URL {
        switch item.kind {
        case .milestone:
            ViabarWidgetNavigationURL.milestone(projectID: projectID, milestoneID: item.id)
        case .subTask:
            ViabarWidgetNavigationURL.subTask(
                projectID: projectID,
                milestoneID: item.milestoneID,
                subTaskID: item.id
            )
        }
    }

    private func emptyState(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey?
    ) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.callout.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reminderColor(_ tone: WidgetReminderTone?) -> Color {
        switch tone {
        case .overdue:
            .red
        case .todayPending:
            .orange
        case .future, nil:
            .secondary
        }
    }
}

private enum ViabarWidgetNavigationURL {
    static func project(_ projectID: UUID) -> URL {
        url(path: "project/\(projectID.uuidString)")
    }

    static func milestone(projectID: UUID, milestoneID: UUID) -> URL {
        url(path: "milestone/\(projectID.uuidString)/\(milestoneID.uuidString)")
    }

    static func subTask(projectID: UUID, milestoneID: UUID, subTaskID: UUID) -> URL {
        url(path: "subtask/\(projectID.uuidString)/\(milestoneID.uuidString)/\(subTaskID.uuidString)")
    }

    private static func url(path: String) -> URL {
        URL(string: "viabar://navigate/\(path)")!
    }
}
