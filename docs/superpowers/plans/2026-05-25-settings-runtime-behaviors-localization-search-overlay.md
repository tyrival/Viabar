# Settings Runtime Behaviors, Localization, And Search Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate launch-at-login, immediate application language, overview scope, and running-app global shortcuts from Settings, while constraining the global-search gradient to the central toolbar area.

**Architecture:** Keep `AppSettings` as the persisted source of choice and introduce small application-boundary controllers for login-item state, effective language, and global hot-key commands. SwiftUI roots read the shared settings record to inject locale immediately, `ContentView` owns overview filtering and search command/layout state, and localized resource files translate all built-in interface copy without changing user content.

**Tech Stack:** SwiftUI, SwiftData, AppKit, ServiceManagement (`SMAppService`), Carbon hot-key registration, `.strings` localized resources, Swift Testing.

**Repository Constraint:** Do not run `xcodebuild`, Swift tests, previews, or app launch workflows unless the user explicitly authorizes compilation. Test expectations are authored first, but this pass verifies only through focused source inspection and `git diff --check`.

---

## File Map

- Modify `Viabar/Models/AppSettings.swift`: effective language resolution, overview filtering, and shortcut validation helpers.
- Modify `ViabarTests/ViabarTests.swift`: behavioral expectations for language resolution, overview filtering, and duplicate shortcut rejection.
- Create `Viabar/System/AppLaunchAtLoginController.swift`: Service Management registration and status reconciliation.
- Create `Viabar/System/AppGlobalShortcutController.swift`: process-lifetime global hot-key registration and command callbacks.
- Create `Viabar/System/AppRuntimeController.swift`: shared application command/window/registration coordinator injected into scenes.
- Modify `Viabar/ViabarApp.swift`: create the runtime coordinator, configure persisted settings, and inject it into main and Settings scenes.
- Modify `Viabar/ContentView.swift`: observe shared settings, show the main window bridge, present search from a shortcut command, filter overview cards, and confine the toolbar gradient to central detail width.
- Modify `Viabar/Views/Settings/SettingsView.swift`: live launch toggle, language selection, shortcut reconfiguration and errors, remove weekday row and shortcut descriptions.
- Modify `Viabar/Views/Settings/ShortcutRecorderField.swift`: keep recorder copy localizable.
- Modify `Viabar/Views/Component/GlobalSearchOverlay.swift`: expose a presentation trigger/focus path shared by toolbar and shortcut activation and localize copy.
- Modify UI view files under `Viabar/Views` and fixed display-label code in `Viabar/Models/GlobalSearch.swift` / `Viabar/System/ViabarColor.swift`: localize built-in visible strings.
- Create `Viabar/en.lproj/Localizable.strings`: English strings.
- Create `Viabar/zh-Hans.lproj/Localizable.strings`: Simplified Chinese strings.

### Task 1: Specify Pure Language, Overview, And Shortcut Rules

**Files:**
- Modify: `ViabarTests/ViabarTests.swift`
- Modify: `Viabar/Models/AppSettings.swift`

- [ ] **Step 1: Add behavioral expectations before production implementation**

Add tests with these assertions:

```swift
@Test func resolvesLanguageImmediatelyWithEnglishSystemFallback() {
    #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
    #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["en-SG"]) == .english)
    #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["zh-Hant-TW"]) == .english)
    #expect(AppLanguage.effectiveLanguage(storedValue: "system", preferredLanguages: ["ja-JP"]) == .english)
    #expect(AppLanguage.effectiveLanguage(storedValue: "invalid", preferredLanguages: ["zh-Hans"]) == .simplifiedChinese)
    #expect(AppLanguage.effectiveLanguage(storedValue: "english", preferredLanguages: ["zh-Hans"]) == .english)
    #expect(AppLanguage.effectiveLanguage(storedValue: "simplifiedChinese", preferredLanguages: ["en"]) == .simplifiedChinese)
}

@Test func overviewScopeFiltersOnlyActiveProjects() {
    let active = Project(title: "Active")
    let favorite = Project(title: "Favorite")
    favorite.isFavorite = true
    let archivedFavorite = Project(title: "Archived")
    archivedFavorite.isFavorite = true
    archivedFavorite.isArchived = true

    #expect(OverviewScope.visibleProjects(from: [active, favorite, archivedFavorite], storedValue: "allProjects").map(\.title) == ["Active", "Favorite"])
    #expect(OverviewScope.visibleProjects(from: [active, favorite, archivedFavorite], storedValue: "favoriteProjects").map(\.title) == ["Favorite"])
    #expect(OverviewScope.visibleProjects(from: [active, favorite], storedValue: "invalid").count == 2)
}

@Test func rejectsDuplicateConfiguredShortcuts() {
    #expect(AppShortcutConfiguration(toggleMainPanel: "Option+V", openSearch: "Command+F").isValid)
    #expect(!AppShortcutConfiguration(toggleMainPanel: "Option+V", openSearch: "Option+V").isValid)
}
```

- [ ] **Step 2: Leave executable red verification paused**

Do not run `xcodebuild test` because compilation is not authorized. Record this
test-first contract in the final handoff as source-authored but unexecuted.

- [ ] **Step 3: Implement the minimum pure model helpers**

Add:

```swift
enum EffectiveAppLanguage: String {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var locale: Locale { Locale(identifier: rawValue) }
}

extension AppLanguage {
    static func effectiveLanguage(storedValue: String?, preferredLanguages: [String]) -> EffectiveAppLanguage {
        switch AppLanguage(rawValue: storedValue ?? "") ?? .system {
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        case .system:
            let preferred = preferredLanguages.first?.lowercased() ?? ""
            return preferred.hasPrefix("zh-hans") || preferred.hasPrefix("zh_cn")
                ? .simplifiedChinese
                : .english
        }
    }
}

extension OverviewScope {
    static func visibleProjects(from projects: [Project], storedValue: String?) -> [Project] {
        let scope = OverviewScope(rawValue: storedValue ?? "") ?? .allProjects
        return projects.filter { !$0.isArchived && (scope == .allProjects || $0.isFavorite) }
            .sorted { $0.orderIndex < $1.orderIndex }
    }
}

struct AppShortcutConfiguration {
    let toggleMainPanel: String
    let openSearch: String
    var isValid: Bool { toggleMainPanel != openSearch }
}
```

### Task 2: Add Application Runtime Controllers

**Files:**
- Create: `Viabar/System/AppLaunchAtLoginController.swift`
- Create: `Viabar/System/AppGlobalShortcutController.swift`
- Create: `Viabar/System/AppRuntimeController.swift`
- Modify: `Viabar/ViabarApp.swift`

- [ ] **Step 1: Implement login item reconciliation**

Create an `@MainActor @Observable` controller around `SMAppService.mainApp`
whose `isEnabled` reads `.status == .enabled`, and whose update function calls
`register()` or `unregister()`, refreshes status after success/failure, and
returns a localized-error key for Settings presentation on failure.

- [ ] **Step 2: Implement exactly two process-lifetime global hot keys**

Create a hot-key controller that:

```swift
enum AppShortcutCommand: UInt32 {
    case toggleMainPanel = 1
    case openSearch = 2
}

func reconfigure(_ configuration: AppShortcutConfiguration) throws
var onCommand: ((AppShortcutCommand) -> Void)?
```

Map the existing canonical `ShortcutKeyCombination` values to Carbon key codes
and modifier flags, reject duplicate configurations before replacing active
registrations, register with `RegisterEventHotKey`, and unregister tokens on
replacement/deinitialization. Keep old registrations active when replacement
fails.

- [ ] **Step 3: Coordinate main-window actions**

Create `AppRuntimeController` to own login/hot-key controllers and a weak
reference to the main `NSWindow`. It exposes:

```swift
var searchPresentationID = UUID()
func registerMainWindow(_ window: NSWindow?)
func configureShortcuts(from settings: AppSettings) throws
func toggleMainPanel()
func presentSearch()
```

`toggleMainPanel()` orders out a main window only when it is already the active
key window; if hidden or behind another application it activates the app and
makes that window key/front; if the last main window was closed while the
process remains running it uses `openWindow(id: "main")` to create a
replacement window. `presentSearch()` first reveals or reopens that window
and mutates `searchPresentationID`, which `ContentView` observes or consumes
when a replacement content view appears.

- [ ] **Step 4: Inject and configure runtime state at the app boundary**

In `ViabarApp`, create one stateful runtime controller, give the main
`WindowGroup` a stable `main` id, inject it into the `WindowGroup` and
`Settings` content, and configure appearance plus saved shortcuts from the
shared `AppSettings` record in the existing mounted task. Do not make
terminated-app launching part of the hot-key controller.

### Task 3: Activate Settings Controls And Overview Filtering

**Files:**
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Modify: `Viabar/ContentView.swift`
- Modify: `Viabar/Views/Component/GlobalSearchOverlay.swift`

- [ ] **Step 1: Replace launch toggle persistence with system action**

Read `AppRuntimeController` from the environment in Settings, reconcile
`settings.launchAtLogin` with actual status on appearance, and route the
launch switch through the login controller. If it fails, restore effective
state and display an alert with localizable title/message.

- [ ] **Step 2: Remove unused/settings-only copy**

Delete the visible `工作日过滤` row and both shortcut `description:` values;
retain the stored `weekdayFilterEnabled` property for compatibility.

- [ ] **Step 3: Apply changed shortcuts without losing working values**

Before a recorder mutation, capture the old saved value. Reject a duplicate or
failed runtime registration, restore that prior value, and show the localized
error; only keep the new stored value when global registration succeeds.

- [ ] **Step 4: Bind overview cards to the scope setting**

Have `ContentView` query `AppSettings`, pass its `overviewScope` into
`OverviewDashboardView`, and replace the card filter with
`OverviewScope.visibleProjects(from:storedValue:)`. Leave sidebar/search data
sources unchanged.

- [ ] **Step 5: Share search presentation between click and shortcut**

Have `ContentView` observe `runtimeController.searchPresentationID` and invoke
the same `presentGlobalSearch()` path used by the magnifying-glass control. Do
not add a second independent query/focus state.

### Task 4: Add Immediate Localization Across Visible Interface Copy

**Files:**
- Create: `Viabar/en.lproj/Localizable.strings`
- Create: `Viabar/zh-Hans.lproj/Localizable.strings`
- Modify: `Viabar/ViabarApp.swift`
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Modify: `Viabar/ContentView.swift`
- Modify: `Viabar/Views/Sidebar/SidebarView.swift`
- Modify: `Viabar/Views/MainPanel/MilestoneListView.swift`
- Modify: `Viabar/Views/MainPanel/MemoTimelineView.swift`
- Modify: `Viabar/Views/Component/*.swift`
- Modify: `Viabar/Models/AppSettings.swift`
- Modify: `Viabar/Models/GlobalSearch.swift`
- Modify: `Viabar/System/ViabarColor.swift`

- [ ] **Step 1: Add two localization resource tables**

Add `Localizable.strings` resources with every built-in UI key currently shown
in the main window, Settings, popovers and sheets. English translations include
navigation/actions such as `"总览" = "Overview";`, `"归档" = "Archive";`,
`"打开搜索框" = "Open Search";`; Simplified Chinese entries preserve the
existing Chinese product copy.

- [ ] **Step 2: Inject the resolved locale into both scenes**

Read the singleton settings record in small main/settings root wrappers and
apply:

```swift
.environment(\.locale, AppLanguage.effectiveLanguage(
    storedValue: settings.language,
    preferredLanguages: Locale.preferredLanguages
).locale)
```

Changing the language picker then refreshes both open windows without restarting
the process. Invalid or unsupported system-language selection follows the
English fallback defined in Task 1.

- [ ] **Step 3: Convert string-producing UI paths to localizable values**

Change enum display titles, alert/prompt computed properties, conditional
labels, reminder repeat titles, color help labels, and archived search display
prefixes so they render from localizable keys rather than fixed runtime
`String` values. Do not localize project/milestone/memo/template/folder names
created by the user.

### Task 5: Fix Search Gradient Ownership

**Files:**
- Modify: `Viabar/ContentView.swift`

- [ ] **Step 1: Isolate the fixed toolbar background from the floating results**

Move/size the `toolbarGradientMask` so its fixed
`toolbarGradientHeight` area belongs only to the detail panel: apply sidebar
leading exclusion from the `NavigationSplitView` layout and the existing memo
drawer trailing exclusion, while allowing `GlobalSearchOverlay` results to
render beyond that fixed background height.

- [ ] **Step 2: Keep search behavior unchanged**

Do not alter result matching, keyboard movement, outside-click dismissal,
navigation routing, or result-list height. The only search UI behavior change
is the gradient's area and independence from candidate-list height.

### Task 6: Validate Without Compilation

**Files:**
- Inspect: all changed source/resource files

- [ ] **Step 1: Source-check required behaviors**

Use focused `rg` checks to confirm:

- `SMAppService.mainApp` is wired to `launchAtLogin`;
- both shortcut actions reach the runtime controller and search shares one
  presentation path;
- `weekdayFilterEnabled` has no Settings row;
- the two shortcut descriptions are absent;
- locale injection occurs for both scene roots and resource tables exist;
- overview passes through `OverviewScope.visibleProjects`;
- gradient ownership excludes sidebar and memo drawer with fixed toolbar height.

- [ ] **Step 2: Check patch integrity**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 3: Report verification limits honestly**

Report that compilation, test execution, hot-key runtime registration,
login-item behavior, live localization rendering, and visual overlay validation
remain unexecuted because the user instructed that code not be compiled unless
explicitly requested.
