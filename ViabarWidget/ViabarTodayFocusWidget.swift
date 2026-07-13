import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

enum ViabarTodayFocusState {
    case unavailable
    case empty
    case content([TodayFocusItem])
}

struct ViabarTodayFocusEntry: TimelineEntry {
    let date: Date
    let state: ViabarTodayFocusState
    let dateFormatPattern: String?
    let language: EffectiveAppLanguage
}

struct ViabarTodayFocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> ViabarTodayFocusEntry {
        ViabarTodayFocusEntry(
            date: .now,
            state: .content(Self.placeholderItems),
            dateFormatPattern: nil,
            language: .english
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ViabarTodayFocusEntry) -> Void
    ) {
        Task { @MainActor in
            completion(makeEntry(now: .now))
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<ViabarTodayFocusEntry>) -> Void
    ) {
        Task { @MainActor in
            let now = Date()
            let entry = makeEntry(now: now)
            let items: [TodayFocusItem]
            if case let .content(contentItems) = entry.state {
                items = contentItems
            } else {
                items = []
            }
            let refreshDate = TodayFocusEngine().nextRefreshDate(items: items, now: now)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    @MainActor
    private func makeEntry(now: Date) -> ViabarTodayFocusEntry {
        do {
            let container = try SharedModelContainer.makeWidgetContainer()
            let context = container.mainContext
            let projects = try context.fetch(FetchDescriptor<Project>())
            let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
            let language = AppLanguage.effectiveLanguage(storedValue: settings?.language)
            let items = TodayFocusEngine().items(projects: projects, now: now)
            return ViabarTodayFocusEntry(
                date: now,
                state: items.isEmpty ? .empty : .content(items),
                dateFormatPattern: settings?.dateFormat,
                language: language
            )
        } catch {
            return ViabarTodayFocusEntry(
                date: now,
                state: .unavailable,
                dateFormatPattern: nil,
                language: AppLanguage.effectiveLanguage(storedValue: nil)
            )
        }
    }

    private static let placeholderItems: [TodayFocusItem] = [
        TodayFocusItem(
            projectID: UUID(),
            projectTitle: "Viabar",
            projectSymbolName: "circle.dashed",
            projectAccentColor: ViabarColor.primaryHex,
            projectProgress: 0.72,
            projectOrderIndex: 0,
            taskID: UUID(),
            taskKind: .subTask,
            milestoneID: UUID(),
            taskTitle: "Prepare the next milestone",
            reminderDate: nil,
            source: .rule,
            reason: .today,
            latestCompletionDate: nil
        ),
        TodayFocusItem(
            projectID: UUID(),
            projectTitle: "Mobile App",
            projectSymbolName: "iphone",
            projectAccentColor: "#7C5CFC",
            projectProgress: 0.45,
            projectOrderIndex: 1,
            taskID: UUID(),
            taskKind: .milestone,
            milestoneID: UUID(),
            taskTitle: "Review interaction details",
            reminderDate: nil,
            source: .rule,
            reason: .favorite,
            latestCompletionDate: nil
        ),
        TodayFocusItem(
            projectID: UUID(),
            projectTitle: "Launch",
            projectSymbolName: "paperplane.fill",
            projectAccentColor: "#F59E0B",
            projectProgress: 0.88,
            projectOrderIndex: 2,
            taskID: UUID(),
            taskKind: .subTask,
            milestoneID: UUID(),
            taskTitle: "Finish the release checklist",
            reminderDate: nil,
            source: .rule,
            reason: .stalled(days: 9),
            latestCompletionDate: nil
        ),
    ]
}

struct ViabarTodayFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedModelContainer.todayFocusWidgetKind,
            provider: ViabarTodayFocusProvider()
        ) { entry in
            ViabarTodayFocusWidgetView(entry: entry)
                .environment(\.locale, entry.language.locale)
        }
        .configurationDisplayName("今日推荐")
        .description("展示当前最值得推进的任务")
        .supportedFamilies([.systemLarge])
    }
}

private struct ViabarTodayFocusWidgetView: View {
    let entry: ViabarTodayFocusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.headline)
                    .foregroundStyle(ViabarColor.primary)
                Text(localized("今日推荐"))
                    .font(.headline)
                Spacer()
                Text("Viabar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            switch entry.state {
            case .unavailable:
                messageState(
                    symbol: "exclamationmark.circle",
                    text: localized("暂时无法读取今日推荐")
                )
            case .empty:
                messageState(
                    symbol: "checkmark.circle.fill",
                    text: localized("今天没有需要推进的任务")
                )
            case let .content(items):
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(3))) { item in
                        if item.id != items.first?.id {
                            Divider()
                        }
                        TodayFocusWidgetRow(
                            item: item,
                            dateFormatPattern: entry.dateFormatPattern,
                            language: entry.language
                        )
                    }
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func messageState(symbol: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, language: entry.language)
    }
}

private struct TodayFocusWidgetRow: View {
    let item: TodayFocusItem
    let dateFormatPattern: String?
    let language: EffectiveAppLanguage

    private var accentColor: Color {
        Color(hex: item.projectAccentColor)
    }

    var body: some View {
        HStack(spacing: 10) {
            Link(destination: navigationURL) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(reasonColor)
                        .frame(width: 4, height: 48)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.taskTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Image(systemName: item.projectSymbolName)
                                .foregroundStyle(accentColor)
                            Text(item.projectTitle)
                                .lineLimit(1)
                            Text("·")
                            Text(reasonText)
                                .lineLimit(1)
                            if let reminderDate = item.reminderDate {
                                Text("·")
                                Text(AppDateFormatter.string(
                                    from: reminderDate,
                                    pattern: dateFormatPattern
                                ))
                                .lineLimit(1)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ProgressView(value: item.projectProgress)
                            .tint(accentColor)
                            .controlSize(.mini)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(intent: ToggleWidgetTaskIntent(kind: item.taskKind, taskID: item.taskID)) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(reasonColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var navigationURL: URL {
        switch item.taskKind {
        case .milestone:
            ViabarWidgetNavigationURL.milestone(
                projectID: item.projectID,
                milestoneID: item.milestoneID
            )
        case .subTask:
            ViabarWidgetNavigationURL.subTask(
                projectID: item.projectID,
                milestoneID: item.milestoneID,
                subTaskID: item.taskID
            )
        }
    }

    private var reasonColor: Color {
        switch item.reason {
        case .overdue: .red
        case .today: .orange
        case .favorite: .yellow
        case .stalled: .blue
        case .projectOrder: accentColor
        case .aiSuggested: .purple
        }
    }

    private var reasonText: String {
        switch item.reason {
        case .overdue:
            AppLocalization.string("提醒已逾期", language: language)
        case .today:
            AppLocalization.string("今天需要处理", language: language)
        case .favorite:
            AppLocalization.string("收藏项目", language: language)
        case let .stalled(days):
            AppLocalization.format("已 %d 天未推进", language: language, days)
        case .projectOrder:
            AppLocalization.string("按项目顺序推荐", language: language)
        case .aiSuggested:
            AppLocalization.string("AI 建议", language: language)
        }
    }
}
