# Menu Bar Component Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configurable macOS menu bar panel that surfaces current or due tasks, supports completing and quickly adding tasks, synchronizes its filters with Settings, and preserves accurate reminder lifecycle behavior.

**Architecture:** Keep `AppSettings`, project models, `ProjectService`, and `NotificationScheduleService` as the shared source of truth for the main window and the new `MenuBarExtra`. Add a pure menu-bar content builder for filtering/mapping/sorting, a narrow runtime navigation bridge for opening existing detail/highlight routes, and a service-owned reminder update path so the panel never duplicates mutation rules. `ViabarApp` mirrors the persisted enabled setting into `MenuBarExtra(isInserted:)` runtime state so the status item can appear and disappear immediately.

**Tech Stack:** SwiftUI (`MenuBarExtra`, menus, popovers), SwiftData, AppKit window activation, existing Observation runtime controller, Swift Testing.

**Repository Constraint:** Do not run `xcodebuild`, Swift tests, previews, or app-launch workflows unless the user explicitly authorizes compilation. This plan specifies test-first source changes; without later authorization, verification is limited to focused source inspection and `git diff --check`.

---

## File Map

- Modify `Viabar/Models/AppSettings.swift`: persist menu bar icon/scope/mode choices and provide invalid-value fallbacks.
- Modify `ViabarTests/ViabarTests.swift`: specify settings defaults, card projection behavior, service reminder mutation, and notification-lifecycle expectations.
- Create `Viabar/Models/MenuBarContent.swift`: pure card/entry projection for current-task and reminder-task modes.
- Create `Viabar/Models/ReminderDisplay.swift`: shared reminder fire-date, repeat-title, and next-future-date helpers presently trapped inside the milestone view.
- Modify `Viabar/Views/MainPanel/MilestoneListView.swift`: consume shared reminder display helpers and route reminder changes through `ProjectService`.
- Modify `Viabar/Services/ProjectService.swift`: expose service-owned reminder update entry points for tasks and subtasks.
- Modify `Viabar/Services/NotificationScheduleService.swift`: preserve single overdue reminder configuration and advance repeating task/subtask reminders after notification delivery.
- Modify `Viabar/System/AppRuntimeController.swift`: queue and publish menu-bar navigation requests while reusing existing main-window presentation.
- Modify `Viabar/ContentView.swift`: consume external navigation requests through the same selection and orange-highlight route used by global search.
- Modify `Viabar/Views/Settings/SettingsView.swift`: create the dedicated menu bar settings group and synchronize the enable binding to scene insertion state.
- Create `Viabar/Views/MenuBar/MenuBarPanelView.swift`: panel shell, project cards, task rows, quick-add input, and gear menu.
- Modify `Viabar/ViabarApp.swift`: own menu-bar insertion state, render `MenuBarExtra`, inject shared dependencies, and render the selected status-item symbol.
- Modify `Viabar/en.lproj/Localizable.strings`: English copy for menu bar settings, cards, menu and empty/add states.
- Modify `Viabar/zh-Hans.lproj/Localizable.strings`: Simplified-Chinese copy for the same interface.

### Task 1: Persist Menu Bar Settings And Expose Them In General Settings

**Files:**
- Modify: `Viabar/Models/AppSettings.swift`
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add failing settings expectations**

Extend `AppSettingsTests` with the menu bar defaults and fallback resolution:

```swift
@Test func initializesMenuBarComponentDefaults() {
    let settings = AppSettings()

    #expect(settings.menuBarComponentEnabled == false)
    #expect(settings.menuBarIcon == MenuBarIcon.bookmarkFill.rawValue)
    #expect(settings.menuBarProjectScope == MenuBarProjectScope.allProjects.rawValue)
    #expect(settings.menuBarContentMode == MenuBarContentMode.currentTask.rawValue)
}

@Test func resolvesInvalidMenuBarSavedValuesToDocumentedDefaults() {
    #expect(MenuBarIcon.resolve("not-a-symbol") == .bookmarkFill)
    #expect(MenuBarProjectScope.resolve("not-a-scope") == .allProjects)
    #expect(MenuBarContentMode.resolve("not-a-mode") == .currentTask)
    #expect(MenuBarIcon.allCases.map(\.rawValue) == [
        "bookmark", "bookmark.fill", "bookmark.circle", "bookmark.circle.fill",
        "star.rectangle", "star.rectangle.fill", "list.bullet.rectangle",
        "list.bullet.rectangle.fill", "checkmark.seal", "checkmark.seal.fill",
        "checkmark.rectangle", "checkmark.rectangle.fill",
    ])
}
```

- [ ] **Step 2: Leave red execution paused under the repository constraint**

Do not invoke the `ViabarTests` target unless the user separately approves compilation. The newly authored expectations are intentionally unexecuted at this point.

- [ ] **Step 3: Add menu bar setting enums and stored fields**

In `AppSettings.swift`, add the focused persisted-choice types:

```swift
enum MenuBarIcon: String, CaseIterable, Identifiable {
    case bookmark
    case bookmarkFill = "bookmark.fill"
    case bookmarkCircle = "bookmark.circle"
    case bookmarkCircleFill = "bookmark.circle.fill"
    case starRectangle = "star.rectangle"
    case starRectangleFill = "star.rectangle.fill"
    case listBulletRectangle = "list.bullet.rectangle"
    case listBulletRectangleFill = "list.bullet.rectangle.fill"
    case checkmarkSeal = "checkmark.seal"
    case checkmarkSealFill = "checkmark.seal.fill"
    case checkmarkRectangle = "checkmark.rectangle"
    case checkmarkRectangleFill = "checkmark.rectangle.fill"

    var id: String { rawValue }
    static func resolve(_ value: String?) -> MenuBarIcon {
        MenuBarIcon(rawValue: value ?? "") ?? .bookmarkFill
    }
}

enum MenuBarProjectScope: String, CaseIterable, Identifiable {
    case allProjects
    case favoriteProjects

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .allProjects: "所有项目"
        case .favoriteProjects: "星标项目"
        }
    }

    static func resolve(_ value: String?) -> MenuBarProjectScope {
        MenuBarProjectScope(rawValue: value ?? "") ?? .allProjects
    }
}

enum MenuBarContentMode: String, CaseIterable, Identifiable {
    case currentTask
    case reminderTask

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .currentTask: "当前任务"
        case .reminderTask: "提醒任务"
        }
    }

    static func resolve(_ value: String?) -> MenuBarContentMode {
        MenuBarContentMode(rawValue: value ?? "") ?? .currentTask
    }
}
```

Add stored properties with declaration defaults for existing persisted records,
plus initializer defaults to `AppSettings`:

```swift
var menuBarIcon: String = MenuBarIcon.bookmarkFill.rawValue
var menuBarProjectScope: String = MenuBarProjectScope.allProjects.rawValue
var menuBarContentMode: String = MenuBarContentMode.currentTask.rawValue

// initializer parameters
menuBarIcon: String = MenuBarIcon.bookmarkFill.rawValue,
menuBarProjectScope: String = MenuBarProjectScope.allProjects.rawValue,
menuBarContentMode: String = MenuBarContentMode.currentTask.rawValue,
```

Assign all three initializer values alongside `menuBarComponentEnabled`.

- [ ] **Step 4: Rebuild the General settings group with live bindings**

Give `SettingsView` and `SettingsDetailView` an insertion callback:

```swift
struct SettingsView: View {
    var onMenuBarEnabledChange: (Bool) -> Void = { _ in }
    // pass callback into SettingsDetailView
}

private struct SettingsDetailView: View {
    let category: SettingsCategory
    @Bindable var settings: AppSettings
    let onMenuBarEnabledChange: (Bool) -> Void
}
```

Replace `generalPanel` with two groups:

```swift
private var generalPanel: some View {
    VStack(alignment: .leading, spacing: 22) {
        SettingsGroup("启动") {
            SettingsRow("开机启动") {
                settingsSwitch(launchAtLoginBinding)
            }
        }

        SettingsGroup("菜单栏组件") {
            SettingsRow("启用") {
                settingsSwitch(menuBarEnabledBinding)
            }
            SettingsDivider()
            SettingsRow("菜单栏图标") {
                Picker("菜单栏图标", selection: menuBarIconBinding) {
                    ForEach(MenuBarIcon.allCases) { icon in
                        Label(icon.rawValue, systemImage: icon.rawValue).tag(icon)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 188, alignment: .trailing)
            }
            SettingsDivider()
            SettingsRow("项目") {
                Picker("项目", selection: menuBarProjectScopeBinding) {
                    ForEach(MenuBarProjectScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150, alignment: .trailing)
            }
            SettingsDivider()
            SettingsRow("功能") {
                Picker("功能", selection: menuBarContentModeBinding) {
                    ForEach(MenuBarContentMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150, alignment: .trailing)
            }
        }
    }
}
```

Add bindings:

```swift
private var menuBarEnabledBinding: Binding<Bool> {
    Binding(
        get: { settings.menuBarComponentEnabled },
        set: {
            settings.menuBarComponentEnabled = $0
            onMenuBarEnabledChange($0)
        }
    )
}

private var menuBarIconBinding: Binding<MenuBarIcon> {
    Binding(get: { .resolve(settings.menuBarIcon) }, set: { settings.menuBarIcon = $0.rawValue })
}

private var menuBarProjectScopeBinding: Binding<MenuBarProjectScope> {
    Binding(get: { .resolve(settings.menuBarProjectScope) }, set: { settings.menuBarProjectScope = $0.rawValue })
}

private var menuBarContentModeBinding: Binding<MenuBarContentMode> {
    Binding(get: { .resolve(settings.menuBarContentMode) }, set: { settings.menuBarContentMode = $0.rawValue })
}
```

- [ ] **Step 5: Add localized settings copy**

Append these entries to both language files, translating the values in `en.lproj` and preserving Chinese values in `zh-Hans.lproj`:

```text
"菜单栏组件" = "Menu Bar Component";
"菜单栏图标" = "Menu Bar Icon";
"功能" = "Content";
"当前任务" = "Current Tasks";
"提醒任务" = "Reminder Tasks";
```

- [ ] **Step 6: Commit settings storage and UI wiring**

```bash
git add -- Viabar/Models/AppSettings.swift Viabar/Views/Settings/SettingsView.swift Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings ViabarTests/ViabarTests.swift
git commit -m "feat: add menu bar component settings"
```

### Task 2: Build Pure Menu Bar Card Projection And Shared Reminder Presentation

**Files:**
- Create: `Viabar/Models/MenuBarContent.swift`
- Create: `Viabar/Models/ReminderDisplay.swift`
- Modify: `Viabar/Views/MainPanel/MilestoneListView.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add projection tests for current and reminder modes**

Add the following `MenuBarContentTests` expectations:

```swift
struct MenuBarContentTests {
    @Test func currentModeReturnsFirstUnfinishedSubtaskOnly() {
        let project = Project(title: "Release", orderIndex: 0)
        let milestone = Milestone(title: "Prepare", orderIndex: 0)
        let finished = SubTask(title: "Done", orderIndex: 0, isCompleted: true)
        let target = SubTask(title: "Review", orderIndex: 1)
        finished.milestone = milestone
        target.milestone = milestone
        milestone.project = project
        milestone.subtasks = [finished, target]
        project.milestones = [milestone]

        let cards = MenuBarContentBuilder.cards(
            from: [project],
            scope: .allProjects,
            mode: .currentTask,
            now: Date()
        )

        #expect(cards.count == 1)
        #expect(cards[0].entries.map(\.title) == ["Review"])
        #expect(cards[0].entries[0].parentTitle == "Prepare")
        #expect(cards[0].entries[0].destination == .subTask(milestoneID: milestone.milestoneId, subTaskID: target.taskId))
    }

    @Test func reminderModeFiltersByEndOfTodayAndOrdersAllMatchingRows() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 12))!
        let project = Project(title: "Release")
        let first = Milestone(title: "Overdue", orderIndex: 0)
        let second = Milestone(title: "Later Today", orderIndex: 1)
        let tomorrow = Milestone(title: "Tomorrow", orderIndex: 2)
        first.project = project
        second.project = project
        tomorrow.project = project
        first.reminder = Reminder(type: "single", fireTimestamp: now.addingTimeInterval(-3600))
        second.reminder = Reminder(type: "single", fireTimestamp: now.addingTimeInterval(3600))
        tomorrow.reminder = Reminder(type: "single", fireTimestamp: now.addingTimeInterval(86400))
        project.milestones = [first, second, tomorrow]

        let cards = MenuBarContentBuilder.cards(
            from: [project],
            scope: .allProjects,
            mode: .reminderTask,
            now: now,
            calendar: calendar
        )

        #expect(cards[0].entries.map(\.title) == ["Overdue", "Later Today"])
        #expect(cards[0].entries.map(\.fireDate) == [first.reminder!.displayFireDate, second.reminder!.displayFireDate])
    }

    @Test func mapsProjectReminderAndFiltersArchivedOrUnstarredProjects() {
        let now = Date()
        let favorite = Project(title: "Favorite", orderIndex: 0)
        favorite.isFavorite = true
        let milestone = Milestone(title: "Mapped Task", orderIndex: 0)
        milestone.project = favorite
        favorite.milestones = [milestone]
        favorite.reminder = Reminder(type: "single", fireTimestamp: now)
        let unstarred = Project(title: "Other", orderIndex: 1)
        let archived = Project(title: "Archived", orderIndex: 2)
        archived.isFavorite = true
        archived.isArchived = true

        let cards = MenuBarContentBuilder.cards(
            from: [favorite, unstarred, archived],
            scope: .favoriteProjects,
            mode: .reminderTask,
            now: now
        )

        #expect(cards.map(\.project.title) == ["Favorite"])
        #expect(cards[0].entries[0].source == .projectReminder)
        #expect(cards[0].entries[0].destination == .milestone(milestone.milestoneId))
    }
}
```

- [ ] **Step 2: Leave red execution paused**

Do not run the Swift Testing target without compilation permission. Confirm only that the new test names reference types that will be added in this task.

- [ ] **Step 3: Move reusable reminder presentation into a model helper file**

Create `ReminderDisplay.swift` so both milestone rows and the menu bar builder can use one definition:

```swift
import Foundation

extension Reminder {
    var isRepeating: Bool { type == "repeating" }

    var displayFireDate: Date? {
        fireTimestamp ?? nextRepeatingFireDate(relativeTo: Date(), calendar: .current)
    }

    func displaySummary(dateFormatPattern: String?, language: EffectiveAppLanguage) -> String {
        let time = displayFireDate.map { AppDateFormatter.string(from: $0, pattern: dateFormatPattern) } ?? "--"
        guard isRepeating else { return time }
        return "\(time) \(repeatTitle(language: language))"
    }

    func repeatTitle(language: EffectiveAppLanguage) -> String {
        let key: String
        switch repeatIntervalDays {
        case 0: key = "每小时"
        case 1: key = "每天"
        case 2: key = "每2天"
        case 3: key = "每3天"
        case -1: key = "工作日"
        case 7: key = "每周"
        case 14: key = "每两周"
        case 30: key = "每月"
        case 90: key = "每3个月"
        case 180: key = "每6个月"
        case 365: key = "每年"
        default: key = "循环"
        }
        return AppLocalization.string(key, language: language)
    }

    func isOverdue(at now: Date) -> Bool { displayFireDate.map { $0 < now } ?? false }

    func isTodayPending(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let date = displayFireDate else { return false }
        return calendar.isDate(date, inSameDayAs: now) && date >= now
    }

    private func nextRepeatingFireDate(relativeTo now: Date, calendar: Calendar) -> Date? {
        guard isRepeating, let fireTime else { return fireTimestamp }
        let pieces = fireTime.split(separator: ":").compactMap { Int($0) }
        guard pieces.count >= 2 else { return fireTimestamp }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = pieces[0]
        components.minute = pieces[1]
        components.second = 0
        guard let today = calendar.date(from: components) else { return fireTimestamp }
        return today >= now ? today : nextCycle(after: today, calendar: calendar)
    }

    fileprivate func nextCycle(after date: Date, calendar: Calendar) -> Date? {
        switch repeatIntervalDays {
        case 0:
            return calendar.date(byAdding: .hour, value: 1, to: date)
        case -1:
            var candidate = calendar.date(byAdding: .day, value: 1, to: date)
            while let value = candidate {
                let weekday = calendar.component(.weekday, from: value)
                if weekday != 1 && weekday != 7 { return value }
                candidate = calendar.date(byAdding: .day, value: 1, to: value)
            }
            return nil
        case 30:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case 90:
            return calendar.date(byAdding: .month, value: 3, to: date)
        case 180:
            return calendar.date(byAdding: .month, value: 6, to: date)
        case 365:
            return calendar.date(byAdding: .year, value: 1, to: date)
        default:
            return calendar.date(byAdding: .day, value: repeatIntervalDays ?? 1, to: date)
        }
    }
}
```

Move the existing equivalent helper usage in `MilestoneListView` from
`inlineReminderSummary`, `isInlineReminderOverdue`, and
`isInlineReminderTodayPending` to `displaySummary`, `isOverdue(at:)`, and
`isTodayPending(at:)`, then remove the duplicated private display helpers.

- [ ] **Step 4: Implement stable card and entry snapshots**

Create `MenuBarContent.swift`:

```swift
import Foundation

enum MenuBarReminderSource: Equatable {
    case milestoneReminder
    case subTaskReminder
    case projectReminder
}

struct MenuBarTaskEntry: Identifiable {
    let id: String
    let title: String
    let parentTitle: String?
    let destination: GlobalSearchDestination
    let source: MenuBarReminderSource?
    let reminder: Reminder?
    let fireDate: Date?
}

struct MenuBarProjectCard: Identifiable {
    var id: UUID { project.projectId }
    let project: Project
    let entries: [MenuBarTaskEntry]
}

enum MenuBarContentBuilder {
    static func cards(
        from projects: [Project],
        scope: MenuBarProjectScope,
        mode: MenuBarContentMode,
        now: Date,
        calendar: Calendar = .current
    ) -> [MenuBarProjectCard] {
        visibleProjects(from: projects, scope: scope).compactMap { project in
            let entries = mode == .currentTask
                ? currentEntries(for: project)
                : reminderEntries(for: project, now: now, calendar: calendar)
            return entries.isEmpty ? nil : MenuBarProjectCard(project: project, entries: entries)
        }
    }
}
```

Implement private helpers with these exact rules:

```swift
private static func visibleProjects(from projects: [Project], scope: MenuBarProjectScope) -> [Project] {
    projects
        .filter { !$0.isArchived && (scope == .allProjects || $0.isFavorite) }
        .sorted {
            $0.orderIndex == $1.orderIndex
                ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                : $0.orderIndex < $1.orderIndex
        }
}

private static func currentEntries(for project: Project) -> [MenuBarTaskEntry] {
    guard let milestone = project.milestones.sorted(by: { $0.orderIndex < $1.orderIndex }).first(where: { !$0.isCompleted }) else {
        return []
    }
    if let subTask = milestone.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }).first(where: { !$0.isCompleted }) {
        return [entry(for: subTask, milestone: milestone, source: nil, reminder: nil)]
    }
    return [entry(for: milestone, source: nil, reminder: nil)]
}

private static func reminderEntries(for project: Project, now: Date, calendar: Calendar) -> [MenuBarTaskEntry] {
    let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
    var entries: [MenuBarTaskEntry] = []
    for milestone in project.milestones.sorted(by: { $0.orderIndex < $1.orderIndex }) where !milestone.isCompleted {
        if let reminder = milestone.reminder, let date = reminder.displayFireDate, date <= endOfToday {
            entries.append(entry(for: milestone, source: .milestoneReminder, reminder: reminder))
        }
        for subTask in milestone.subtasks.sorted(by: { $0.orderIndex < $1.orderIndex }) where !subTask.isCompleted {
            if let reminder = subTask.reminder, let date = reminder.displayFireDate, date <= endOfToday {
                entries.append(entry(for: subTask, milestone: milestone, source: .subTaskReminder, reminder: reminder))
            }
        }
    }
    if let reminder = project.reminder,
       let date = reminder.displayFireDate,
       date <= endOfToday,
       var mapped = currentEntries(for: project).first {
        mapped = MenuBarTaskEntry(
            id: "project-reminder-\(project.projectId.uuidString)",
            title: mapped.title,
            parentTitle: mapped.parentTitle,
            destination: mapped.destination,
            source: .projectReminder,
            reminder: reminder,
            fireDate: date
        )
        entries.append(mapped)
    }
    return entries.sorted {
        if $0.fireDate == $1.fireDate { return $0.id < $1.id }
        return ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture)
    }
}

private static func entry(for milestone: Milestone, source: MenuBarReminderSource?, reminder: Reminder?) -> MenuBarTaskEntry {
    MenuBarTaskEntry(
        id: "\(source.map { String(describing: $0) } ?? "current")-milestone-\(milestone.milestoneId.uuidString)",
        title: milestone.title,
        parentTitle: nil,
        destination: .milestone(milestone.milestoneId),
        source: source,
        reminder: reminder,
        fireDate: reminder?.displayFireDate
    )
}

private static func entry(for subTask: SubTask, milestone: Milestone, source: MenuBarReminderSource?, reminder: Reminder?) -> MenuBarTaskEntry {
    MenuBarTaskEntry(
        id: "\(source.map { String(describing: $0) } ?? "current")-subtask-\(subTask.taskId.uuidString)",
        title: subTask.title,
        parentTitle: milestone.title,
        destination: .subTask(milestoneID: milestone.milestoneId, subTaskID: subTask.taskId),
        source: source,
        reminder: reminder,
        fireDate: reminder?.displayFireDate
    )
}
```

Keep the date comparison in this builder so the panel does not independently
reimplement reminder visibility or row order.

- [ ] **Step 5: Commit the pure display/projection layer**

```bash
git add -- Viabar/Models/MenuBarContent.swift Viabar/Models/ReminderDisplay.swift Viabar/Views/MainPanel/MilestoneListView.swift ViabarTests/ViabarTests.swift
git commit -m "feat: derive menu bar task cards"
```

### Task 3: Centralize Reminder Mutations And Complete Notification Lifecycle

**Files:**
- Modify: `Viabar/Services/ProjectService.swift`
- Modify: `Viabar/Services/NotificationScheduleService.swift`
- Modify: `Viabar/Views/MainPanel/MilestoneListView.swift`
- Modify: `Viabar/Models/ReminderDisplay.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Specify service-owned reminder updates and repeat advancement**

Add tests using an in-memory model container and a no-op notification delivery closure:

```swift
@MainActor
struct NotificationScheduleLifecycleTests {
    @Test func projectServiceSetsMilestoneReminderAndCreatesScheduleEntry() throws {
        let (projectService, scheduleService, context) = try makeServices()
        let project = projectService.createProject(title: "Release")
        let milestone = projectService.addMilestone(to: project, title: "Review")
        let fireDate = Date().addingTimeInterval(3600)

        projectService.updateReminder(
            Reminder(type: "single", fireTimestamp: fireDate),
            for: milestone
        )

        let entries = try context.fetch(FetchDescriptor<NotificationScheduleEntry>())
        #expect(milestone.reminder?.fireTimestamp == fireDate)
        #expect(entries.map(\.ownerId) == [milestone.milestoneId])
        _ = scheduleService
    }

    @Test func singleDueMilestoneReminderStaysOnTaskAfterDelivery() throws {
        let (projectService, scheduleService, context) = try makeServices()
        let project = projectService.createProject(title: "Release")
        let milestone = projectService.addMilestone(to: project, title: "Review")
        let firedAt = Date().addingTimeInterval(-60)
        projectService.updateReminder(Reminder(type: "single", fireTimestamp: firedAt), for: milestone)

        scheduleService.processDueEntries(now: Date())

        #expect(milestone.reminder?.fireTimestamp == firedAt)
        #expect(try context.fetch(FetchDescriptor<NotificationScheduleEntry>()).isEmpty)
    }

    @Test func repeatingDueSubtaskReminderAdvancesBeyondNow() throws {
        let (projectService, scheduleService, context) = try makeServices()
        let project = projectService.createProject(title: "Release")
        let milestone = projectService.addMilestone(to: project, title: "Prepare")
        let subTask = projectService.addSubTask(to: milestone, title: "Review")
        let now = Date()
        projectService.updateReminder(
            Reminder(type: "repeating", fireTimestamp: now.addingTimeInterval(-172800), repeatIntervalDays: 1),
            for: subTask
        )

        scheduleService.processDueEntries(now: now)

        #expect(subTask.reminder!.fireTimestamp! > now)
        let entries = try context.fetch(FetchDescriptor<NotificationScheduleEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].ownerId == subTask.taskId)
        #expect(entries[0].fireDate == subTask.reminder!.fireTimestamp)
    }
}
```

Define `makeServices()` in that test structure with an in-memory container and
registered services:

```swift
private func makeServices() throws -> (ProjectService, NotificationScheduleService, ModelContext) {
    let schema = Schema([
        Project.self, Milestone.self, SubTask.self, Memo.self, Reminder.self,
        NotificationScheduleEntry.self, ArchiveFolder.self, ProjectTemplate.self,
        TemplateMilestone.self, TemplateSubTask.self, AppSettings.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
    let context = modelContainer.mainContext
    let container = ServiceContainer()
    let projectService = ProjectService(modelContext: context, container: container)
    let scheduleService = NotificationScheduleService(modelContext: context) { _, _ in }
    container.register(projectService)
    container.register(scheduleService)
    return (projectService, scheduleService, context)
}
```

- [ ] **Step 2: Leave service tests unexecuted until compilation is approved**

Do not run `xcodebuild test`. During implementation, use source review to
confirm the tests exercise single reminders and repeating subtasks through the
new public seams.

- [ ] **Step 3: Give ProjectService ownership of reminder writes**

Add to `ProjectServiceProtocol` and `ProjectService`:

```swift
func updateReminder(_ reminder: Reminder?, for milestone: Milestone)
func updateReminder(_ reminder: Reminder?, for subTask: SubTask)
```

Implement them as:

```swift
func updateReminder(_ reminder: Reminder?, for milestone: Milestone) {
    milestone.reminder = reminder
    save()
    guard let project = milestone.project else { return }
    if reminder == nil {
        notificationScheduleService?.removeEntry(ownerId: milestone.milestoneId)
    } else {
        notificationScheduleService?.syncMilestone(milestone, project: project)
    }
}

func updateReminder(_ reminder: Reminder?, for subTask: SubTask) {
    subTask.reminder = reminder
    save()
    guard let project = subTask.milestone?.project else { return }
    if reminder == nil {
        notificationScheduleService?.removeEntry(ownerId: subTask.taskId)
    } else {
        notificationScheduleService?.syncSubTask(subTask, project: project)
    }
}
```

Update `MilestoneListView` reminder bindings to call these two methods instead
of setting `reminder`, saving, and invoking private synchronization functions.
Leave completion/reordering sync behavior intact.

- [ ] **Step 4: Make notification delivery and due processing testable**

In `NotificationScheduleService`, introduce a defaulted posting closure and
an explicit-time due method:

```swift
private let notificationPoster: (String, String) -> Void

init(
    modelContext: ModelContext,
    notificationPoster: ((String, String) -> Void)? = nil
) {
    self.modelContext = modelContext
    self.notificationPoster = notificationPoster ?? Self.deliverNotification
    super.init()
}

func processDueEntries(now: Date = Date()) {
    // existing fetch loop uses supplied now
}

private static func deliverNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}
```

Replace internal post calls with `notificationPoster(title, body)`.

- [ ] **Step 5: Advance task and subtask repeating reminders**

Replace the non-project due-entry deletion branch with:

```swift
private func handleDueTaskEntry(_ entry: NotificationScheduleEntry, now: Date) {
    defer { modelContext.delete(entry) }
    guard let resolved = taskOwner(for: entry), !resolved.project.isArchived, !resolved.isCompleted else { return }

    notificationPoster(resolved.project.title, resolved.title)
    guard let reminder = resolved.reminder, reminder.type == "repeating",
          let nextDate = reminder.nextFutureFireDate(after: entry.fireDate, now: now)
    else { return }

    reminder.fireTimestamp = nextDate
    modelContext.insert(NotificationScheduleEntry(
        ownerId: entry.ownerId,
        ownerKind: entry.ownerKind,
        projectId: resolved.project.projectId,
        projectTitle: resolved.project.title,
        body: resolved.title,
        fireDate: nextDate
    ))
}
```

Resolve `ownerKind == "milestone"` and `ownerKind == "subtask"` through the
destination project's current task tree:

```swift
private struct TaskReminderOwner {
    let project: Project
    let title: String
    let reminder: Reminder?
    let isCompleted: Bool
}

private func taskOwner(for entry: NotificationScheduleEntry) -> TaskReminderOwner? {
    guard let project = project(id: entry.projectId) else { return nil }
    if entry.ownerKind == "milestone",
       let milestone = project.milestones.first(where: { $0.milestoneId == entry.ownerId }) {
        return TaskReminderOwner(
            project: project,
            title: milestone.title,
            reminder: milestone.reminder,
            isCompleted: milestone.isCompleted
        )
    }
    if entry.ownerKind == "subtask" {
        for milestone in project.milestones {
            if let subTask = milestone.subtasks.first(where: { $0.taskId == entry.ownerId }) {
                return TaskReminderOwner(
                    project: project,
                    title: subTask.title,
                    reminder: subTask.reminder,
                    isCompleted: subTask.isCompleted
                )
            }
        }
    }
    return nil
}
```

Single reminders intentionally leave `Reminder.fireTimestamp` untouched while
their consumed `NotificationScheduleEntry` is deleted.

Move generalized next-future-date calculation to `ReminderDisplay.swift`:

```swift
extension Reminder {
    func nextFutureFireDate(after firedDate: Date, now: Date, calendar: Calendar = .current) -> Date? {
        var candidate = firedDate
        for _ in 0..<10000 {
            guard let next = nextCycle(after: candidate, calendar: calendar) else { return nil }
            if next > now { return next }
            candidate = next
        }
        return nil
    }

}
```

Use this helper for project, milestone, and subtask repeat advancement so all
three owner kinds skip missed historical cycles identically.

- [ ] **Step 6: Commit service-owned reminder lifecycle**

```bash
git add -- Viabar/Services/ProjectService.swift Viabar/Services/NotificationScheduleService.swift Viabar/Views/MainPanel/MilestoneListView.swift Viabar/Models/ReminderDisplay.swift ViabarTests/ViabarTests.swift
git commit -m "feat: preserve due task reminder lifecycle"
```

### Task 4: Bridge Menu Bar Clicks Into Existing Detail Navigation

**Files:**
- Modify: `Viabar/System/AppRuntimeController.swift`
- Modify: `Viabar/ContentView.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add a focused navigation handoff expectation**

Add a pure consumption test for the runtime request store; isolate UI activation
from the request API by constructing without invoking `navigate`:

```swift
@MainActor
struct AppRuntimeNavigationTests {
    @Test func consumesQueuedMenuBarNavigationOnce() {
        let controller = AppRuntimeController()
        let request = GlobalSearchNavigationRequest(
            projectID: UUID(),
            destination: .project
        )

        controller.queueNavigationRequestForTesting(request)

        #expect(controller.consumePendingNavigationRequest() == request)
        #expect(controller.consumePendingNavigationRequest() == nil)
    }
}
```

- [ ] **Step 2: Leave runtime test execution paused**

Do not compile or run this test without authorization. Its purpose is to force
one-shot request semantics before wiring `ContentView`.

- [ ] **Step 3: Add one-shot navigation publication to the runtime controller**

Add runtime state and entry points:

```swift
private(set) var navigationPresentationID = UUID()
private var pendingNavigationRequest: GlobalSearchNavigationRequest?

func navigate(to request: GlobalSearchNavigationRequest) {
    pendingNavigationRequest = request
    showMainPanel()
    navigationPresentationID = UUID()
}

func consumePendingNavigationRequest() -> GlobalSearchNavigationRequest? {
    defer { pendingNavigationRequest = nil }
    return pendingNavigationRequest
}

func queueNavigationRequestForTesting(_ request: GlobalSearchNavigationRequest) {
    pendingNavigationRequest = request
}
```

Keep `showMainPanel()` as the single AppKit activation/window-opening path.

- [ ] **Step 4: Route external requests through the existing selection/highlight path**

In `ContentView`, add:

```swift
.onAppear {
    runtimeController.registerMainWindowOpener { openWindow(id: "main") }
    presentPendingGlobalSearchIfNeeded()
    consumePendingNavigationIfNeeded()
}
.onChange(of: runtimeController.navigationPresentationID) { _, _ in
    consumePendingNavigationIfNeeded()
}
```

Implement:

```swift
private func consumePendingNavigationIfNeeded() {
    guard let request = runtimeController.consumePendingNavigationRequest(),
          let project = allProjects.first(where: { $0.projectId == request.projectID })
    else { return }
    navigationRequest = request
    selection = .project(project)
}
```

Do not create alternate milestone or subtask highlight UI: existing
`navigationRequest` propagation to `MilestoneListView` must continue to own the
orange target feedback.

- [ ] **Step 5: Commit menu-bar-to-main-window navigation**

```bash
git add -- Viabar/System/AppRuntimeController.swift Viabar/ContentView.swift ViabarTests/ViabarTests.swift
git commit -m "feat: route menu bar navigation to project details"
```

### Task 5: Build The Menu Bar Panel And Mutations

**Files:**
- Create: `Viabar/Views/MenuBar/MenuBarPanelView.swift`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Create the panel data/query shell**

Create a view that reads shared models and services:

```swift
struct MenuBarPanelView: View {
    @Query(sort: \Project.orderIndex) private var projects: [Project]
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @Environment(ServiceContainer.self) private var container
    @Environment(AppRuntimeController.self) private var runtimeController

    @State private var draft = ""
    @State private var selectedProjectID: UUID?
    @State private var draftReminder: Reminder?

    private var settings: AppSettings? { settingsRecords.first }
    private var scope: MenuBarProjectScope { .resolve(settings?.menuBarProjectScope) }
    private var mode: MenuBarContentMode { .resolve(settings?.menuBarContentMode) }
    private var cards: [MenuBarProjectCard] {
        MenuBarContentBuilder.cards(from: projects, scope: scope, mode: mode, now: Date())
    }
    private var activeProjects: [Project] {
        projects.filter { !$0.isArchived }.sorted { $0.orderIndex < $1.orderIndex }
    }
    private var projectService: ProjectService? { container.projectService }
    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settings?.language)
    }
    private var preferredColorScheme: ColorScheme? {
        switch AppTheme(rawValue: settings?.theme ?? "") ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
```

Wrap a fixed-width panel body in a `ScrollView` for cards, retaining a
non-scrolling bottom quick-add/footer area:

```swift
var body: some View {
    VStack(spacing: 12) {
        ScrollView {
            LazyVStack(spacing: 10) {
                if cards.isEmpty { emptyState }
                ForEach(cards) { card in projectCard(card) }
            }
        }
        quickAddArea
        footer
    }
    .padding(14)
    .frame(width: 370, height: 580)
    .environment(\.locale, effectiveLanguage.locale)
    .preferredColorScheme(preferredColorScheme)
}

private var emptyState: some View {
    Text(mode == .currentTask ? "暂无当前任务" : "暂无今天需要处理的提醒")
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
}
```

- [ ] **Step 2: Render cards and actionable rows**

Implement card/row bodies and row actions with the projected destination:

```swift
@ViewBuilder
private func projectCard(_ card: MenuBarProjectCard) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Button { openProject(card.project) } label: {
            HStack {
                Image(systemName: card.project.sfSymbolName)
                    .foregroundStyle(Color(hex: card.project.accentColor))
                Text(card.project.title).font(.headline)
            }
        }
        .buttonStyle(.plain)
        ForEach(card.entries) { entry in taskRow(entry, in: card.project) }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
}

@ViewBuilder
private func taskRow(_ entry: MenuBarTaskEntry, in project: Project) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Button { complete(entry, in: project) } label: {
            Image(systemName: "circle")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)

        Button { openEntry(entry, in: project) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).foregroundStyle(.primary)
                if let parentTitle = entry.parentTitle {
                    Text(parentTitle).font(.caption).foregroundStyle(.secondary)
                }
                reminderSummary(for: entry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

@ViewBuilder
private func reminderSummary(for entry: MenuBarTaskEntry) -> some View {
    if let reminder = entry.reminder {
        HStack(spacing: 6) {
            if entry.source == .projectReminder { Text("项目提醒") }
            Text(reminder.displaySummary(dateFormatPattern: settings?.dateFormat, language: effectiveLanguage))
        }
        .font(.system(size: 11))
        .foregroundStyle(reminder.isOverdue(at: Date()) ? .red : .orange)
    }
}

private func openProject(_ project: Project) {
    runtimeController.navigate(to: GlobalSearchNavigationRequest(
        projectID: project.projectId,
        destination: .project
    ))
}

private func openEntry(_ entry: MenuBarTaskEntry, in project: Project) {
    runtimeController.navigate(to: GlobalSearchNavigationRequest(
        projectID: project.projectId,
        destination: entry.destination
    ))
}

private func complete(_ entry: MenuBarTaskEntry, in project: Project) {
    switch entry.destination {
    case .milestone(let id):
        guard let milestone = project.milestones.first(where: { $0.milestoneId == id }) else { return }
        projectService?.toggleMilestoneComplete(milestone)
    case .subTask(let milestoneID, let subTaskID):
        guard let milestone = project.milestones.first(where: { $0.milestoneId == milestoneID }),
              let subTask = milestone.subtasks.first(where: { $0.taskId == subTaskID })
        else { return }
        projectService?.toggleSubTaskComplete(subTask)
    case .project, .memo:
        break
    }
}
```

- [ ] **Step 3: Add quick creation of a task with optional reminder**

Only expand controls when the trimmed draft is nonempty:

```swift
private func submitDraft() {
    let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty,
          let project = activeProjects.first(where: { $0.projectId == selectedProjectID }),
          let service = projectService
    else { return }

    let milestone = service.addMilestone(to: project, title: title)
    if let draftReminder {
        service.updateReminder(
            Reminder(
                type: draftReminder.type,
                fireTime: draftReminder.fireTime,
                fireTimestamp: draftReminder.fireTimestamp,
                repeatIntervalDays: draftReminder.repeatIntervalDays
            ),
            for: milestone
        )
    }

    draft = ""
    selectedProjectID = nil
    self.draftReminder = nil
}
```

Use a `TextField("添加任务", text: $draft)` with `.onSubmit(submitDraft)`;
once nonempty, render a project `Picker` over all active projects and a
reminder button/popover backed by `ReminderSettingsPopover(reminder:
$draftReminder)`. Disable submit until the text and project selection are
present.

```swift
private var hasDraft: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private var canSubmitDraft: Bool {
    hasDraft && selectedProjectID != nil
}

private var quickAddArea: some View {
    VStack(alignment: .leading, spacing: 8) {
        TextField("添加任务", text: $draft)
            .textFieldStyle(.plain)
            .onSubmit(submitDraft)
        if hasDraft {
            HStack {
                Picker("选择项目", selection: $selectedProjectID) {
                    Text("选择项目").tag(UUID?.none)
                    ForEach(activeProjects) { project in
                        Text(project.title).tag(Optional(project.projectId))
                    }
                }
                .labelsHidden()
                .disabled(activeProjects.isEmpty)
                ReminderSettingsPopoverTrigger(reminder: $draftReminder)
                Button("添加任务", action: submitDraft).disabled(!canSubmitDraft)
            }
        }
    }
    .padding(10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}
```

Create `ReminderSettingsPopoverTrigger` in the same file:

```swift
private struct ReminderSettingsPopoverTrigger: View {
    @Binding var reminder: Reminder?
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("添加提醒", systemImage: "calendar")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popover(isPresented: $isPresented) {
            ReminderSettingsPopover(reminder: $reminder)
        }
    }
}
```

- [ ] **Step 4: Add the synchronized gear menu**

At bottom right render:

```swift
private var settingsMenu: some View {
    Menu {
        Picker("项目", selection: projectScopeBinding) {
            ForEach(MenuBarProjectScope.allCases) { scope in Text(scope.title).tag(scope) }
        }
        Picker("功能", selection: contentModeBinding) {
            ForEach(MenuBarContentMode.allCases) { mode in Text(mode.title).tag(mode) }
        }
    } label: {
        Image(systemName: "gearshape.fill")
    }
}
```

Use bindings directly against `settings.menuBarProjectScope` and
`settings.menuBarContentMode`, so Settings and the open menu-bar panel observe
the same SwiftData record:

```swift
private var projectScopeBinding: Binding<MenuBarProjectScope> {
    Binding(
        get: { .resolve(settings?.menuBarProjectScope) },
        set: { settings?.menuBarProjectScope = $0.rawValue }
    )
}

private var contentModeBinding: Binding<MenuBarContentMode> {
    Binding(
        get: { .resolve(settings?.menuBarContentMode) },
        set: { settings?.menuBarContentMode = $0.rawValue }
    )
}

private var footer: some View {
    HStack {
        Spacer()
        settingsMenu
    }
}
```

- [ ] **Step 5: Add panel localization copy**

Add both-language entries for:

```text
"暂无当前任务" = "No Current Tasks";
"暂无今天需要处理的提醒" = "No Reminders Due Today";
"项目提醒" = "Project Reminder";
"选择项目" = "Choose Project";
"添加提醒" = "Add Reminder";
"面板配置" = "Panel Settings";
```

- [ ] **Step 6: Commit the panel surface**

```bash
git add -- Viabar/Views/MenuBar/MenuBarPanelView.swift Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add menu bar task panel"
```

### Task 6: Register MenuBarExtra With Shared State And Theme

**Files:**
- Modify: `Viabar/ViabarApp.swift`
- Modify: `Viabar/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Initialize insertion state from the persisted settings row**

In `ViabarApp`, add:

```swift
@State private var isMenuBarInserted: Bool
```

During `init`, capture the ensured settings row and initialize it:

```swift
let settings = AppSettingsStore.ensureDefaultSettings(in: sharedModelContainer.mainContext)
_isMenuBarInserted = State(initialValue: settings.menuBarComponentEnabled)
```

Replace the existing ignored return value from `ensureDefaultSettings` with
this captured `settings`.

- [ ] **Step 2: Add MenuBarExtra and its dynamic label**

Add the scene after the main window:

```swift
MenuBarExtra(isInserted: $isMenuBarInserted) {
    MenuBarPanelView()
        .environment(serviceContainer)
        .environment(runtimeController)
        .modelContainer(sharedModelContainer)
} label: {
    MenuBarStatusLabelView()
        .modelContainer(sharedModelContainer)
}
.menuBarExtraStyle(.window)
```

Add a small label reader:

```swift
private struct MenuBarStatusLabelView: View {
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]

    var body: some View {
        Image(systemName: MenuBarIcon.resolve(settingsRecords.first?.menuBarIcon).rawValue)
    }
}
```

`MenuBarPanelView.preferredColorScheme` reads the same saved `AppTheme` choice
as `AppAppearanceController`, so the menu-bar window displays the selected
light, dark, or system appearance even before the main window is brought
forward.

- [ ] **Step 3: Synchronize the Settings enable toggle with scene insertion**

Pass the binding effect from the Settings scene:

```swift
SettingsView { enabled in
    isMenuBarInserted = enabled
}
```

The callback writes only runtime scene insertion; the setting binding added in
Task 1 remains responsible for storing
`settings.menuBarComponentEnabled = enabled`.

- [ ] **Step 4: Commit app scene registration**

```bash
git add -- Viabar/ViabarApp.swift Viabar/Views/Settings/SettingsView.swift
git commit -m "feat: register configurable menu bar scene"
```

### Task 7: Static Verification And Deferred Runtime Checklist

**Files:**
- Verify: `Viabar/Models/AppSettings.swift`
- Verify: `Viabar/Models/MenuBarContent.swift`
- Verify: `Viabar/Models/ReminderDisplay.swift`
- Verify: `Viabar/Services/ProjectService.swift`
- Verify: `Viabar/Services/NotificationScheduleService.swift`
- Verify: `Viabar/System/AppRuntimeController.swift`
- Verify: `Viabar/ContentView.swift`
- Verify: `Viabar/Views/Settings/SettingsView.swift`
- Verify: `Viabar/Views/MenuBar/MenuBarPanelView.swift`
- Verify: `Viabar/ViabarApp.swift`
- Verify: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Inspect the implemented requirement paths**

Use focused searches to ensure the feature routes through shared sources:

```bash
rg -n "menuBarIcon|menuBarProjectScope|menuBarContentMode|MenuBarExtra|MenuBarPanelView|MenuBarContentBuilder" Viabar ViabarTests
rg -n "updateReminder|processDueEntries|nextFutureFireDate|navigate\\(to:|consumePendingNavigationRequest" Viabar ViabarTests
```

Expected: menu bar storage, panel rendering, service reminder writes, lifecycle
advance, and navigation bridging each have a concrete source/test reference.

- [ ] **Step 2: Run the authorized static validation**

```bash
git diff --check
git status --short --branch
```

Expected: `git diff --check` exits `0`; status shows only the intended
implementation/test/document changes or a clean tree after task commits.

- [ ] **Step 3: Keep executable verification explicitly deferred**

Do not run the following unless the user authorizes compilation:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS'
```

When authorization is later given, the expected result is a passing test run
including `AppSettingsTests`, `MenuBarContentTests`,
`NotificationScheduleLifecycleTests`, and `AppRuntimeNavigationTests`.

- [ ] **Step 4: Record runtime checks requiring an authorized build/run**

After a user-authorized run, manually verify:

1. Settings enabling/disabling immediately inserts/removes the configured menu bar icon.
2. Settings and gear-menu project/mode choices remain synchronized.
3. Current-task cards display only one actionable target per visible project.
4. Reminder cards retain overdue single reminders and advance recurring reminders.
5. Checkbox completion and quick add refresh both the panel and main application data.
6. Project/task/subtask clicks open the main panel and reuse orange highlight feedback.
7. Light, dark, and system theme choices are reflected in the menu bar panel.
