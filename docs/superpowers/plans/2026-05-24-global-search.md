# Global Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent top-bar global search that finds tasks, subtasks, and memos across active and archived projects and navigates to each match.

**Architecture:** Keep search ownership in `ContentView`, which already owns sidebar selection, the memo drawer, and floating toolbar placement. Add one pure search model/index file, one focused overlay view, and narrowly scoped navigation bindings for the sidebar and content panels so archived reveal and one-time scroll targets do not leak into persistence.

**Tech Stack:** SwiftUI, SwiftData model objects, Swift Testing, macOS keyboard input through SwiftUI key handlers.

**Verification constraint:** The repository instruction says not to compile code for investigation unless explicitly requested. Unit test commands below are the correct RED/GREEN checks, but must not be executed in this implementation session unless the user separately authorizes compilation.

---

## File Map

- Create `Viabar/Models/GlobalSearch.swift`: search result identity, navigation target, query matching, path formatting, and active/archive ordering.
- Create `Viabar/Views/Component/GlobalSearchOverlay.swift`: expanding search field and Spotlight-style result list with pointer and keyboard selection.
- Modify `Viabar/ContentView.swift`: global search state, toolbar placement on overview and project screens, and routing from a selected result into panels/sidebar.
- Modify `Viabar/Views/Sidebar/SidebarView.swift`: accept an archived project reveal request and open the archive folder ancestor chain.
- Modify `Viabar/Views/MainPanel/MainSplitView.swift`: forward one-time search navigation targets to the milestone list.
- Modify `Viabar/Views/MainPanel/MilestoneListView.swift`: temporarily include a hidden completed destination and scroll to task/subtask rows.
- Modify `Viabar/Views/MainPanel/MemoTimelineView.swift`: scroll to a selected memo when global search navigates to it.
- Modify `ViabarTests/ViabarTests.swift`: replace placeholder test with search matching and path-format tests.

### Task 1: Pure Search Index And Formatting Rules

**Files:**
- Create: `Viabar/Models/GlobalSearch.swift`
- Modify: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Write tests for task, subtask, memo, and archive paths**

Replace the placeholder test with model-based specifications:

```swift
import Testing
@testable import Viabar

struct GlobalSearchTests {
    @Test func buildsTaskSubtaskAndMemoResults() {
        let project = Project(title: "发布计划", orderIndex: 0)
        let milestone = Milestone(title: "准备发布页面信息架构复核", orderIndex: 0)
        milestone.project = project
        let subtask = SubTask(title: "发布公告复核", orderIndex: 0)
        subtask.milestone = milestone
        milestone.subtasks = [subtask]
        project.milestones = [milestone]
        let memo = Memo(content: "发布检查已结束", orderIndex: 0)
        memo.project = project
        project.memos = [memo]

        let results = GlobalSearchIndex.results(matching: "发布", projects: [project])

        #expect(results.map(\.text) == ["准备发布页面信息架构复核", "发布公告复核", "发布检查已结束"])
        #expect(results.map(\.path) == [
            "发布计划 / 准备发布页面信息架构复核",
            "发布计划 / 准备发布页面信息架… / 发布公告复核",
            "发布计划 / 备忘录"
        ])
    }

    @Test func prefixesArchivedResultsAndKeepsFolderTreeOrder() {
        let folder = ArchiveFolder(name: "旧版本", orderIndex: 0)
        let project = Project(title: "历史发布", orderIndex: 0)
        project.isArchived = true
        project.archiveFolder = folder
        folder.projects = [project]
        let memo = Memo(content: "发布回顾", orderIndex: 0)
        memo.project = project
        project.memos = [memo]

        let results = GlobalSearchIndex.results(matching: "发布", projects: [project])

        #expect(results.map(\.path) == ["归档 / 历史发布 / 备忘录"])
    }
}
```

- [ ] **Step 2: Do not run the failing test without compilation authorization**

The RED command, if later authorized, is:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/GlobalSearchTests
```

Expected before implementation: compile/test failure because `GlobalSearchIndex` is undefined. In this session record it as not run because executing it compiles the app and conflicts with the repository instruction.

- [ ] **Step 3: Add the result model, destination model, and index builder**

Create `GlobalSearch.swift` with these public-to-module contracts:

```swift
import Foundation

enum GlobalSearchDestination: Equatable {
    case milestone(UUID)
    case subTask(milestoneID: UUID, subTaskID: UUID)
    case memo(UUID)
}

struct GlobalSearchNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let projectID: UUID
    let destination: GlobalSearchDestination
}

struct GlobalSearchResult: Identifiable {
    let id: String
    let project: Project
    let text: String
    let path: String
    let destination: GlobalSearchDestination
}

enum GlobalSearchIndex {
    static func results(matching query: String, projects: [Project]) -> [GlobalSearchResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return orderedProjects(from: projects).flatMap { project in
            results(in: project, matching: term)
        }
    }

    private static func compactMilestoneTitle(_ title: String) -> String {
        guard title.count > 10 else { return title }
        return String(title.prefix(9)) + "…"
    }
}
```

Implementation details:

- `orderedProjects(from:)` emits active projects sorted by `orderIndex`, then recursively traverses root `ArchiveFolder` instances sorted by `orderIndex` and folder projects sorted by `orderIndex`.
- Archived projects not attached to a folder are appended deterministically by `orderIndex`.
- `results(in:matching:)` emits matching milestones, then matching subtasks within each milestone, then memos sorted by `orderIndex` and `createdAt`.
- Every path prepends `"归档 / "` when `project.isArchived` is true.

- [ ] **Step 4: Reserve the GREEN test command for authorized verification**

If compilation is later authorized, run the same `xcodebuild test` command and expect all `GlobalSearchTests` cases to pass. Do not run it during this session under the current instruction.

### Task 2: Search Overlay UI And Toolbar Placement

**Files:**
- Create: `Viabar/Views/Component/GlobalSearchOverlay.swift`
- Modify: `Viabar/ContentView.swift:8-340`

- [ ] **Step 1: Add root-owned ephemeral search state**

In `ContentView`, add:

```swift
@State private var isGlobalSearchPresented = false
@State private var globalSearchQuery = ""
@State private var highlightedSearchResultID: String?
@State private var navigationRequest: GlobalSearchNavigationRequest?
```

Add a derived result list:

```swift
private var globalSearchResults: [GlobalSearchResult] {
    GlobalSearchIndex.results(matching: globalSearchQuery, projects: allProjects)
}
```

- [ ] **Step 2: Build a focused overlay component**

Create a `GlobalSearchOverlay` with explicit inputs:

```swift
struct GlobalSearchOverlay: View {
    @Binding var isPresented: Bool
    @Binding var query: String
    @Binding var highlightedResultID: String?
    let results: [GlobalSearchResult]
    let availableWidth: CGFloat
    let iconSize: CGFloat
    let buttonSize: CGFloat
    let onSelect: (GlobalSearchResult) -> Void
}
```

Its behavior must be:

- Collapsed state is a circular search button using `.font(.system(size: iconSize, weight: .medium))` and `buttonSize`, matching existing top icons.
- Presented empty state is a capsule text field extending left from its trailing anchor.
- Presented non-empty state wraps the field and a `ScrollView` list in a rounded panel; cap the result list frame at `8 * 54` points.
- `@FocusState` places focus in the text field on expansion.
- `.onKeyPress(.upArrow)`, `.downArrow`, `.return`, and `.escape` mutate/highlight/activate/dismiss without writing domain data.
- Each row shows `Image(systemName: result.project.sfSymbolName)`, `result.text`, and `result.path`; selected or hovered rows use `ViabarColor.primary` and white text.

- [ ] **Step 3: Replace project-only toolbar branching with a persistent detail toolbar**

Change `ContentView` so the top toolbar layer is rendered whether `selection` is `.overview` or `.project`. The toolbar row should:

- Render `GlobalSearchOverlay` at the trailing edge on overview pages.
- Render `GlobalSearchOverlay`, then `hideCompletedButton(project:)` on project pages.
- Preserve the memo drawer right-hand reservation only while a project with the memo drawer is visible.
- Compute the overlay max width with `GeometryReader`, using a larger value when `splitVisibility == .detailOnly` while leaving the collapsed-sidebar title unobscured.

Add `.case globalSearch` to `ToolbarButtonKind` only if the collapsed search button uses the existing hover background helper; keep the overlay itself responsible for expanded styling.

### Task 3: Route Search Results Into Projects And Archived Sidebar Paths

**Files:**
- Modify: `Viabar/ContentView.swift:34-155`
- Modify: `Viabar/Views/Sidebar/SidebarView.swift:95-466`

- [ ] **Step 1: Pass a reveal request into the sidebar**

Update construction and input:

```swift
SidebarView(
    selection: $selection,
    revealRequest: navigationRequest
)

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    let revealRequest: GlobalSearchNavigationRequest?
}
```

React on appearance and changes:

```swift
.onChange(of: revealRequest?.id) { _, _ in
    revealArchivedProject(revealRequest?.projectID)
}
```

- [ ] **Step 2: Expand the full archive path without mutating the project**

Add a helper in `SidebarView`:

```swift
private func revealArchivedProject(_ projectID: UUID?) {
    guard let projectID,
          let project = allProjects.first(where: { $0.projectId == projectID && $0.isArchived }),
          let folder = project.archiveFolder
    else { return }

    isArchiveExpanded = true
    var current: ArchiveFolder? = folder
    while let folder = current {
        expandedFolderIds.insert(folder.folderId)
        current = folder.parent
    }
}
```

This function only changes sidebar expansion state; it never calls `unarchiveProject`.

- [ ] **Step 3: Route selection from a search result**

Add in `ContentView`:

```swift
private func openSearchResult(_ result: GlobalSearchResult) {
    navigationRequest = GlobalSearchNavigationRequest(
        projectID: result.project.projectId,
        destination: result.destination
    )
    selection = .project(result.project)
    if case .memo = result.destination {
        resetMemoSearch()
        isMemoDrawerVisible = true
    }
    dismissGlobalSearch()
}
```

`dismissGlobalSearch()` clears input and highlight but leaves `navigationRequest` alive while the matching project remains selected. Add an `onChange` for the selected project's ID that assigns `navigationRequest = nil` whenever the user leaves `navigationRequest.projectID`; this removes temporary visibility when leaving the destination project. A new result selection creates a fresh request ID, so choosing the same result twice still retriggers sidebar reveal and scrolling.

```swift
.onChange(of: selectedProject?.projectId) { _, projectID in
    guard let navigationRequest, projectID != navigationRequest.projectID else { return }
    self.navigationRequest = nil
}
```

### Task 4: Locate Tasks And Temporarily Reveal Completed Matches

**Files:**
- Modify: `Viabar/Views/MainPanel/MainSplitView.swift:8-17`
- Modify: `Viabar/Views/MainPanel/MilestoneListView.swift:16-523`

- [ ] **Step 1: Thread task destinations into the milestone panel**

Extend the view boundary:

```swift
struct MainSplitView: View {
    let project: Project
    let navigationRequest: GlobalSearchNavigationRequest?
}

MilestoneListView(
    project: project,
    showsHeader: false,
    navigationRequest: navigationRequest
)
```

- [ ] **Step 2: Include a hidden target only while it is the current destination**

Extend `MilestoneListView`:

```swift
let navigationRequest: GlobalSearchNavigationRequest?

private var targetedMilestoneID: UUID? {
    guard navigationRequest?.projectID == project.projectId else { return nil }
    switch navigationRequest?.destination {
    case let .some(.milestone(id)):
        return id
    case let .some(.subTask(milestoneID, _)):
        return milestoneID
    default:
        return nil
    }
}

private var targetedSubTaskID: UUID? {
    guard navigationRequest?.projectID == project.projectId,
          case let .some(.subTask(_, subTaskID)) = navigationRequest?.destination
    else { return nil }
    return subTaskID
}

private var scrollTargetID: UUID? {
    targetedSubTaskID ?? targetedMilestoneID
}
```

Only return target IDs when `navigationRequest?.projectID == project.projectId`; this prevents a request from affecting any other selected project.

Update filtering rules:

```swift
return sorted.filter { milestone in
    milestone.milestoneId == targetedMilestoneID
        || !milestone.isCompleted
        || milestone.subtasks.contains(where: { !$0.isCompleted || $0.taskId == targetedSubTaskID })
}
```

When filtering subtasks, include `$0.taskId == targetedSubTaskID` even if it is completed. Never assign to `project.hideCompleted` and never call `updateProject` for navigation.

- [ ] **Step 3: Make rows scrollable and consume task navigation changes**

Pass a target anchor plus `navigationRequest?.id` to `SafeMilestoneListView`, apply stable row IDs:

```swift
SafeMilestoneRowView(...)
    .id(snapshot.id)

SafeSubTaskRowView(...)
    .id(subtask.id)
```

Inside its `ScrollViewReader`, observe the anchor:

```swift
.onChange(of: navigationRequestID) { _, _ in
    guard let id = scrollTargetID else { return }
    withAnimation(.easeInOut(duration: 0.18)) {
        proxy.scrollTo(id, anchor: .center)
    }
}
```

### Task 5: Locate Memo Matches In The Drawer

**Files:**
- Modify: `Viabar/ContentView.swift:136-221`
- Modify: `Viabar/Views/MainPanel/MemoTimelineView.swift:9-244`

- [ ] **Step 1: Forward memo target state from the root**

Pass `navigationRequest` through `memoDrawer(project:)`:

```swift
MemoTimelineView(
    project: project,
    searchDraft: $memoSearchDraft,
    activeSearchQuery: $activeMemoSearchQuery,
    navigationRequest: navigationRequest
)
```

- [ ] **Step 2: Scroll an opened memo into view**

Add:

```swift
let navigationRequest: GlobalSearchNavigationRequest?

private var targetedMemoID: UUID? {
    guard navigationRequest?.projectID == project.projectId,
          case let .some(.memo(id)) = navigationRequest?.destination
    else { return nil }
    return id
}
```

In the existing `ScrollViewReader`, replace unconditional initial bottom scrolling when a target exists and observe the memo ID:

```swift
.onAppear {
    if let targetedMemoID {
        scrollToMemo(targetedMemoID, proxy: proxy)
    } else {
        scrollToBottom(proxy)
    }
}
.onChange(of: navigationRequest?.id) { _, _ in
    guard let targetedMemoID else { return }
    scrollToMemo(targetedMemoID, proxy: proxy)
}
```

Use `proxy.scrollTo(id, anchor: .center)` in `scrollToMemo`. The root clears the memo-specific local filter before opening so the selected card is visible.

### Task 6: Static Validation And Deferred Runtime Verification

**Files:**
- Inspect: all files changed in Tasks 1-5

- [ ] **Step 1: Run non-compiling consistency checks**

Run:

```bash
git diff --check
rg -n "GlobalSearch|navigationRequest|revealArchivedProject|hideCompleted|scrollToMemo|scrollTargetID" Viabar ViabarTests
git diff --stat
```

Expected: no whitespace errors; every threaded state appears at its intended producer and consumer; changes are limited to search, routing, and tests.

- [ ] **Step 2: Document the deferred compile-based verification**

Do not run `xcodebuild` during this session unless the user expressly authorizes compiling. Report that the test suite and UI build are pending that authorization:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS'
```

Expected once authorized: build succeeds and `GlobalSearchTests` pass.
