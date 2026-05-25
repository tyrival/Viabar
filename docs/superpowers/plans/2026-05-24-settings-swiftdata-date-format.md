# Settings SwiftData Persistence And Date Format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native macOS Settings window whose configurable values persist in one SwiftData record, and make the selected date format drive reminder and memo timestamps.

**Architecture:** Introduce `AppSettings` as a singleton-style SwiftData entity plus small enums and a shared `AppDateFormatter` in a focused support file. Ensure default settings exist when the application initializes, query that record from the settings panel and the three timestamp-rendering components, and leave all settings other than date format disconnected from behavior for now.

**Tech Stack:** SwiftUI `Settings` scene and `NavigationSplitView`, SwiftData `@Model` / `@Query` / `@Bindable`, Foundation `DateFormatter`, Swift Testing source coverage.

---

## Constraints

- The top application menu opens the native Settings scene; do not add `MenuBarExtra` or a system status item.
- Every configurable field belongs to one SwiftData `AppSettings` record, including macOS-only fields that a future iOS app may ignore.
- Only `dateFormat` changes current product behavior. Theme, language, filtering, shortcuts, sync, backup, launch, and menu-bar settings persist but do not execute functionality.
- Do not change `Reminder`, `NotificationScheduleEntry`, `NotificationScheduleService`, or reminder rescheduling/notification semantics.
- The project uses file-system-synchronized Xcode groups, so adding Swift files below `Viabar/` and `ViabarTests/` does not require editing `Viabar.xcodeproj/project.pbxproj`.
- The repository instruction forbids compiling unless separately requested. Swift Testing execution compiles the target, so implementation adds test source but does not run it without permission; verification defaults to source inspection and `git diff --check`.

## File Structure

- Create `Viabar/Models/AppSettings.swift`: SwiftData settings entity, supported preference enums, default record bootstrap, and shared date formatter.
- Create `Viabar/Views/Settings/SettingsView.swift`: sidebar-detail Settings window and persisted form controls.
- Modify `Viabar/ViabarApp.swift`: register `AppSettings`, bootstrap its default row, and declare the native `Settings` scene.
- Modify `Viabar/ContentView.swift`: format overview-card reminder timestamps through the saved date-format selection and register `AppSettings` in its preview container.
- Modify `Viabar/Views/MainPanel/MilestoneListView.swift`: format displayed milestone/subtask reminder timestamps through the saved selection without touching status/repeat logic.
- Modify `Viabar/Views/MainPanel/MemoTimelineView.swift`: format memo-card timestamps through the saved selection.
- Modify `ViabarTests/ViabarTests.swift`: add default-value and pure date-format output coverage source.

### Task 1: Define Persisted Settings And Date Formatting Contract

**Files:**
- Create: `Viabar/Models/AppSettings.swift`
- Modify: `ViabarTests/ViabarTests.swift`

- [x] **Step 1: Add behavior coverage source before production implementation**

Append a Swift Testing suite which defines the required defaults and formatter
outputs. Add `import Foundation` at the top of the test file because the test
uses fixed `DateComponents`.

```swift
struct AppSettingsTests {
    @Test func initializesDocumentedDefaults() {
        let settings = AppSettings()

        #expect(settings.launchAtLogin == false)
        #expect(settings.menuBarComponentEnabled == false)
        #expect(settings.theme == AppTheme.system.rawValue)
        #expect(settings.language == AppLanguage.system.rawValue)
        #expect(settings.overviewScope == OverviewScope.allProjects.rawValue)
        #expect(settings.weekdayFilterEnabled == false)
        #expect(settings.dateFormat == AppDateFormat.yearMonthDaySlashes.rawValue)
        #expect(settings.toggleMainPanelShortcut == "Option+V")
        #expect(settings.openSearchShortcut == "Command+F")
        #expect(settings.syncEnabled == true)
        #expect(settings.lastSyncAt == nil)
        #expect(settings.backupEnabled == true)
        #expect(settings.backupPath == "~/Documents/Viabar")
    }

    @Test func formatsDatesUsingEverySupportedSelection() {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 5, day: 24, hour: 14, minute: 30)
        )!

        #expect(AppDateFormatter.string(from: date, pattern: "yyyy/MM/dd HH:mm") == "2026/05/24 14:30")
        #expect(AppDateFormatter.string(from: date, pattern: "yyyy-MM-dd HH:mm") == "2026-05-24 14:30")
        #expect(AppDateFormatter.string(from: date, pattern: "MM/dd HH:mm") == "05/24 14:30")
        #expect(AppDateFormatter.string(from: date, pattern: "dd/MM/yyyy HH:mm") == "24/05/2026 14:30")
    }

    @Test func fallsBackToDefaultDateFormatForUnknownSavedValue() {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 5, day: 24, hour: 14, minute: 30)
        )!

        #expect(AppDateFormatter.string(from: date, pattern: "invalid") == "2026/05/24 14:30")
    }
}
```

- [x] **Step 2: Record the deferred red-test boundary**

Running `xcodebuild test` or the equivalent Swift Testing command would compile
the target. Because compilation is not authorized, do not run the new tests in
this implementation pass. Record in the completion report that the tests are
authored but their red/green evidence is intentionally deferred until the user
permits compilation.

- [x] **Step 3: Create selection types and the SwiftData settings model**

Create `Viabar/Models/AppSettings.swift` with string-backed values that are
safe to persist and simple for future iOS consumers to ignore when irrelevant:

```swift
import Foundation
import SwiftData

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "系统"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

enum OverviewScope: String, CaseIterable, Identifiable {
    case allProjects
    case favoriteProjects

    var id: String { rawValue }
    var title: String {
        switch self {
        case .allProjects: "所有项目"
        case .favoriteProjects: "星标项目"
        }
    }
}

enum AppDateFormat: String, CaseIterable, Identifiable {
    case yearMonthDaySlashes = "yyyy/MM/dd HH:mm"
    case yearMonthDayDashes = "yyyy-MM-dd HH:mm"
    case monthDay = "MM/dd HH:mm"
    case dayMonthYear = "dd/MM/yyyy HH:mm"

    static let defaultValue = AppDateFormat.yearMonthDaySlashes
    var id: String { rawValue }

    var example: String {
        AppDateFormatter.string(from: AppDateFormatter.exampleDate, pattern: rawValue)
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var settingsId: String
    var createdAt: Date
    var launchAtLogin: Bool
    var menuBarComponentEnabled: Bool
    var theme: String
    var language: String
    var overviewScope: String
    var weekdayFilterEnabled: Bool
    var dateFormat: String
    var toggleMainPanelShortcut: String
    var openSearchShortcut: String
    var syncEnabled: Bool
    var lastSyncAt: Date?
    var backupEnabled: Bool
    var backupPath: String

    init(
        settingsId: String = "shared",
        createdAt: Date = Date(),
        launchAtLogin: Bool = false,
        menuBarComponentEnabled: Bool = false,
        theme: String = AppTheme.system.rawValue,
        language: String = AppLanguage.system.rawValue,
        overviewScope: String = OverviewScope.allProjects.rawValue,
        weekdayFilterEnabled: Bool = false,
        dateFormat: String = AppDateFormat.defaultValue.rawValue,
        toggleMainPanelShortcut: String = "Option+V",
        openSearchShortcut: String = "Command+F",
        syncEnabled: Bool = true,
        lastSyncAt: Date? = nil,
        backupEnabled: Bool = true,
        backupPath: String = "~/Documents/Viabar"
    ) {
        self.settingsId = settingsId
        self.createdAt = createdAt
        self.launchAtLogin = launchAtLogin
        self.menuBarComponentEnabled = menuBarComponentEnabled
        self.theme = theme
        self.language = language
        self.overviewScope = overviewScope
        self.weekdayFilterEnabled = weekdayFilterEnabled
        self.dateFormat = dateFormat
        self.toggleMainPanelShortcut = toggleMainPanelShortcut
        self.openSearchShortcut = openSearchShortcut
        self.syncEnabled = syncEnabled
        self.lastSyncAt = lastSyncAt
        self.backupEnabled = backupEnabled
        self.backupPath = backupPath
    }
}
```

- [x] **Step 4: Add singleton bootstrap and pure date-format helpers**

In the same file, add a bootstrap helper that makes an initial persisted record
available before the app renders settings-dependent text, and a formatter that
normalizes unsupported saved strings to the default:

```swift
@MainActor
enum AppSettingsStore {
    static func ensureDefaultSettings(in context: ModelContext) {
        var descriptor = FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\AppSettings.createdAt)]
        )
        descriptor.fetchLimit = 1

        guard (try? context.fetch(descriptor).first) == nil else { return }
        context.insert(AppSettings())
        try? context.save()
    }
}

enum AppDateFormatter {
    static let exampleDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 5, day: 24, hour: 14, minute: 30)
    )!

    static func resolvedFormat(for rawValue: String?) -> AppDateFormat {
        AppDateFormat(rawValue: rawValue ?? "") ?? .defaultValue
    }

    static func string(from date: Date, pattern: String?) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = resolvedFormat(for: pattern).rawValue
        return formatter.string(from: date)
    }
}
```

### Task 2: Register The Settings Model And Native Settings Scene

**Files:**
- Modify: `Viabar/ViabarApp.swift`

- [x] **Step 1: Register and bootstrap `AppSettings`**

Append `AppSettings.self` to the existing `Schema` list. Immediately after
successfully creating `sharedModelContainer`, create the singleton defaults:

```swift
AppSettingsStore.ensureDefaultSettings(in: sharedModelContainer.mainContext)
```

Keep the existing project and notification service configuration unchanged.

- [x] **Step 2: Add the native Settings scene**

Extend `body` with a separate settings scene that receives the same SwiftData
container:

```swift
Settings {
    SettingsView()
        .modelContainer(sharedModelContainer)
}
```

Do not add a custom command, status item, or `MenuBarExtra`; macOS supplies the
top-menu Settings command for this scene.

### Task 3: Build The Sidebar-Detail Settings Window

**Files:**
- Create: `Viabar/Views/Settings/SettingsView.swift`

- [x] **Step 1: Define category selection and load the singleton record**

Create a settings root that owns only window-local selection and queries the
persisted record initialized by `ViabarApp`:

```swift
import SwiftData
import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用"
    case display = "显示"
    case shortcuts = "快捷键"
    case syncAndBackup = "数据同步与备份"
    case about = "关于"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .display: "display"
        case .shortcuts: "keyboard"
        case .syncAndBackup: "arrow.trianglehead.2.clockwise.rotate.90"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var selection: SettingsCategory? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { category in
                Label(category.rawValue, systemImage: category.icon).tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 184, max: 220)
        } detail: {
            if let settings = settingsRecords.first {
                SettingsDetailView(category: selection ?? .general, settings: settings)
            } else {
                ProgressView().task {
                    AppSettingsStore.ensureDefaultSettings(in: modelContext)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 470)
    }
}
```

- [x] **Step 2: Implement bindable persisted controls**

Create `SettingsDetailView` with `@Bindable var settings: AppSettings` and
switch on `category`. Use native `Form` sections, direct Boolean bindings for
toggles, and computed `Binding` wrappers for persisted enum strings:

```swift
private struct SettingsDetailView: View {
    let category: SettingsCategory
    @Bindable var settings: AppSettings

    private var dateFormatBinding: Binding<AppDateFormat> {
        Binding(
            get: { AppDateFormatter.resolvedFormat(for: settings.dateFormat) },
            set: { settings.dateFormat = $0.rawValue }
        )
    }
}
```

The five detail panels expose these concrete controls:

- `通用`: toggles for `开机启动` and `启用菜单栏组件`.
- `显示`: pickers for `主题`, `语言`, `总览`, a `工作日过滤` toggle, and a
  date-format picker displaying `format.rawValue` plus `format.example`.
- `快捷键`: editable text fields bound to `toggleMainPanelShortcut` and
  `openSearchShortcut`, with labels `全局显示/隐藏主面板` and `打开搜索框`.
- `数据同步与备份`: toggles for `syncEnabled` and `backupEnabled`, display
  `lastSyncAt` as `尚未同步` or `AppDateFormatter.string(...)`, an editable
  `backupPath` text field, plus disabled `立即同步`, `数据导入`, and `数据导出`
  buttons.
- `关于`: read version from
  `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")`,
  falling back to `--`, and show disabled rows/buttons for `Telegram`,
  `App Store 评分`, `许可证`, and `协议`.

Do not implement side effects in toggle, picker, or placeholder button
handlers; SwiftData observes changes to the `@Bindable` model and persists
them through its context.

- [x] **Step 3: Add a settings preview with an in-memory record**

Add a preview container containing `AppSettings.self`, insert one default
`AppSettings` row in the preview closure, and render `SettingsView` so the
sidebar-detail layout remains previewable without launching the full app.

### Task 4: Apply The Date Setting To All Requested Timestamp Surfaces

**Files:**
- Modify: `Viabar/ContentView.swift`
- Modify: `Viabar/Views/MainPanel/MilestoneListView.swift`
- Modify: `Viabar/Views/MainPanel/MemoTimelineView.swift`

- [x] **Step 1: Update overview reminder timestamps**

In `OverviewProjectCard`, query the singleton settings record:

```swift
@Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]

private var savedDateFormat: String? {
    settingsRecords.first?.dateFormat
}
```

Replace:

```swift
Text(reminderDate.formattedOverviewReminder(relativeTo: Date()))
```

with:

```swift
Text(AppDateFormatter.string(from: reminderDate, pattern: savedDateFormat))
```

Remove only `Date.formattedOverviewReminder(relativeTo:)`; preserve
`Reminder.overviewFireDate`, overdue checks, and today-pending color logic.
Append `AppSettings.self` to the `ContentView` preview model container.

- [x] **Step 2: Update milestone and subtask reminder summary timestamps**

In `ReminderStatusView`, add the same `@Query` and `savedDateFormat`. Replace
the text call with a function that receives the persisted pattern:

```swift
Text(reminder.inlineReminderSummary(dateFormatPattern: savedDateFormat))
```

Change the existing `Reminder` extension without altering its fire-date or
repeat-status logic:

```swift
func inlineReminderSummary(dateFormatPattern: String?) -> String {
    let time = inlineFireDate.map {
        AppDateFormatter.string(from: $0, pattern: dateFormatPattern)
    } ?? "--"
    guard isRepeating else { return time }
    return "\(time) \(inlineRepeatTitle)"
}
```

Delete `formattedInlineReminderTime`, because its relative date behavior is no
longer a display path. Leave `formatCompletionTimestamp(_:)` unchanged: it
formats completion status, not a requested alarm timestamp.

- [x] **Step 3: Update memo-card timestamps**

In `MemoCardView`, query settings and change:

```swift
Text(formatTimestamp(memo.createdAt))
```

to:

```swift
Text(AppDateFormatter.string(from: memo.createdAt, pattern: settingsRecords.first?.dateFormat))
```

Delete the private `formatTimestamp(_:)` function so the memo card no longer
has an independent relative timestamp format.

### Task 5: Static Verification And Delivery

**Files:**
- Verify: `Viabar/Models/AppSettings.swift`
- Verify: `Viabar/Views/Settings/SettingsView.swift`
- Verify: `Viabar/ViabarApp.swift`
- Verify: `Viabar/ContentView.swift`
- Verify: `Viabar/Views/MainPanel/MilestoneListView.swift`
- Verify: `Viabar/Views/MainPanel/MemoTimelineView.swift`
- Verify: `ViabarTests/ViabarTests.swift`

- [x] **Step 1: Inspect schema and feature-scope coverage**

Run:

```bash
rg -n "AppSettings|Settings \\{|AppDateFormatter|dateFormat|立即同步|数据导入|数据导出|formattedOverviewReminder|formattedInlineReminderTime|formatTimestamp" Viabar ViabarTests
```

Expected: `AppSettings` appears in model/schema/settings views and tests;
`AppDateFormatter` appears in all three requested timestamp paths;
unimplemented sync/import/export actions appear only as settings UI
placeholders; the three removed per-surface formatting helper names no longer
appear.

- [x] **Step 2: Inspect reminder behavior isolation**

Run:

```bash
git diff -- Viabar/Models/Project.swift Viabar/Services/NotificationScheduleService.swift Viabar/Services/ProjectService.swift Viabar/Views/Component/ReminderSettingsPopover.swift
```

Expected: no output, because this feature must not change reminder model,
scheduling, editing, or project service behavior.

- [x] **Step 3: Check patch formatting without compiling**

Run:

```bash
git diff --check
```

Expected: exit code `0` and no output.

- [x] **Step 4: Defer compilation-dependent test execution explicitly**

Do not run `xcodebuild build`, `xcodebuild test`, or open/run the app unless
the user separately permits compilation. In the completion report, state that
Swift Testing coverage source was added but automated execution was deferred
under the repository instruction.
