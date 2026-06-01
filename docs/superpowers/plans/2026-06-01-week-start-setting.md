# Configurable Week Start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted Sunday/Monday week-start preference and make overview weekly summaries use it.

**Architecture:** `WeekStartDay` lives beside `AppSettings` as the single parser, locale-default policy, and calendar-adjustment boundary. `ContentView` passes the resolved setting into the pure `OverviewReportBuilder`; settings UI and backups read and write the same persisted field. The optional stored field allows existing SwiftData rows and old JSON backups to migrate without changing the backup format version.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing, macOS `.strings` localization

**Verification Constraint:** The user has not authorized compiling. Add test source first as executable behavior contracts, but do not run `xcodebuild`, `swift test`, or any build-backed test command unless the user explicitly authorizes it. Use static inspection, `plutil -lint`, and `git diff --check` during this execution.

---

## File Structure

- Modify: `Viabar/Models/AppSettings.swift`
  - Define `WeekStartDay`, persist the optional stored value, and freeze missing or invalid values during settings bootstrap.
- Modify: `ViabarTests/ViabarTests.swift`
  - Add contracts for locale defaults, bootstrap migration, week boundaries, and backup compatibility.
- Modify: `Viabar/Models/OverviewReport.swift`
  - Accept `WeekStartDay` and use its adjusted calendar for all weekly intervals.
- Modify: `Viabar/ContentView.swift`
  - Resolve the saved setting and pass it into the overview report builder.
- Modify: `Viabar/Views/Settings/SettingsView.swift`
  - Add the `每周开始于` picker to `显示 > 视图`.
- Modify: `Viabar/en.lproj/Localizable.strings`
  - Add English labels.
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`
  - Add Simplified Chinese labels.
- Modify: `Viabar/Models/BackupSnapshot.swift`
  - Include the optional preference in version-1 snapshots while preserving old JSON decoding.
- Modify: `Viabar/Services/BackupService.swift`
  - Restore a resolved explicit preference.

### Task 1: Add Week-Start Policy And Bootstrap Migration

**Files:**
- Modify: `ViabarTests/ViabarTests.swift:330`
- Modify: `Viabar/Models/AppSettings.swift:69`
- Modify: `Viabar/Models/AppSettings.swift:163`
- Modify: `Viabar/Models/AppSettings.swift:231`

- [ ] **Step 1: Write the week-start policy tests**

Add tests under `AppSettingsTests` before changing production code:

```swift
// Add to initializesDocumentedDefaults()
#expect(settings.weekStartDay == WeekStartDay.defaultValue().rawValue)

@Test func resolvesWeekStartDefaultsFromRegionAndPreservesSavedValues() {
    let unitedStates = Locale(identifier: "en_US")
    let singapore = Locale(identifier: "en_SG")

    #expect(WeekStartDay.defaultValue(locale: unitedStates) == .sunday)
    #expect(WeekStartDay.defaultValue(locale: singapore) == .monday)
    #expect(WeekStartDay.resolve("monday", locale: unitedStates) == .monday)
    #expect(WeekStartDay.resolve("invalid", locale: unitedStates) == .sunday)
    #expect(WeekStartDay.resolve(nil, locale: singapore) == .monday)
}
```

Add a `@MainActor` migration contract using an in-memory settings container:

```swift
@Test @MainActor func bootstrapFreezesMissingWeekStartUsingCurrentRegion() throws {
    let schema = Schema([AppSettings.self])
    let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let settings = AppSettings(weekStartDay: nil)
    container.mainContext.insert(settings)

    let resolved = AppSettingsStore.ensureDefaultSettings(
        in: container.mainContext,
        locale: Locale(identifier: "en_US")
    )

    #expect(resolved.weekStartDay == WeekStartDay.sunday.rawValue)
}
```

- [ ] **Step 2: Record the expected RED state without compiling**

Run:

```bash
rg -n "enum WeekStartDay|weekStartDay|locale:" Viabar/Models/AppSettings.swift
```

Expected: no `WeekStartDay` implementation exists yet. Do not invoke a compiler.

- [ ] **Step 3: Implement the policy and persisted field**

Add beside the existing settings enums:

```swift
enum WeekStartDay: String, CaseIterable, Identifiable {
    case sunday
    case monday

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .sunday: "周日"
        case .monday: "周一"
        }
    }

    static func defaultValue(locale: Locale = .current) -> WeekStartDay {
        locale.region?.identifier == "US" ? .sunday : .monday
    }

    static func resolve(_ storedValue: String?, locale: Locale = .current) -> WeekStartDay {
        WeekStartDay(rawValue: storedValue ?? "") ?? defaultValue(locale: locale)
    }

    func applying(to calendar: Calendar) -> Calendar {
        var calendar = calendar
        calendar.firstWeekday = self == .sunday ? 1 : 2
        return calendar
    }
}
```

Add the optional SwiftData field and initializer parameter:

```swift
var weekStartDay: String?
```

```swift
weekStartDay: String? = WeekStartDay.defaultValue().rawValue,
```

Assign it in `AppSettings.init`:

```swift
self.weekStartDay = weekStartDay
```

Allow deterministic bootstrap migration:

```swift
static func ensureDefaultSettings(
    in context: ModelContext,
    locale: Locale = .current
) -> AppSettings {
    var descriptor = FetchDescriptor<AppSettings>(
        sortBy: [SortDescriptor(\AppSettings.createdAt)]
    )
    descriptor.fetchLimit = 1

    if let settings = try? context.fetch(descriptor).first {
        if WeekStartDay(rawValue: settings.weekStartDay ?? "") == nil {
            settings.weekStartDay = WeekStartDay.defaultValue(locale: locale).rawValue
            try? context.save()
        }
        return settings
    }

    let settings = AppSettings(
        weekStartDay: WeekStartDay.defaultValue(locale: locale).rawValue
    )
    context.insert(settings)
    try? context.save()
    return settings
}
```

- [ ] **Step 4: Perform static checks**

Run:

```bash
rg -n "WeekStartDay|weekStartDay|ensureDefaultSettings" Viabar/Models/AppSettings.swift ViabarTests/ViabarTests.swift
git diff --check
```

Expected: enum, optional field, migration branch, and tests are present; whitespace check exits `0`.

- [ ] **Step 5: Commit**

```bash
git add -- Viabar/Models/AppSettings.swift ViabarTests/ViabarTests.swift
git commit -m "feat: persist configurable week start"
```

### Task 2: Apply The Setting To Overview Weekly Intervals

**Files:**
- Modify: `ViabarTests/ViabarTests.swift:566`
- Modify: `Viabar/Models/OverviewReport.swift:62`
- Modify: `Viabar/ContentView.swift:230`

- [ ] **Step 1: Write completion and todo boundary tests**

Under `OverviewReportTests`, add one completed task on Sunday and one reminder on Sunday:

```swift
@Test func weekStartChangesCompletionAndTodoBoundaries() {
    let project = Project(title: "Boundary")
    let completed = Milestone(title: "Sunday Done", isCompleted: true)
    completed.completedAt = calendar.date(
        from: DateComponents(year: 2026, month: 5, day: 31, hour: 12)
    )
    completed.project = project
    let planned = Milestone(title: "Sunday Todo")
    planned.reminder = Reminder(
        type: "single",
        fireTimestamp: calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 31, hour: 12)
        )
    )
    planned.project = project
    project.milestones = [completed, planned]

    let mondayNow = calendar.date(
        from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)
    )!
    let sundayReport = OverviewReportBuilder.makeReport(
        projects: [project],
        scheduleEntries: [],
        now: mondayNow,
        calendar: calendar,
        weekStartDay: .sunday
    )
    let mondayReport = OverviewReportBuilder.makeReport(
        projects: [project],
        scheduleEntries: [],
        now: mondayNow,
        calendar: calendar,
        weekStartDay: .monday
    )
    let sundayWeekDone = sundayReport.first { $0.kind == .weekDone }!
    let mondayWeekDone = mondayReport.first { $0.kind == .weekDone }!
    let sundayTodo = sundayReport.first { $0.kind == .weekTodo }!
    let mondayTodo = mondayReport.first { $0.kind == .weekTodo }!

    #expect(sundayWeekDone.cards[0].groups.map(\.title) == ["Sunday Done"])
    #expect(mondayWeekDone.cards.isEmpty)
    #expect(sundayTodo.cards[0].groups.map(\.title) == ["Sunday Todo"])
    #expect(mondayTodo.cards[0].groups.map(\.title) == ["Sunday Todo"])
}
```

Keep the assertion intent: the Sunday completion belongs to different weekly completion sections after switching the setting, while cumulative todo still remains included.

- [ ] **Step 2: Record the expected RED state without compiling**

Run:

```bash
rg -n "weekStartDay|applying\\(to:" Viabar/Models/OverviewReport.swift Viabar/ContentView.swift
```

Expected: the builder and call site do not yet receive the saved week-start value.

- [ ] **Step 3: Thread the setting through the builder**

Extend the builder signature:

```swift
static func makeReport(
    projects: [Project],
    scheduleEntries: [NotificationScheduleEntry],
    weekTodoOffset: Int = 0,
    weekDoneOffset: Int = 0,
    monthDoneOffset: Int = -1,
    now: Date = Date(),
    calendar: Calendar = .current,
    weekStartDay: WeekStartDay = WeekStartDay.resolve(nil)
) -> [OverviewReportSection] {
    let weeklyCalendar = weekStartDay.applying(to: calendar)
    let weekTodoInterval = weekInterval(offset: weekTodoOffset, now: now, calendar: weeklyCalendar)
    let weekDoneInterval = weekInterval(offset: weekDoneOffset, now: now, calendar: weeklyCalendar)
    let monthDoneInterval = monthInterval(offset: monthDoneOffset, now: now, calendar: calendar)
    // existing section construction
}
```

Resolve and pass the singleton setting from `ContentView`:

```swift
weekStartDay: WeekStartDay.resolve(settingsRecords.first?.weekStartDay)
```

- [ ] **Step 4: Perform static checks**

Run:

```bash
rg -n "weekStartDay|weeklyCalendar|monthDoneInterval" Viabar/Models/OverviewReport.swift Viabar/ContentView.swift ViabarTests/ViabarTests.swift
git diff --check
```

Expected: both weekly intervals use `weeklyCalendar`, the month interval keeps `calendar`, and `ContentView` passes the resolved preference.

- [ ] **Step 5: Commit**

```bash
git add -- Viabar/Models/OverviewReport.swift Viabar/ContentView.swift ViabarTests/ViabarTests.swift
git commit -m "feat: apply week start to overview summaries"
```

### Task 3: Add The Display Setting And Localized Labels

**Files:**
- Modify: `Viabar/Views/Settings/SettingsView.swift:225`
- Modify: `Viabar/en.lproj/Localizable.strings:32`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings:32`

- [ ] **Step 1: Add the settings picker**

Insert the row between `总览` and `日期格式`:

```swift
SettingsDivider()
SettingsRow("每周开始于") {
    Picker("每周开始于", selection: weekStartDayBinding) {
        ForEach(WeekStartDay.allCases) { day in
            Text(day.title).tag(day)
        }
    }
    .labelsHidden()
    .controlSize(.small)
    .frame(width: 150, alignment: .trailing)
}
```

Add the binding beside the existing display bindings:

```swift
private var weekStartDayBinding: Binding<WeekStartDay> {
    Binding(
        get: { WeekStartDay.resolve(settings.weekStartDay) },
        set: { settings.weekStartDay = $0.rawValue }
    )
}
```

- [ ] **Step 2: Add localized strings**

Add to both localization files near the other view labels:

```text
"每周开始于" = "Week Starts On";
"周日" = "Sunday";
"周一" = "Monday";
```

```text
"每周开始于" = "每周开始于";
"周日" = "周日";
"周一" = "周一";
```

- [ ] **Step 3: Perform static localization checks**

Run:

```bash
rg -n '"每周开始于"|"周日"|"周一"' Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git diff --check
```

Expected: each key appears in both files, both `.strings` files report `OK`, and whitespace check exits `0`.

- [ ] **Step 4: Commit**

```bash
git add -- Viabar/Views/Settings/SettingsView.swift Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add week start display setting"
```

### Task 4: Preserve Week Start In Backups

**Files:**
- Modify: `ViabarTests/ViabarTests.swift:774`
- Modify: `Viabar/Models/BackupSnapshot.swift:14`
- Modify: `Viabar/Services/BackupService.swift:429`

- [ ] **Step 1: Write backup compatibility tests**

Extend the existing round-trip test with an explicit value:

```swift
var settings = BackupSettingsSnapshot(backupEnabled: true, backupPath: "~/Documents/Viabar")
settings.weekStartDay = WeekStartDay.sunday.rawValue
```

Add a legacy JSON decode contract:

```swift
@Test func decodesLegacyBackupWithoutWeekStart() throws {
    let json = """
    {
      "settingsId": "shared",
      "createdAt": "1970-01-01T00:00:00Z",
      "launchAtLogin": false,
      "menuBarComponentEnabled": false,
      "menuBarIcon": "bookmark.fill",
      "menuBarProjectScope": "allProjects",
      "menuBarContentMode": "currentTask",
      "theme": "system",
      "language": "system",
      "overviewScope": "allProjects",
      "weekdayFilterEnabled": false,
      "dateFormat": "yyyy/MM/dd HH:mm",
      "toggleMainPanelShortcut": "Option+V",
      "openSearchShortcut": "Command+F",
      "syncEnabled": true,
      "backupEnabled": false,
      "backupPath": "",
      "automaticallyChecksForUpdates": true
    }
    """

    let snapshot = try JSONDecoder.backupDecoder.decode(
        BackupSettingsSnapshot.self,
        from: Data(json.utf8)
    )

    #expect(snapshot.weekStartDay == nil)
}
```

Extend `BackupRestoreTests.restoreRebuildsNotificationTimelineFromReminderConfiguration()` after `service.restore(snapshot:)` to prove a legacy snapshot freezes an explicit locale-derived value during restore:

```swift
#expect(
    try context.fetch(FetchDescriptor<AppSettings>()).first?.weekStartDay
        == WeekStartDay.defaultValue().rawValue
)
```

- [ ] **Step 2: Record the expected RED state without compiling**

Run:

```bash
rg -n "weekStartDay" Viabar/Models/BackupSnapshot.swift Viabar/Services/BackupService.swift
```

Expected: backup snapshot and restore service do not yet reference the new field.

- [ ] **Step 3: Add snapshot and restore support**

Add the optional snapshot field:

```swift
var weekStartDay: String?
```

Copy the explicit stored value when making a snapshot:

```swift
weekStartDay = settings.weekStartDay
```

Resolve old or invalid values while restoring:

```swift
settings.weekStartDay = WeekStartDay.resolve(snapshot.weekStartDay).rawValue
```

- [ ] **Step 4: Perform static checks**

Run:

```bash
rg -n "weekStartDay|WeekStartDay.resolve" Viabar/Models/BackupSnapshot.swift Viabar/Services/BackupService.swift ViabarTests/ViabarTests.swift
git diff --check
git status --short
```

Expected: snapshot creation, legacy decode test, restore assignment, and behavior contracts are visible; whitespace check exits `0`.

- [ ] **Step 5: Commit**

```bash
git add -- Viabar/Models/BackupSnapshot.swift Viabar/Services/BackupService.swift ViabarTests/ViabarTests.swift
git commit -m "feat: preserve week start in backups"
```

### Task 5: Final Static Verification

**Files:**
- Verify only: all modified files

- [ ] **Step 1: Check spec coverage**

Run:

```bash
rg -n "WeekStartDay|weekStartDay|每周开始于|周日|周一|weeklyCalendar" Viabar ViabarTests
```

Expected: model policy, bootstrap freeze, builder input, `ContentView` wiring, settings picker, localization, backup snapshot, restore assignment, and tests are all present.

- [ ] **Step 2: Validate strings and whitespace**

Run:

```bash
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git diff --check HEAD~4..HEAD
git status --short
```

Expected: both strings files report `OK`, whitespace check exits `0`, and the worktree is clean.

- [ ] **Step 3: Keep compile-backed verification gated**

Do not run this command unless the user explicitly authorizes compiling:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS'
```

When authorized later, expected result: all tests pass, including the new week-start behavior contracts.
