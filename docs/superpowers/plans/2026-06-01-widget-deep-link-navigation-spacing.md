# Widget Deep Link Navigation And Spacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open the selected Viabar project or Widget task in the main app with the existing search-style highlight, while slightly increasing Widget task-row spacing.

**Architecture:** Add a small app-side URL parser that converts `viabar://navigate/...` URLs into the existing `GlobalSearchNavigationRequest`. Register the URL scheme in the main app, hand incoming URLs to `AppRuntimeController`, and generate matching URLs inside the Widget Extension. Preserve the existing background checkbox intent and use WidgetKit `Link` plus one project-level `widgetURL(_:)` for foreground navigation.

**Tech Stack:** SwiftUI, WidgetKit, Foundation URL parsing, existing `GlobalSearchNavigationRequest`, Swift Testing.

**Repository Constraint:** Do not run `xcodebuild`, Swift tests, previews, app-launch workflows, or Widget installation workflows unless the user explicitly authorizes compilation. Author tests first, then verify with source inspection, `plutil -lint`, and `git diff --check`.

---

## File Map

- Modify `Viabar/Models/GlobalSearch.swift`: add app-side deep-link parsing into existing navigation requests.
- Modify `Viabar/Models/WidgetContent.swift`: carry each Widget row's milestone ID as non-persistent navigation context.
- Modify `ViabarTests/ViabarTests.swift`: specify valid project, milestone, and subtask URLs plus invalid URL rejection.
- Modify `Viabar/ContentView.swift`: consume incoming URLs and delegate valid requests to `AppRuntimeController`.
- Modify `Viabar/Info.plist`: register the `viabar` URL scheme.
- Modify `ViabarWidget/ViabarLargeWidget.swift`: generate deep links, add project-level default navigation, wrap task titles in precise links, and increase task-row spacing.

### Task 1: Parse Widget Navigation URLs

**Files:**
- Modify: `Viabar/Models/GlobalSearch.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [x] **Step 1: Add parser expectations**

Add tests that require:

```swift
#expect(WidgetNavigationURL.navigationRequest(from: URL(string: "viabar://navigate/project/<uuid>")!)?.destination == .project)
#expect(WidgetNavigationURL.navigationRequest(from: URL(string: "viabar://navigate/milestone/<project>/<milestone>")!)?.destination == .milestone(milestoneID))
#expect(WidgetNavigationURL.navigationRequest(from: URL(string: "viabar://navigate/subtask/<project>/<milestone>/<subtask>")!)?.destination == .subTask(milestoneID: milestoneID, subTaskID: subTaskID))
#expect(WidgetNavigationURL.navigationRequest(from: URL(string: "https://navigate/project/<uuid>")!) == nil)
```

- [x] **Step 2: Leave red execution paused**

Do not run the Swift test target without explicit compilation authorization.

- [x] **Step 3: Add the minimal parser**

Implement `WidgetNavigationURL.navigationRequest(from:)` with strict checks for scheme `viabar`, host `navigate`, known path shapes, and valid UUID strings.

### Task 2: Route Incoming URLs Through Existing Runtime Navigation

**Files:**
- Modify: `Viabar/ContentView.swift`
- Modify: `Viabar/Info.plist`

- [x] **Step 1: Register the URL scheme**

Add `CFBundleURLTypes` with URL scheme `viabar`.

- [x] **Step 2: Consume URLs in the main content root**

Add:

```swift
.onOpenURL { url in
    guard let request = WidgetNavigationURL.navigationRequest(from: url) else { return }
    runtimeController.navigate(to: request)
}
```

The existing pending-navigation flow remains responsible for opening the window, selecting the project, scrolling, and highlighting.

### Task 3: Add Widget Links And Increase Row Spacing

**Files:**
- Modify: `ViabarWidget/ViabarLargeWidget.swift`

- [x] **Step 1: Add Widget URL generation**

Create local `ViabarWidgetNavigationURL` helpers for project, milestone, and subtask URLs using UUID strings. Add `WidgetTaskItem.milestoneID` so subtask URLs include their parent milestone.

- [x] **Step 2: Add the default project URL**

Apply:

```swift
.widgetURL(ViabarWidgetNavigationURL.project(content.projectID))
```

to the content root.

- [x] **Step 3: Add precise task-title links**

Wrap the title/reminder text area in `Link(destination:)`, choosing milestone or subtask URL based on `WidgetTaskKind`. Keep the checkbox as the existing `Button(intent:)`.

- [x] **Step 4: Increase spacing**

Change the task-list `VStack` spacing from `7` to `9`.

### Task 4: Static Verification

**Files:**
- Inspect all modified files.

- [x] **Step 1: Inspect wiring**

Run:

```bash
rg -n "widgetURL|Link\\(|onOpenURL|CFBundleURLTypes|viabar|WidgetNavigationURL" Viabar ViabarWidget ViabarTests --glob '*.swift' --glob '*.plist'
```

- [x] **Step 2: Lint property lists**

Run:

```bash
plutil -lint Viabar/Info.plist ViabarWidget/Info.plist
```

- [x] **Step 3: Check whitespace**

Run:

```bash
git diff --check
```

- [x] **Step 4: Record deferred verification**

Report that compilation, test execution, and installed Widget interaction testing remain intentionally unexecuted because the user did not authorize compilation.
