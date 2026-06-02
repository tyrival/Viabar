# iOS Static Interaction Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the iOS placeholder with an interactive, in-memory prototype for overview, task detail, memo detail, search, context menus, and multiline editing without writing to SwiftData.

**Architecture:** Keep all prototype-only state under `ViabariOS/Prototype/`. `IOSPrototypeStore` owns demo records and temporary mutations for the current launch. SwiftUI screens render that store and call narrow store methods so the later `ProjectService` integration can replace the adapter boundary without redesigning the views.

**Tech Stack:** SwiftUI, Observation, SF Symbols, iOS 17 APIs, shell static checks.

---

## File Map

- Create: `ViabariOS/Prototype/IOSPrototypeModels.swift`
  - Defines lightweight in-memory project, milestone, subtask, memo, search-result, and navigation types.
- Create: `ViabariOS/Prototype/IOSPrototypeStore.swift`
  - Owns demo data, navigation state, search state, and temporary mutations.
- Create: `ViabariOS/Prototype/IOSPrototypeComponents.swift`
  - Owns progress ring, floating bottom bars, section labels, and multiline editor.
- Create: `ViabariOS/Prototype/IOSPrototypeOverviewView.swift`
  - Owns overview grouping, project cards, search expansion, and placeholder tabs.
- Create: `ViabariOS/Prototype/IOSPrototypeProjectDetailView.swift`
  - Owns project header, task list, memo list, context menus, inline editing, and add input.
- Modify: `ViabariOS/ContentView.swift`
  - Replaces the placeholder with `IOSPrototypeRootView`.
- Create: `scripts/tests/test_ios_static_prototype.sh`
  - Locks the prototype boundary using static assertions.

The `ViabariOS/` synchronized root group already belongs to the iOS app target. New Swift files under that folder do not require manual `project.pbxproj` membership edits.

### Task 1: Add Static Prototype Boundary Checks

**Files:**
- Create: `scripts/tests/test_ios_static_prototype.sh`

- [ ] **Step 1: Write the failing static test**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROTOTYPE_DIR="$ROOT_DIR/ViabariOS/Prototype"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

for file in \
    IOSPrototypeModels.swift \
    IOSPrototypeStore.swift \
    IOSPrototypeComponents.swift \
    IOSPrototypeOverviewView.swift \
    IOSPrototypeProjectDetailView.swift; do
    [[ -f "$PROTOTYPE_DIR/$file" ]] || fail "missing ViabariOS/Prototype/$file"
done

if rg -q '@Model|ModelContext|ModelContainer|SwiftData' "$PROTOTYPE_DIR" --glob '*.swift'; then
    fail "iOS static prototype must not depend on SwiftData"
fi

rg -q 'final class IOSPrototypeStore' "$PROTOTYPE_DIR/IOSPrototypeStore.swift" ||
    fail "prototype store is missing"
rg -q 'struct IOSMultilineEditor' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "shared multiline editor is missing"
rg -q '\\.contextMenu' "$PROTOTYPE_DIR" --glob '*.swift' ||
    fail "prototype context menus are missing"
rg -q 'star\\.fill' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "favorite project cards must show star.fill"
rg -q 'IOSPrototypeRootView' "$ROOT_DIR/ViabariOS/ContentView.swift" ||
    fail "ContentView must present the prototype root"

printf 'PASS: iOS static prototype checks\n'
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x scripts/tests/test_ios_static_prototype.sh
```

- [ ] **Step 3: Run the test and verify it fails**

Run:

```bash
./scripts/tests/test_ios_static_prototype.sh
```

Expected: `FAIL: missing ViabariOS/Prototype/IOSPrototypeModels.swift`

### Task 2: Add In-Memory Prototype Models And Store

**Files:**
- Create: `ViabariOS/Prototype/IOSPrototypeModels.swift`
- Create: `ViabariOS/Prototype/IOSPrototypeStore.swift`

- [ ] **Step 1: Define lightweight prototype records**

Create value types with UUID identifiers:

```swift
import Foundation

struct IOSPrototypeProject: Identifiable {
    let id: UUID
    var title: String
    var accentHex: String
    var symbol: String
    var isFavorite: Bool
    var isArchived: Bool
    var reminderDate: Date?
    var milestones: [IOSPrototypeMilestone]
    var memos: [IOSPrototypeMemo]

    var progress: Double {
        guard !milestones.isEmpty else { return 0 }
        let total = milestones.reduce(0.0) { $0 + $1.score }
        return ((total / Double(milestones.count)) * 10000).rounded() / 10000
    }

    var topUnfinishedMilestone: IOSPrototypeMilestone? {
        milestones.sorted { $0.orderIndex < $1.orderIndex }
            .first { $0.score < 1 }
    }
}

struct IOSPrototypeMilestone: Identifiable {
    let id: UUID
    var title: String
    var orderIndex: Int
    var isCompleted: Bool
    var reminderDate: Date?
    var subtasks: [IOSPrototypeSubTask]
    var score: Double {
        guard !subtasks.isEmpty else { return isCompleted ? 1 : 0 }
        return Double(subtasks.filter(\.isCompleted).count) / Double(subtasks.count)
    }
}

struct IOSPrototypeSubTask: Identifiable {
    let id: UUID
    var title: String
    var orderIndex: Int
    var isCompleted: Bool
    var reminderDate: Date?
}

struct IOSPrototypeMemo: Identifiable {
    let id: UUID
    var content: String
    var createdAt: Date
}

enum IOSPrototypeHomeTab { case overview, reports, archive }
enum IOSPrototypeDetailTab { case tasks, memos }
enum IOSPrototypeSearchTarget { case project, milestone, subtask, memo }

struct IOSPrototypeSearchResult: Identifiable {
    let id: UUID
    let projectID: UUID
    let detailTab: IOSPrototypeDetailTab
    let target: IOSPrototypeSearchTarget
    let title: String
    let subtitle: String
}
```

- [ ] **Step 2: Add a single observable store**

Use an `@Observable` reference type:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class IOSPrototypeStore {
    var projects: [IOSPrototypeProject] = Self.demoProjects()
    var homeTab: IOSPrototypeHomeTab = .overview
    var selectedProjectID: UUID?
    var detailTab: IOSPrototypeDetailTab = .tasks
    var isSearchPresented = false
    var searchText = ""

    var favoriteProjects: [IOSPrototypeProject] {
        projects.filter { $0.isFavorite && !$0.isArchived }
    }

    var regularProjects: [IOSPrototypeProject] {
        projects.filter { !$0.isFavorite && !$0.isArchived }
    }

    var searchResults: [IOSPrototypeSearchResult] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return matchingProjects() + matchingMilestones() + matchingSubtasks() + matchingMemos()
    }

    func selectProject(_ id: UUID, detailTab: IOSPrototypeDetailTab = .tasks)
    func toggleFavorite(_ projectID: UUID)
    func archive(_ projectID: UUID)
    func deleteProject(_ projectID: UUID)
    func toggleMilestone(_ milestoneID: UUID, in projectID: UUID)
    func toggleSubtask(_ subtaskID: UUID, milestoneID: UUID, in projectID: UUID)
    func renameMilestone(_ milestoneID: UUID, in projectID: UUID, title: String)
    func renameSubtask(_ subtaskID: UUID, milestoneID: UUID, in projectID: UUID, title: String)
    func renameMemo(_ memoID: UUID, in projectID: UUID, content: String)
    func addMilestone(to projectID: UUID, title: String)
    func addMemo(to projectID: UUID, content: String)
    func deleteMilestone(_ milestoneID: UUID, in projectID: UUID)
    func deleteSubtask(_ subtaskID: UUID, milestoneID: UUID, in projectID: UUID)
    func deleteMemo(_ memoID: UUID, in projectID: UUID)
}
```

Implement each mutation by locating the nested array index, mutating the value record in place, and writing the updated record back into `projects`. Every rename and add method must trim `.whitespacesAndNewlines`; blank submissions return without mutation. `toggleSubtask` must recompute its parent milestone's `isCompleted` from all child states. Search helper methods must perform localized case-insensitive matching and return the correct detail Tab.

- [ ] **Step 3: Seed realistic demo content**

Add at least:

- Two favorite active projects and one regular active project.
- One completed project so the 100% state is visible.
- A task tree containing both leaf milestones and milestones with subtasks.
- Project, milestone, and subtask reminders.
- Three multi-line memos.

Keep demo construction in `private static func demoProjects() -> [IOSPrototypeProject]`.

- [ ] **Step 4: Run static checks**

Run:

```bash
./scripts/tests/test_ios_static_prototype.sh
```

Expected: fails on the next missing view component, proving models and store have been added without SwiftData.

### Task 3: Add Shared iOS Prototype Components

**Files:**
- Create: `ViabariOS/Prototype/IOSPrototypeComponents.swift`

- [ ] **Step 1: Add progress and section-label components**

Implement:

```swift
struct IOSPrototypeProgressRing: View {
    let progress: Double
    let tint: Color
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 36, height: 36)
    }
}

struct IOSPrototypeSectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: Add the multiline editor**

Implement a reusable `TextEditor` wrapper:

```swift
struct IOSMultilineEditor: View {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .focused($isFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成", action: onCommit)
                }
            }
    }
}
```

Do not intercept `Return`; `TextEditor` must preserve newline entry. Parent views commit when focus moves outside or the toolbar button is tapped.

- [ ] **Step 3: Add floating navigation components**

Create compact capsule-shaped bottom bars for:

- Home: overview, reports, archive.
- Detail: tasks, memos.
- Detached circular action button: search or add.

Use iOS 17 materials (`.ultraThinMaterial`) and SF Symbols. Do not use iOS 26-only glass APIs.

### Task 4: Build The Overview And Search Flow

**Files:**
- Create: `ViabariOS/Prototype/IOSPrototypeOverviewView.swift`

- [ ] **Step 1: Add the prototype root**

Implement `IOSPrototypeRootView` with:

```swift
@State private var store = IOSPrototypeStore()

var body: some View {
    NavigationStack {
        IOSPrototypeHomeView(store: store)
            .navigationDestination(for: UUID.self) { projectID in
                IOSPrototypeProjectDetailView(store: store, projectID: projectID)
            }
    }
}
```

- [ ] **Step 2: Add the overview grouping**

Render:

- Settings gear placeholder in the top-left.
- Compact `IOSPrototypeSectionLabel(title: "星标项目")`.
- Favorite cards.
- Compact `IOSPrototypeSectionLabel(title: "其他项目")`.
- Regular cards.
- Floating home tab capsule and detached search button.

- [ ] **Step 3: Add project cards**

Each `IOSOverviewProjectCard` must render:

- Accent-colored leading line.
- Project symbol and title.
- `star.fill` in the top-right when favorite.
- Top unfinished milestone and first unfinished subtask.
- Reminder timestamp.
- Progress percentage and ring.
- `.contextMenu` with edit, archive, favorite toggle, and delete. Edit switches the project title into an inline `IOSMultilineEditor`.
- Tap navigation into project detail.

- [ ] **Step 4: Add expanded global search**

When the detached search button is tapped:

- Show an animated search field above the bottom bar.
- Render results from `store.searchResults`.
- Navigate project, task, subtask, and memo results to the matching project.
- Set detail Tab to `.tasks` or `.memos` before navigation.
- Dismiss search when tapping outside the search surface.

- [ ] **Step 5: Add reports and archive placeholders**

Create `IOSPlaceholderView` and render it for `.reports` and `.archive`.

### Task 5: Build Project Detail Tasks And Memos

**Files:**
- Create: `ViabariOS/Prototype/IOSPrototypeProjectDetailView.swift`

- [ ] **Step 1: Add the detail shell**

Render:

- Native back navigation.
- Project symbol and title.
- Top-right ellipsis menu.
- Progress ring and percentage.
- Project reminder timestamp.
- Detail bottom capsule for tasks and memos.
- Detached add button.

- [ ] **Step 2: Add task rows**

Render milestones and nested subtasks with:

- Completion circle buttons.
- Reminder timestamp and alarm icon.
- Child indentation.
- Inline editor when title is tapped.
- `.contextMenu` with edit and delete actions.

Use `IOSMultilineEditor` for both milestone and subtask editing. Commit on toolbar “完成” or focus loss.

- [ ] **Step 3: Add memo cards**

Render memo cards with:

- Timestamp.
- Multi-line content.
- Inline editor when tapped.
- `.contextMenu` with edit and delete actions.

Use `IOSMultilineEditor` and commit on toolbar “完成” or focus loss.

- [ ] **Step 4: Add temporary creation**

When the detached add button is tapped:

- Tasks Tab: show a multiline input for a new milestone.
- Memos Tab: show a multiline input for a new memo.
- Commit valid trimmed text on toolbar “完成” or focus loss.
- Ignore blank submissions.

### Task 6: Replace The iOS Placeholder

**Files:**
- Modify: `ViabariOS/ContentView.swift`

- [ ] **Step 1: Present the prototype root**

Replace the placeholder body with:

```swift
struct ContentView: View {
    var body: some View {
        IOSPrototypeRootView()
    }
}
```

Keep the `.onOpenURL` routing point inside `IOSPrototypeRootView` as a no-op placeholder for the later real navigation adapter.

- [ ] **Step 2: Run the prototype static check**

Run:

```bash
./scripts/tests/test_ios_static_prototype.sh
```

Expected:

```text
PASS: iOS static prototype checks
```

### Task 7: Run Static Verification

**Files:**
- Verify only.

- [ ] **Step 1: Run iOS prototype and foundation static checks**

Run:

```bash
./scripts/tests/test_ios_static_prototype.sh
./scripts/tests/test_ios_foundation_static.sh
bash scripts/tests/test_widget_static.sh
```

Expected:

```text
PASS: iOS static prototype checks
PASS: iOS foundation static checks
PASS: Widget static checks
```

- [ ] **Step 2: Lint plist and project files**

Run:

```bash
plutil -lint \
    ViabariOS/Info.plist \
    ViabariOSWidget/Info.plist \
    ViabarWidget/Info.plist \
    Viabar.xcodeproj/project.pbxproj
```

Expected: all files report `OK`.

- [ ] **Step 3: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 4: Hand off manual Xcode verification**

Ask the user to run the iOS app and verify the fourteen manual cases listed in:

```text
docs/superpowers/specs/2026-06-02-ios-static-interaction-prototype-design.md
```

Do not compile or run the simulator unless the user explicitly requests it.
