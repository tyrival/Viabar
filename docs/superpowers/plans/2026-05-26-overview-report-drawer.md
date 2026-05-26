# Overview Report Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在总览页面加入与备忘录面板一致的只读右侧汇总栏，展示本周完成、下周待办和本月完成，并支持按分组复制任务树。

**Architecture:** 新增 `OverviewReportBuilder` 作为纯数据边界，根据项目树、有效提醒时间轴、`Date` 与 `Calendar` 产出三个稳定排序的只读分组及复制正文。新增 `OverviewReportDrawerView` 只负责抽屉、分组和卡片渲染；`ContentView` 查询时间轴并管理总览抽屉显隐，不改动项目详情备忘录的数据语义。

**Tech Stack:** SwiftUI, SwiftData `@Query`, AppKit `NSPasteboard` / `NSCursor`, Swift Testing, `AppLocalization`, `ViabarColor`.

**Verification Constraint:** 仓库指令要求未明确声明时不编译代码。因此本计划坚持先写测试再实现，但默认不运行 `xcodebuild` 或 XCTest；只运行源码检查与 `git diff --check`。需要执行测试时，先取得用户明确授权。

---

## File Map

- Create: `Viabar/Models/OverviewReport.swift`
  - 只读分组/卡片/任务树模型、自然周期计算、完成内容提取、下周时间轴映射、去重、复制正文。
- Create: `Viabar/Views/MainPanel/OverviewReportDrawerView.swift`
  - 总览右栏 UI、内部切换按钮、分组复制反馈、只读卡片、面板视觉样式。
- Modify: `Viabar/ContentView.swift`
  - 查询 `NotificationScheduleEntry`，持有总览面板状态，为总览预留右侧空间并挂载右栏。
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`
  - 中文标题、空状态、复制帮助文本、归档标签和面板展开/收起帮助文本。
- Modify: `Viabar/en.lproj/Localizable.strings`
  - 对应英文文案。
- Modify: `ViabarTests/ViabarTests.swift`
  - 构建器的周期、归档、提醒展开、去重与复制格式测试。

### Task 1: 完成周期模型与复制正文

**Files:**
- Create: `Viabar/Models/OverviewReport.swift`
- Modify: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: 在测试文件中增加完成分组与复制正文样例**

在 `ViabarTests/ViabarTests.swift` 的 `MenuBarContentTests` 后增加新的测试结构，使用固定的 ISO 星期一日历，验证自然周/月、父任务上下文和归档完成卡片：

```swift
struct OverviewReportTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 26, hour: 12))!
    }

    @Test func completedSectionsIncludeOnlyTasksCompletedInTheirPeriod() {
        let project = Project(title: "Website", orderIndex: 0)
        project.isArchived = true
        let standalone = Milestone(title: "Launch", orderIndex: 0, isCompleted: true)
        standalone.completedAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 9))
        standalone.project = project

        let parent = Milestone(title: "Design System", orderIndex: 1, isCompleted: true)
        parent.project = project
        let thisWeek = SubTask(title: "Tokens", orderIndex: 0, isCompleted: true)
        thisWeek.completedAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 26, hour: 10))
        thisWeek.milestone = parent
        let earlierThisMonth = SubTask(title: "Typography", orderIndex: 1, isCompleted: true)
        earlierThisMonth.completedAt = calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 10))
        earlierThisMonth.milestone = parent
        parent.subtasks = [thisWeek, earlierThisMonth]
        project.milestones = [standalone, parent]

        let report = OverviewReportBuilder.makeReport(
            projects: [project],
            scheduleEntries: [],
            now: now,
            calendar: calendar
        )

        #expect(report.thisWeek.cards[0].project.isArchived)
        #expect(report.thisWeek.cards[0].groups.map(\.title) == ["Launch", "Design System"])
        #expect(report.thisWeek.cards[0].groups[1].subtasks.map(\.title) == ["Tokens"])
        #expect(report.thisMonth.cards[0].groups[1].subtasks.map(\.title) == ["Tokens", "Typography"])
        #expect(report.thisWeek.copyText == """
        1. Website
        - Launch
        - Design System
          - Tokens
        """)
    }

    @Test func completionIntervalUsesExclusiveEndBoundary() {
        let project = Project(title: "Boundary")
        let task = Milestone(title: "Next Week", isCompleted: true)
        task.completedAt = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))
        task.project = project
        project.milestones = [task]

        let report = OverviewReportBuilder.makeReport(
            projects: [project],
            scheduleEntries: [],
            now: now,
            calendar: calendar
        )

        #expect(report.thisWeek.cards.isEmpty)
        #expect(report.thisMonth.cards.isEmpty)
    }
}
```

- [ ] **Step 2: 不编译，仅确认测试预期与新 API 引用完整**

Run:

```bash
rg -n "OverviewReportTests|OverviewReportBuilder|completionIntervalUsesExclusiveEndBoundary" ViabarTests/ViabarTests.swift
```

Expected: 列出新测试与尚待实现的 `OverviewReportBuilder.makeReport(...)` 引用。根据用户约束，本步骤不运行将产生编译动作的测试命令。

- [ ] **Step 3: 新增完成分组的只读模型与构建逻辑**

创建 `Viabar/Models/OverviewReport.swift`，先实现完成范围和复制正文；类型签名在后续任务继续扩展下周待办：

```swift
import Foundation

enum OverviewReportSectionKind: CaseIterable, Hashable {
    case thisWeek
    case nextWeek
    case thisMonth
}

struct OverviewReport: Equatable {
    let thisWeek: OverviewReportSection
    let nextWeek: OverviewReportSection
    let thisMonth: OverviewReportSection

    var sections: [OverviewReportSection] { [thisWeek, nextWeek, thisMonth] }
}

struct OverviewReportSection: Equatable, Identifiable {
    let kind: OverviewReportSectionKind
    let cards: [OverviewReportProjectCard]

    var id: OverviewReportSectionKind { kind }
    var copyText: String {
        cards.enumerated().map { index, card in
            (["\(index + 1). \(card.project.title)"] + card.copyLines).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

struct OverviewReportProjectCard: Equatable, Identifiable {
    let project: Project
    let groups: [OverviewReportTaskGroup]

    var id: UUID { project.projectId }
    var copyLines: [String] {
        groups.flatMap { group in
            ["- \(group.title)"] + group.subtasks.map { "  - \($0.title)" }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.project.projectId == rhs.project.projectId && lhs.groups == rhs.groups
    }
}

struct OverviewReportTaskGroup: Equatable, Identifiable {
    let milestoneID: UUID
    let title: String
    let subtasks: [OverviewReportSubTaskRow]

    var id: UUID { milestoneID }
}

struct OverviewReportSubTaskRow: Equatable, Identifiable {
    let taskID: UUID
    let title: String

    var id: UUID { taskID }
}

enum OverviewReportBuilder {
    static func makeReport(
        projects: [Project],
        scheduleEntries: [NotificationScheduleEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> OverviewReport {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let month = calendar.dateInterval(of: .month, for: now)!
        return OverviewReport(
            thisWeek: section(.thisWeek, cards: completedCards(from: projects, in: week)),
            nextWeek: section(.nextWeek, cards: []),
            thisMonth: section(.thisMonth, cards: completedCards(from: projects, in: month))
        )
    }

    private static func section(
        _ kind: OverviewReportSectionKind,
        cards: [OverviewReportProjectCard]
    ) -> OverviewReportSection {
        OverviewReportSection(kind: kind, cards: cards)
    }

    private static func completedCards(
        from projects: [Project],
        in interval: DateInterval
    ) -> [OverviewReportProjectCard] {
        sortedProjects(projects).compactMap { project in
            let groups = project.milestones
                .sorted { $0.orderIndex < $1.orderIndex }
                .compactMap { milestone -> OverviewReportTaskGroup? in
                    if milestone.subtasks.isEmpty {
                        guard contains(milestone.completedAt, in: interval) else { return nil }
                        return OverviewReportTaskGroup(
                            milestoneID: milestone.milestoneId,
                            title: milestone.title,
                            subtasks: []
                        )
                    }
                    let subtasks = milestone.subtasks
                        .sorted { $0.orderIndex < $1.orderIndex }
                        .filter { contains($0.completedAt, in: interval) }
                        .map { OverviewReportSubTaskRow(taskID: $0.taskId, title: $0.title) }
                    guard !subtasks.isEmpty else { return nil }
                    return OverviewReportTaskGroup(
                        milestoneID: milestone.milestoneId,
                        title: milestone.title,
                        subtasks: subtasks
                    )
                }
            guard !groups.isEmpty else { return nil }
            return OverviewReportProjectCard(project: project, groups: groups)
        }
    }

    private static func contains(_ date: Date?, in interval: DateInterval) -> Bool {
        guard let date else { return false }
        return date >= interval.start && date < interval.end
    }

    private static func sortedProjects(_ projects: [Project]) -> [Project] {
        projects.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.orderIndex < $1.orderIndex
        }
    }
}
```

- [ ] **Step 4: 静态核对完成规则与格式字符串**

Run:

```bash
rg -n "completedCards|date >= interval.start|date < interval.end|copyText|  - " Viabar/Models/OverviewReport.swift ViabarTests/ViabarTests.swift
git diff --check -- Viabar/Models/OverviewReport.swift ViabarTests/ViabarTests.swift
```

Expected: 能看到半开区间及缩进复制实现；`git diff --check` 无输出。XCTest 仅在用户随后授权编译验证时运行。

- [ ] **Step 5: 提交完成周期模型**

```bash
git add -- Viabar/Models/OverviewReport.swift ViabarTests/ViabarTests.swift
git commit -m "feat: add overview completed report model"
```

### Task 2: 下周有效提醒映射、项目级展开与去重

**Files:**
- Modify: `Viabar/Models/OverviewReport.swift`
- Modify: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: 增加有效时间轴、归档排除和去重测试**

在 `OverviewReportTests` 中增加下周待办测试。用 `NotificationScheduleEntry` 而非 `Reminder` 驱动显示，从而锁定归档语义：

```swift
@Test func nextWeekExpandsProjectReminderAndDeduplicatesSubtaskReminder() {
    let project = Project(title: "App", orderIndex: 0)
    let parent = Milestone(title: "Store Review", orderIndex: 0)
    parent.project = project
    let screenshots = SubTask(title: "Screenshots", orderIndex: 0)
    let copy = SubTask(title: "Localized Copy", orderIndex: 1)
    screenshots.milestone = parent
    copy.milestone = parent
    parent.subtasks = [screenshots, copy]
    project.milestones = [parent]
    let nextWeek = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 9))!
    let entries = [
        NotificationScheduleEntry(
            ownerId: project.projectId,
            ownerKind: "project",
            projectId: project.projectId,
            projectTitle: project.title,
            body: "",
            fireDate: nextWeek
        ),
        NotificationScheduleEntry(
            ownerId: screenshots.taskId,
            ownerKind: "subtask",
            projectId: project.projectId,
            projectTitle: project.title,
            body: screenshots.title,
            fireDate: nextWeek
        ),
    ]

    let report = OverviewReportBuilder.makeReport(
        projects: [project],
        scheduleEntries: entries,
        now: now,
        calendar: calendar
    )

    #expect(report.nextWeek.cards[0].groups[0].title == "Store Review")
    #expect(report.nextWeek.cards[0].groups[0].subtasks.map(\.title) == ["Screenshots", "Localized Copy"])
    #expect(report.nextWeek.copyText == """
    1. App
    - Store Review
      - Screenshots
      - Localized Copy
    """)
}

@Test func nextWeekUsesOnlyActiveProjectsWithFutureScheduleEntries() {
    let archived = Project(title: "Archived", orderIndex: 0)
    archived.isArchived = true
    let task = Milestone(title: "Hidden Task", orderIndex: 0)
    task.project = archived
    archived.milestones = [task]
    archived.reminder = Reminder(type: "single", fireTimestamp: now)
    let entry = NotificationScheduleEntry(
        ownerId: task.milestoneId,
        ownerKind: "milestone",
        projectId: archived.projectId,
        projectTitle: archived.title,
        body: task.title,
        fireDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))!
    )

    let report = OverviewReportBuilder.makeReport(
        projects: [archived],
        scheduleEntries: [entry],
        now: now,
        calendar: calendar
    )

    #expect(report.nextWeek.cards.isEmpty)
}
```

- [ ] **Step 2: 静态确认测试针对时间轴而非提醒配置**

Run:

```bash
rg -n "nextWeekExpandsProjectReminder|NotificationScheduleEntry|archived.reminder|nextWeek.cards.isEmpty" ViabarTests/ViabarTests.swift
```

Expected: 测试同时构造保留的归档 `Reminder` 与时间轴条目，但预期归档卡片为空。

- [ ] **Step 3: 在构建器中实现下一自然周和任务树聚合**

在 `makeReport(...)` 中计算下一周并替换空的 `.nextWeek` 分组，随后添加以下辅助方法。对每个项目按现有结构构建 `OverviewReportTaskGroup`，用集合去重子任务：

```swift
let nextWeek = DateInterval(
    start: week.end,
    end: calendar.date(byAdding: .weekOfYear, value: 1, to: week.end)!
)

return OverviewReport(
    thisWeek: section(.thisWeek, cards: completedCards(from: projects, in: week)),
    nextWeek: section(
        .nextWeek,
        cards: plannedCards(from: projects, scheduleEntries: scheduleEntries, in: nextWeek)
    ),
    thisMonth: section(.thisMonth, cards: completedCards(from: projects, in: month))
)
```

```swift
private static func plannedCards(
    from projects: [Project],
    scheduleEntries: [NotificationScheduleEntry],
    in interval: DateInterval
) -> [OverviewReportProjectCard] {
    let entriesByProject = Dictionary(
        grouping: scheduleEntries.filter { contains($0.fireDate, in: interval) },
        by: \.projectId
    )

    return sortedProjects(projects.filter { !$0.isArchived }).compactMap { project in
        guard let entries = entriesByProject[project.projectId] else { return nil }
        let groups = plannedGroups(for: project, entries: entries)
        return groups.isEmpty ? nil : OverviewReportProjectCard(project: project, groups: groups)
    }
}

private static func plannedGroups(
    for project: Project,
    entries: [NotificationScheduleEntry]
) -> [OverviewReportTaskGroup] {
    var requestedMilestones = Set<UUID>()
    var requestedSubtasks = Set<UUID>()

    for entry in entries {
        switch entry.ownerKind {
        case "milestone":
            if let milestone = project.milestones.first(where: { $0.milestoneId == entry.ownerId }),
               !milestone.isCompleted {
                requestedMilestones.insert(milestone.milestoneId)
            }
        case "subtask":
            if let subtask = project.milestones.flatMap(\.subtasks).first(where: { $0.taskId == entry.ownerId }),
               !subtask.isCompleted {
                requestedSubtasks.insert(subtask.taskId)
            }
        case "project":
            guard let milestone = project.milestones
                .sorted(by: { $0.orderIndex < $1.orderIndex })
                .first(where: { !$0.isCompleted })
            else { continue }
            requestedMilestones.insert(milestone.milestoneId)
            for subtask in milestone.subtasks where !subtask.isCompleted {
                requestedSubtasks.insert(subtask.taskId)
            }
        default:
            continue
        }
    }

    return project.milestones
        .sorted { $0.orderIndex < $1.orderIndex }
        .compactMap { milestone in
            let subtasks = milestone.subtasks
                .sorted { $0.orderIndex < $1.orderIndex }
                .filter { requestedSubtasks.contains($0.taskId) }
                .map { OverviewReportSubTaskRow(taskID: $0.taskId, title: $0.title) }
            guard requestedMilestones.contains(milestone.milestoneId) || !subtasks.isEmpty else {
                return nil
            }
            return OverviewReportTaskGroup(
                milestoneID: milestone.milestoneId,
                title: milestone.title,
                subtasks: subtasks
            )
        }
}

private static func contains(_ date: Date, in interval: DateInterval) -> Bool {
    date >= interval.start && date < interval.end
}
```

- [ ] **Step 4: 静态核对提醒范围与去重实现**

Run:

```bash
rg -n "nextWeek|plannedCards|project.isArchived|ownerKind|requestedSubtasks|requestedMilestones" Viabar/Models/OverviewReport.swift ViabarTests/ViabarTests.swift
git diff --check -- Viabar/Models/OverviewReport.swift ViabarTests/ViabarTests.swift
```

Expected: 可定位下一自然周、归档排除、三种 owner 分支及集合去重逻辑；`git diff --check` 无输出。

- [ ] **Step 5: 提交下周待办构建逻辑**

```bash
git add -- Viabar/Models/OverviewReport.swift ViabarTests/ViabarTests.swift
git commit -m "feat: build overview next week report entries"
```

### Task 3: 右栏视图、卡片样式与本地化文本

**Files:**
- Create: `Viabar/Views/MainPanel/OverviewReportDrawerView.swift`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`
- Modify: `Viabar/en.lproj/Localizable.strings`

- [ ] **Step 1: 增加中英文界面键值**

在中文资源文件追加：

```text
"本周完成" = "本周完成";
"下周待办" = "下周待办";
"本月完成" = "本月完成";
"已归档" = "已归档";
"复制本周完成" = "复制本周完成";
"复制下周待办" = "复制下周待办";
"复制本月完成" = "复制本月完成";
"本周暂无完成内容" = "本周暂无完成内容";
"下周暂无待办提醒" = "下周暂无待办提醒";
"本月暂无完成内容" = "本月暂无完成内容";
"收起汇总面板" = "收起汇总面板";
"展开汇总面板" = "展开汇总面板";
```

在英文资源文件追加：

```text
"本周完成" = "Completed This Week";
"下周待办" = "Next Week";
"本月完成" = "Completed This Month";
"已归档" = "Archived";
"复制本周完成" = "Copy Completed This Week";
"复制下周待办" = "Copy Next Week";
"复制本月完成" = "Copy Completed This Month";
"本周暂无完成内容" = "Nothing completed this week";
"下周暂无待办提醒" = "No reminders next week";
"本月暂无完成内容" = "Nothing completed this month";
"收起汇总面板" = "Hide Summary";
"展开汇总面板" = "Show Summary";
```

- [ ] **Step 2: 创建只读抽屉视图骨架并封装分组文本**

创建 `Viabar/Views/MainPanel/OverviewReportDrawerView.swift`，视图接受完整 report 和面板切换闭包，不直接查询或修改项目：

```swift
import AppKit
import SwiftUI

struct OverviewReportDrawerView: View {
    let report: OverviewReport
    let onToggleVisibility: () -> Void

    @State private var copiedKind: OverviewReportSectionKind?
    @State private var hoveredCopyKind: OverviewReportSectionKind?
    @State private var isToggleHovered = false

    private let buttonSize: CGFloat = 36
    private let edgeInset: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                toggleButton
            }
            .padding(.trailing, edgeInset)
            .frame(height: buttonSize + edgeInset * 2)

            ForEach(report.sections) { section in
                Divider()
                OverviewReportSectionView(
                    section: section,
                    showsCopiedTag: copiedKind == section.kind,
                    isCopyButtonHovered: hoveredCopyKind == section.kind,
                    onCopy: { copy(section) },
                    onCopyHover: { isHovering in setCopyHover(isHovering, for: section.kind) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OverviewReportDrawerStyle.panelBackground)
    }

    private var toggleButton: some View {
        Button(action: onToggleVisibility) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: buttonSize, height: buttonSize)
                .background(OverviewReportDrawerStyle.toggleBackground(isHovered: isToggleHovered))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("收起汇总面板")
        .onHover { isToggleHovered = $0 }
    }

    private func copy(_ section: OverviewReportSection) {
        guard !section.copyText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(section.copyText, forType: .string)
        withAnimation(.easeInOut(duration: 0.12)) { copiedKind = section.kind }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                if copiedKind == section.kind { copiedKind = nil }
            }
        }
    }

    private func setCopyHover(_ hovering: Bool, for kind: OverviewReportSectionKind) {
        hoveredCopyKind = hovering ? kind : nil
        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
}
```

- [ ] **Step 3: 添加分组和项目卡片子视图**

在同文件追加只读分组与卡片。文本使用 `LocalizedStringKey` 映射，项目名强制主蓝色，归档标签只读显示：

```swift
private struct OverviewReportSectionView: View {
    let section: OverviewReportSection
    let showsCopiedTag: Bool
    let isCopyButtonHovered: Bool
    let onCopy: () -> Void
    let onCopyHover: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if showsCopiedTag {
                    Text("已复制")
                        .font(.caption2)
                        .foregroundStyle(OverviewReportDrawerStyle.copiedForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OverviewReportDrawerStyle.copiedBackground, in: Capsule())
                }
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(isCopyButtonHovered ? AnyShapeStyle(ViabarColor.primary) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .disabled(section.cards.isEmpty)
                .help(copyHelp)
                .onHover(perform: onCopyHover)
            }
            .frame(height: 22)

            if section.cards.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            } else {
                ForEach(section.cards) { card in
                    OverviewReportCardView(card: card)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var title: LocalizedStringKey {
        switch section.kind {
        case .thisWeek: "本周完成"
        case .nextWeek: "下周待办"
        case .thisMonth: "本月完成"
        }
    }

    private var copyHelp: LocalizedStringKey {
        switch section.kind {
        case .thisWeek: "复制本周完成"
        case .nextWeek: "复制下周待办"
        case .thisMonth: "复制本月完成"
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch section.kind {
        case .thisWeek: "本周暂无完成内容"
        case .nextWeek: "下周暂无待办提醒"
        case .thisMonth: "本月暂无完成内容"
        }
    }
}

private struct OverviewReportCardView: View {
    let card: OverviewReportProjectCard

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: card.project.sfSymbolName)
                    .foregroundStyle(Color(hex: card.project.accentColor))
                Text(card.project.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ViabarColor.primary)
                    .lineLimit(nil)
                Spacer(minLength: 8)
                if card.project.isArchived {
                    Text("已归档")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(card.groups) { group in
                Text(group.title)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(group.subtasks) { subtask in
                    Text(subtask.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(OverviewReportDrawerStyle.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OverviewReportDrawerStyle.cardBorder, lineWidth: 1)
        }
    }
}
```

- [ ] **Step 4: 添加与备忘录一致的深浅色语义样式**

在同文件底部追加样式常量，沿用 `ViabarColor.mainPanelMemoBackground`，卡片配色使用备忘录现有深浅色分支：

```swift
private enum OverviewReportDrawerStyle {
    static let panelBackground = ViabarColor.mainPanelMemoBackground
    static let copiedForeground = Color(nsColor: .systemGreen)
    static let copiedBackground = Color(nsColor: .systemGreen).opacity(0.14)

    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.25, alpha: 0.54)
            : NSColor.white
    })

    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.52, alpha: 0.36)
            : NSColor.separatorColor.withAlphaComponent(0.18)
    })

    static func toggleBackground(isHovered: Bool) -> some View {
        Circle()
            .fill(ViabarColor.panelInputBackground)
            .overlay { Circle().fill(.primary.opacity(isHovered ? 0.06 : 0)) }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
    }
}
```

- [ ] **Step 5: 静态验证视图规则与本地化覆盖后提交**

Run:

```bash
rg -n "本周完成|下周待办|本月完成|已归档|收起汇总面板|复制本周完成" Viabar/Views/MainPanel/OverviewReportDrawerView.swift Viabar/zh-Hans.lproj/Localizable.strings Viabar/en.lproj/Localizable.strings
rg -n "mainPanelMemoBackground|doc.on.doc|pointingHand|ViabarColor.primary|lineLimit\\(nil\\)|padding\\(\\.leading, 18\\)" Viabar/Views/MainPanel/OverviewReportDrawerView.swift
git diff --check -- Viabar/Views/MainPanel/OverviewReportDrawerView.swift Viabar/zh-Hans.lproj/Localizable.strings Viabar/en.lproj/Localizable.strings
git add -- Viabar/Views/MainPanel/OverviewReportDrawerView.swift Viabar/zh-Hans.lproj/Localizable.strings Viabar/en.lproj/Localizable.strings
git commit -m "feat: add overview report drawer UI"
```

Expected: 所有界面字符串在两个语言资源中存在；视觉规则可由检索定位；`git diff --check` 无输出。

### Task 4: 将汇总栏接入总览布局

**Files:**
- Modify: `Viabar/ContentView.swift:5-484`

- [ ] **Step 1: 增加时间轴查询、总览显隐状态与 report 计算属性**

在现有 `@Query` / `@State` 和属性区域加入：

```swift
@Query(sort: \NotificationScheduleEntry.fireDate) private var notificationScheduleEntries: [NotificationScheduleEntry]

@State private var isOverviewReportDrawerVisible: Bool = true

private var isOverviewSelected: Bool {
    switch selection {
    case .overview, .none: true
    case .project: false
    }
}

private var overviewReport: OverviewReport {
    OverviewReportBuilder.makeReport(
        projects: allProjects,
        scheduleEntries: notificationScheduleEntries,
        now: Date()
    )
}
```

- [ ] **Step 2: 在 ZStack 中只为总览挂载抽屉并应用动画**

在当前 `memoDrawer` 分支旁加入总览分支，并让动画覆盖总览状态：

```swift
if isOverviewSelected, isOverviewReportDrawerVisible {
    overviewReportDrawer
        .transition(.move(edge: .trailing))
}
```

```swift
.animation(.easeInOut(duration: 0.2), value: isOverviewReportDrawerVisible)
```

新增抽屉包装属性，保持与备忘录相同的外层分隔与宽度：

```swift
private var overviewReportDrawer: some View {
    HStack(spacing: 0) {
        Divider()
        OverviewReportDrawerView(
            report: overviewReport,
            onToggleVisibility: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOverviewReportDrawerVisible = false
                }
            }
        )
        .frame(width: memoDrawerWidth)
    }
    .frame(maxHeight: .infinity)
    .background(ViabarColor.mainPanelBackground)
    .ignoresSafeArea(.container, edges: [.top, .bottom])
}
```

- [ ] **Step 3: 为收起状态提供面板外的重新展开入口，并给总览内容预留空间**

按钮展开时位于面板内部；面板收起后必须存在可恢复入口，因此在顶栏仅于收起状态渲染 `sidebar.right` 按钮：

```swift
private var overviewReportRevealButton: some View {
    Button {
        withAnimation(.easeInOut(duration: 0.2)) {
            isOverviewReportDrawerVisible = true
        }
    } label: {
        Image(systemName: "sidebar.right")
            .font(.system(size: toolbarButtonIconSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: toolbarButtonSize, height: toolbarButtonSize)
            .background(toolbarButtonBackground(isHovered: hoveredToolbarButton == .overviewReport))
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("展开汇总面板")
    .onHover { hoveredToolbarButton = $0 ? .overviewReport : nil }
}
```

在 `ToolbarButtonKind` 增加 `.overviewReport`，在 `mainToolbarLayer` 的搜索按钮后仅当总览面板已经收起时插入：

```swift
if isOverviewSelected, !isOverviewReportDrawerVisible {
    overviewReportRevealButton
}
```

将总览内容传入抽屉预留值：

```swift
OverviewDashboardView(
    projects: allProjects,
    overviewScope: settingsRecords.first?.overviewScope,
    trailingPanelWidth: isOverviewReportDrawerVisible ? memoDrawerWidth : 0,
    onSelectProject: { selection = .project($0) },
    onEditProject: { overviewEditProject = $0 },
    onArchiveProject: { overviewArchiveProject = $0 },
    onDeleteProject: { overviewDeleteProject = $0 }
)
```

修改总览视图使卡片区域避让右栏：

```swift
let trailingPanelWidth: CGFloat

// In body:
.padding(.trailing, trailingPanelWidth)
```

同时令顶端渐变与搜索控件避让展开的汇总面板：

```swift
private var visibleRightPanelWidth: CGFloat {
    if selectedProject != nil && isMemoDrawerVisible { return memoDrawerWidth }
    if isOverviewSelected && isOverviewReportDrawerVisible { return memoDrawerWidth }
    return 0
}
```

用 `visibleRightPanelWidth` 替换渐变和 toolbar trailing 计算中只检查备忘录的分支，确保搜索不会落在总览面板下方。

- [ ] **Step 4: 静态检查只在总览展示汇总面板且项目页仍使用备忘录**

Run:

```bash
rg -n "notificationScheduleEntries|isOverviewReportDrawerVisible|overviewReportDrawer|OverviewReportDrawerView|visibleRightPanelWidth|isMemoDrawerVisible|memoDrawer" Viabar/ContentView.swift
git diff --check -- Viabar/ContentView.swift
```

Expected: 总览和项目详情各有独立显隐状态，右侧宽度统一走面板占位；`git diff --check` 无输出。

- [ ] **Step 5: 提交总览接入改动**

```bash
git add -- Viabar/ContentView.swift
git commit -m "feat: integrate report drawer into overview"
```

### Task 5: 最终静态验收与未编译交付说明

**Files:**
- Verify: `Viabar/Models/OverviewReport.swift`
- Verify: `Viabar/Views/MainPanel/OverviewReportDrawerView.swift`
- Verify: `Viabar/ContentView.swift`
- Verify: `Viabar/zh-Hans.lproj/Localizable.strings`
- Verify: `Viabar/en.lproj/Localizable.strings`
- Verify: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: 核对设计覆盖面**

Run:

```bash
rg -n "thisWeek|nextWeek|thisMonth|completedAt|NotificationScheduleEntry|ownerKind|copyText|isArchived" Viabar/Models/OverviewReport.swift ViabarTests/ViabarTests.swift
rg -n "sidebar.right|doc.on.doc|已归档|mainPanelMemoBackground|ViabarColor.primary|pointingHand" Viabar/Views/MainPanel/OverviewReportDrawerView.swift Viabar/ContentView.swift
rg -n "本周完成|下周待办|本月完成|已归档|汇总面板" Viabar/zh-Hans.lproj/Localizable.strings Viabar/en.lproj/Localizable.strings
```

Expected: 每项已批准需求都有对应实现或测试位置。

- [ ] **Step 2: 执行允许范围内的补丁质量检查**

Run:

```bash
git diff --check bedcbbe..HEAD
git diff --check
git status --short --branch
```

Expected: 两次 `git diff --check` 均无输出；状态中不包含未预期的实现文件。若仍保留视觉预览阶段的 `.gitignore` 工作区变更，明确报告其为未纳入功能提交的独立变更。

- [ ] **Step 3: 记录被约束跳过的编译验证**

不要运行以下命令，除非用户明确改为要求编译或测试：

```bash
# Deferred pending explicit user approval:
# xcodebuild test -project Viabar.xcodeproj -scheme Viabar -only-testing:ViabarTests
```

交付说明中明确写出：已补充单元测试源码并执行静态检查，但遵照用户要求未运行 `xcodebuild`/XCTest。
