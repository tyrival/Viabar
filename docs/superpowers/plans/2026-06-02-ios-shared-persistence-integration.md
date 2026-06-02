# iOS Shared Persistence Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-memory iOS interaction prototype with real SwiftData-backed screens while keeping macOS App, macOS Widget, iOS App, and iOS Widget on one shared schema contract and one App Group identifier.

**Architecture:** Keep `SharedModelContainer.schema` unchanged and reuse the existing `ProjectService`, `NotificationScheduleService`, `TrashService`, `GlobalSearchIndex`, and Widget refresh path. Add an iOS-only UI coordinator that owns navigation and presentation state but never copies business entities. Build persistent iOS views beside the static prototype first, then switch `ContentView` to the persistent root after static contracts pass.

**Tech Stack:** SwiftUI, SwiftData, Observation, WidgetKit, UserNotifications, UIKit/AppKit conditional compilation, shell static checks.

---

## File Structure

### Shared files modified

- `Viabar/System/SharedModelContainer.swift`
  - Use one App Group identifier for all targets.
- `Viabar/Services/TrashService.swift`
  - Keep shared trash behavior but use platform-specific pasteboard imports.
- `Viabar.xcodeproj/project.pbxproj`
  - Add existing shared model and service files to the iOS App target only.

### iOS files modified

- `ViabariOS/ViabariOS.entitlements`
  - Replace the temporary iOS App Group.
- `ViabariOSWidget/ViabariOSWidget.entitlements`
  - Replace the temporary iOS Widget App Group.
- `ViabariOS/ViabariOSApp.swift`
  - Register real main-store, trash-store, and service dependencies.
- `ViabariOS/ContentView.swift`
  - Present the persistent root.
- `ViabariOS/Prototype/IOSPrototypeComponents.swift`
  - Keep approved shared iOS visual components; make highlight consumption callback-based so persistent views can reuse them.

### iOS files created

- `ViabariOS/Persistence/IOSPersistenceCoordinator.swift`
  - Own UI-only home/detail tabs, search state, archive expansion, and one-shot highlight consumption.
- `ViabariOS/Persistence/IOSPersistentRootView.swift`
  - Own `@Query` collections, navigation stack, Widget URLs, and home/detail routing.
- `ViabariOS/Persistence/IOSPersistentOverviewView.swift`
  - Render real overview cards and global search.
- `ViabariOS/Persistence/IOSPersistentProjectDetailView.swift`
  - Render and mutate real milestones, subtasks, and memos.
- `ViabariOS/Persistence/IOSPersistentArchiveView.swift`
  - Render and mutate the real lazy archive tree.

### Static checks modified or created

- `scripts/tests/test_ios_foundation_static.sh`
  - Require the unified App Group.
- `scripts/tests/test_ios_persistence_static.sh`
  - Guard the persistence integration and prohibit a second SwiftData schema.

## Task 1: Add Persistence Static Contracts

**Files:**
- Modify: `scripts/tests/test_ios_foundation_static.sh`
- Create: `scripts/tests/test_ios_persistence_static.sh`

- [ ] **Step 1: Replace the temporary App Group assertions**

In `scripts/tests/test_ios_foundation_static.sh`, require `group.com.tyrival.Viabar` in both iOS entitlements and prohibit `group.com.tyrival.ViabariOS`:

```bash
for entitlements in "$IOS_ENTITLEMENTS" "$IOS_WIDGET_ENTITLEMENTS"; do
    rg -q 'group\.com\.tyrival\.Viabar' "$entitlements" ||
        fail "$entitlements must declare the shared Viabar App Group"
done

if rg -q 'group\.com\.tyrival\.ViabariOS' \
    "$SHARED_CONTAINER" "$IOS_ENTITLEMENTS" "$IOS_WIDGET_ENTITLEMENTS"; then
    fail "temporary iOS-only App Group must not remain active"
fi

if rg -q '#if os\(iOS\)' "$SHARED_CONTAINER"; then
    fail "SharedModelContainer must not branch the App Group by platform"
fi
```

- [ ] **Step 2: Add a persistence integration static script**

Create `scripts/tests/test_ios_persistence_static.sh` with checks for:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ViabariOS"
SHARED_CONTAINER="$ROOT_DIR/Viabar/System/SharedModelContainer.swift"
IOS_APP="$IOS_DIR/ViabariOSApp.swift"
IOS_CONTENT="$IOS_DIR/ContentView.swift"
PROJECT_FILE="$ROOT_DIR/Viabar.xcodeproj/project.pbxproj"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

for file in \
    Persistence/IOSPersistenceCoordinator.swift \
    Persistence/IOSPersistentRootView.swift \
    Persistence/IOSPersistentOverviewView.swift \
    Persistence/IOSPersistentProjectDetailView.swift \
    Persistence/IOSPersistentArchiveView.swift; do
    [[ -f "$IOS_DIR/$file" ]] || fail "missing ViabariOS/$file"
done

rg -q 'static let appGroupIdentifier = "group\.com\.tyrival\.Viabar"' "$SHARED_CONTAINER" ||
    fail "shared App Group identifier must be unified"
rg -q 'SharedModelContainer\.makeTrashContainer\(\)' "$IOS_APP" ||
    fail "iOS app must open trash.store"
rg -q 'registerProjectService' "$IOS_APP" ||
    fail "iOS app must register ProjectService"
rg -q 'registerNotificationScheduleService' "$IOS_APP" ||
    fail "iOS app must register NotificationScheduleService"
rg -q 'registerTrashService' "$IOS_APP" ||
    fail "iOS app must register TrashService"
rg -q '\.environment\(serviceContainer\)' "$IOS_APP" ||
    fail "iOS app must inject ServiceContainer"
rg -q 'IOSPersistentRootView' "$IOS_CONTENT" ||
    fail "ContentView must present the persistent root"
rg -q '@Query\\(sort: \\\\Project\\.orderIndex\\)' "$IOS_DIR/Persistence/IOSPersistentRootView.swift" ||
    fail "persistent root must query real projects"
rg -q 'GlobalSearchIndex\\.results' "$IOS_DIR/Persistence/IOSPersistentOverviewView.swift" ||
    fail "iOS search must reuse GlobalSearchIndex"
rg -q 'SharedModelContainer\\.makeWidgetContainer' "$ROOT_DIR/ViabarWidget" --glob '*.swift' ||
    fail "Widget must continue to open the shared main store"

if rg -q '@Model|Schema\\(' "$IOS_DIR/Persistence" --glob '*.swift'; then
    fail "iOS persistence UI must not define a parallel schema"
fi

for source in \
    Viabar/Models/TrashItem.swift \
    Viabar/Models/BackupSnapshot.swift \
    Viabar/Models/GlobalSearch.swift \
    Viabar/System/TrashModelContainer.swift \
    Viabar/Services/SyncService.swift \
    Viabar/Services/NotificationScheduleService.swift \
    Viabar/Services/TrashService.swift \
    Viabar/Services/ProjectService.swift; do
    rg -q "$source in Sources" "$PROJECT_FILE" ||
        fail "iOS app target must include $source"
done

printf 'PASS: iOS persistence static checks\n'
```

- [ ] **Step 3: Run the new checks and verify they fail**

Run:

```bash
bash scripts/tests/test_ios_foundation_static.sh
bash scripts/tests/test_ios_persistence_static.sh
```

Expected: both fail because the temporary App Group and persistent root still remain.

## Task 2: Unify the App Group Without Moving Data

**Files:**
- Modify: `Viabar/System/SharedModelContainer.swift`
- Modify: `ViabariOS/ViabariOS.entitlements`
- Modify: `ViabariOSWidget/ViabariOSWidget.entitlements`

- [ ] **Step 1: Replace the platform branch**

Use one constant:

```swift
enum SharedModelContainer {
    static let appGroupIdentifier = "group.com.tyrival.Viabar"
```

Do not change `schema`, `sharedStoreURL`, `makeMainAppContainer()`, `makeIOSAppContainer()`, or `makeWidgetContainer()`.

- [ ] **Step 2: Update both iOS entitlements**

Set the only App Group entry to:

```xml
<string>group.com.tyrival.Viabar</string>
```

Do not add iCloud or CloudKit entitlements.

- [ ] **Step 3: Run foundation checks**

Run:

```bash
bash scripts/tests/test_ios_foundation_static.sh
plutil -lint ViabariOS/ViabariOS.entitlements ViabariOSWidget/ViabariOSWidget.entitlements
```

Expected: PASS.

## Task 3: Make Shared Services iOS-Compatible

**Files:**
- Modify: `Viabar/Services/TrashService.swift`
- Modify: `Viabar.xcodeproj/project.pbxproj`

- [ ] **Step 1: Make pasteboard use platform-specific**

At the top of `Viabar/Services/TrashService.swift`, replace the unconditional AppKit import:

```swift
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import Observation
import SwiftData
```

Replace `copyToPasteboard(_:)` with:

```swift
func copyToPasteboard(_ item: TrashItem) throws {
    let text = try item.copyText()
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
#elseif os(iOS)
    UIPasteboard.general.string = text
#endif
}
```

- [ ] **Step 2: Add existing shared files to the iOS App source phase**

In `Viabar.xcodeproj/project.pbxproj`, add PBX file references, PBX build files, and entries in iOS App sources `C3AE2DED2FCE63B900528C34` for:

```text
Viabar/Models/TaskCompletionMutation.swift
Viabar/Models/BackupSnapshot.swift
Viabar/Models/TrashItem.swift
Viabar/Models/GlobalSearch.swift
Viabar/System/TrashModelContainer.swift
Viabar/Services/SyncService.swift
Viabar/Services/NotificationScheduleService.swift
Viabar/Services/TrashService.swift
Viabar/Services/ProjectService.swift
```

Reuse the existing repository files. Do not copy them under `ViabariOS/`.

- [ ] **Step 3: Validate project-file syntax**

Run:

```bash
plutil -lint Viabar.xcodeproj/project.pbxproj
git diff --check -- Viabar.xcodeproj/project.pbxproj Viabar/Services/TrashService.swift
```

Expected: PASS.

## Task 4: Register the iOS Main Store, Trash Store, and Services

**Files:**
- Modify: `ViabariOS/ViabariOSApp.swift`

- [ ] **Step 1: Add stored dependencies**

Add:

```swift
@State private var serviceContainer: ServiceContainer
private let trashModelContainer: ModelContainer
```

- [ ] **Step 2: Register shared services in `init()`**

After opening the main store, open `trash.store`, then register services:

```swift
sharedModelContainer = try SharedModelContainer.makeIOSAppContainer()
trashModelContainer = try SharedModelContainer.makeTrashContainer()

_ = AppSettingsStore.ensureDefaultSettings(in: sharedModelContainer.mainContext)

let container = ServiceContainer()
_ = container.registerProjectService(modelContext: sharedModelContainer.mainContext)
let notificationScheduleService = container.registerNotificationScheduleService(
    modelContext: sharedModelContainer.mainContext
)
notificationScheduleService.start()
let trashService = container.registerTrashService(
    modelContext: trashModelContainer.mainContext,
    projectModelContext: sharedModelContainer.mainContext,
    notificationScheduleService: notificationScheduleService
)
try? trashService.cleanupExpired(policy: TrashRetentionSettingsStore.policy())
_serviceContainer = State(initialValue: container)
```

Do not register macOS-only update, backup, menu bar, Sparkle, or AppKit window services.

- [ ] **Step 3: Inject the service container**

In `WindowGroup`:

```swift
ContentView()
    .environment(serviceContainer)
```

- [ ] **Step 4: Run the persistence script**

Run:

```bash
bash scripts/tests/test_ios_persistence_static.sh
```

Expected: still FAIL because persistent UI files do not exist yet, while service registration assertions pass.

## Task 5: Add the UI-Only Persistence Coordinator

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistenceCoordinator.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeComponents.swift`

- [ ] **Step 1: Add the coordinator**

Create an `@Observable @MainActor` coordinator that stores only presentation state:

```swift
@MainActor
@Observable
final class IOSPersistenceCoordinator {
    var homeTab: IOSPrototypeHomeTab = .overview
    var detailTab: IOSPrototypeDetailTab = .tasks
    var searchText = ""
    var isSearchPresented = false
    var navigationRequest: GlobalSearchNavigationRequest?
    var expandedArchiveFolderIDs: Set<UUID> = []

    private var consumedHighlightRequestIDs: Set<UUID> = []

    func consumeHighlight(_ requestID: UUID?) -> Bool {
        guard let requestID else { return false }
        return consumedHighlightRequestIDs.insert(requestID).inserted
    }
}
```

Do not store copied projects, copied tasks, or copied memos.

- [ ] **Step 2: Generalize the approved outline modifier**

Change `IOSPrototypeSearchOutlineHighlight` to accept:

```swift
let consume: (UUID?) -> Bool
```

The `.task(id:)` guard becomes:

```swift
guard consume(triggerID) else {
    opacity = 0
    return
}
```

Keep a convenience overload for `IOSPrototypeStore` so the static prototype continues to compile, and add another overload usable by persistent views.

- [ ] **Step 3: Run static prototype checks**

Run:

```bash
bash scripts/tests/test_ios_static_prototype.sh
git diff --check -- ViabariOS
```

Expected: PASS.

## Task 6: Add the Persistent Root and Overview

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistentRootView.swift`
- Create: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`
- Modify: `ViabariOS/ContentView.swift`

- [ ] **Step 1: Query real projects and folders at the root**

`IOSPersistentRootView` owns:

```swift
@Query(sort: \Project.orderIndex) private var projects: [Project]
@Query(sort: \ArchiveFolder.orderIndex) private var archiveFolders: [ArchiveFolder]
@State private var coordinator = IOSPersistenceCoordinator()
```

Use `NavigationStack`, route project IDs, and consume Widget URLs:

```swift
.onOpenURL { url in
    guard let request = WidgetNavigationURL.navigationRequest(from: url) else { return }
    coordinator.navigate(to: request)
}
```

- [ ] **Step 2: Add coordinator navigation helpers**

Support both global-search and Widget requests:

```swift
func navigate(to result: GlobalSearchResult)
func navigate(to request: GlobalSearchNavigationRequest)
func revealArchiveAncestors(for project: Project)
```

The coordinator receives real `Project` or folder IDs only for routing; it never owns model copies.

- [ ] **Step 3: Build overview sections from real projects**

Filter:

```swift
let active = projects.filter { !$0.isArchived }
let favorites = active.filter(\.isFavorite)
let regular = active.filter { !$0.isFavorite }
```

Use `Project.projectId`, `Project.sfSymbolName`, `Project.accentColor`, `Project.progress`, `Project.unfinishedMilestones`, and real reminders.

- [ ] **Step 4: Route card mutations through `ProjectService`**

Use:

```swift
projectService.toggleFavorite(project)
projectService.updateProject(project)
projectService.archiveProject(project, to: folder)
projectService.deleteProject(project)
```

Keep the current two-step project delete confirmation. Do not send projects to `TrashService` in this phase.

- [ ] **Step 5: Reuse `GlobalSearchIndex`**

Search results must call:

```swift
GlobalSearchIndex.results(matching: coordinator.searchText, projects: projects)
```

Keep the approved search panel styling and navigate through coordinator helpers.

- [ ] **Step 6: Switch `ContentView`**

Replace:

```swift
IOSPrototypeRootView()
```

with:

```swift
IOSPersistentRootView()
```

## Task 7: Add Persistent Project Detail

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistentProjectDetailView.swift`

- [ ] **Step 1: Resolve the selected real project**

Pass `Project` into detail or resolve it from the root query by `projectId`. Use the existing bottom-composer session pattern with real UUID fields:

```text
Milestone.milestoneId
SubTask.taskId
Memo.memoId
```

- [ ] **Step 2: Route all writes through `ProjectService`**

Use:

```swift
projectService.addMilestone(to:title:)
projectService.addSubTask(to:title:)
projectService.addMemo(to:content:)
projectService.toggleMilestoneComplete(_:)
projectService.toggleSubTaskComplete(_:)
projectService.deleteMilestone(_:)
projectService.deleteSubTask(_:)
projectService.deleteMemo(_:)
projectService.toggleFavorite(_:)
```

For text edits, update the managed object's `title` or `content`, then call:

```swift
projectService.updateProject(project)
```

- [ ] **Step 3: Preserve one-shot search highlights**

Use `GlobalSearchNavigationRequest.destination` and:

```swift
coordinator.consumeHighlight(request.id)
```

Keep row-fill highlights for tasks and subtasks and outline highlights for memos.

- [ ] **Step 4: Preserve reminder colors**

Map:

```swift
reminder.displayFireDate.map(IOSPrototypeReminderStyle.color(for:))
```

for project, task, and subtask reminders.

## Task 8: Add the Persistent Archive Tree

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistentArchiveView.swift`

- [ ] **Step 1: Render root folders lazily**

Filter:

```swift
archiveFolders.filter { $0.parent == nil }
```

Render child nodes only when:

```swift
coordinator.expandedArchiveFolderIDs.contains(folder.folderId)
```

- [ ] **Step 2: Route folder mutations through `ProjectService`**

Use:

```swift
projectService.createArchiveFolder(name:parent:)
projectService.deleteArchiveFolder(_:)
folder.name = normalizedName
projectService.save()
```

- [ ] **Step 3: Preserve archive project interactions**

Use:

```swift
projectService.unarchiveProject(project)
projectService.deleteProject(project)
```

Keep the compact archive row and two-step delete confirmation.

- [ ] **Step 4: Reveal archived search destinations**

When navigation selects an archived project, insert each ancestor `folderId` into:

```swift
coordinator.expandedArchiveFolderIDs
```

## Task 9: Verify Widget-Safe Persistence Wiring

**Files:**
- Modify: `scripts/tests/test_ios_persistence_static.sh`
- Modify: `scripts/tests/test_ios_static_prototype.sh` only if generalized helpers require a static check update

- [ ] **Step 1: Run all static scripts**

Run:

```bash
bash scripts/tests/test_widget_static.sh
bash scripts/tests/test_ios_foundation_static.sh
bash scripts/tests/test_ios_static_prototype.sh
bash scripts/tests/test_ios_persistence_static.sh
```

Expected: PASS.

- [ ] **Step 2: Run repository static validation**

Run:

```bash
rg -n "@Model|Schema\\(|ModelContainer|ModelConfiguration" Viabar ViabarWidget ViabariOS ViabariOSWidget --glob '*.swift'
rg -n "legacyStoreURL|applicationSupportDirectory|default\\.store|trash\\.store|ViabarSharedStore|cloudKitDatabase" Viabar ViabarWidget ViabariOS ViabariOSWidget --glob '*.swift'
rg -n "group\\.com\\.tyrival\\.Viabar|group\\.com\\.tyrival\\.ViabariOS" Viabar ViabarWidget ViabariOS ViabariOSWidget --glob '*.swift' --glob '*.entitlements'
rg -n "BackupSnapshot|BackupSettingsSnapshot|decodeIfPresent|init\\(from decoder" Viabar ViabarTests --glob '*.swift'
git diff --check
plutil -lint Viabar.xcodeproj/project.pbxproj
plutil -lint Viabar/Viabar.entitlements ViabarWidget/ViabarWidget.entitlements
plutil -lint ViabariOS/ViabariOS.entitlements ViabariOSWidget/ViabariOSWidget.entitlements
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
```

Expected:

- No new `@Model`.
- `SharedModelContainer.schema` entity list unchanged.
- No active `group.com.tyrival.ViabariOS` reference outside historical docs.
- All `plutil` checks pass.
- `git diff --check` exits successfully.

- [ ] **Step 3: Do not compile unless the user asks**

Stop after static verification. Ask the user to run the iOS App and Widget in Xcode.

## Manual Acceptance Checklist

After implementation, ask the user to verify:

1. Run iOS App and confirm it opens real persisted projects.
2. Add or edit a task, subtask, and memo; relaunch and confirm persistence.
3. Toggle favorite; confirm overview grouping and star refresh.
4. Archive a project; confirm lazy archive tree display.
5. Search task, subtask, and memo; confirm navigation and one-shot highlight.
6. Add iOS Medium and Large Widgets and select a project.
7. Toggle a task in iOS App; confirm Widget refresh.
8. Toggle a task in Widget; reopen iOS App and confirm the state.
9. Run macOS App and macOS Widgets; confirm existing behavior remains intact.
