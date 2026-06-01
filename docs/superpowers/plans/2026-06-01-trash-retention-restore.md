# Trash Retention And Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a searchable, restorable trash for deleted tasks, subtasks, and memos; configurable startup retention cleanup; backup and restore support; sidebar hover polish; and two-step permanent project deletion.

**Architecture:** Persist deleted content as independent versioned `TrashItem` snapshots so active project progress, widgets, reminders, and search remain free of soft-delete filtering. Add a focused `TrashService` for snapshot creation, filtering, copying, restore validation, restoration, and retention cleanup. Keep `ProjectService` as the deletion boundary, use a dedicated trash browser sheet for UI, and reuse one project-deletion confirmation modifier in both sidebar and overview surfaces.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Observation, Foundation `Codable`, AppKit `NSPasteboard`, Swift Testing.

**Repository constraint:** Do not compile or run test targets unless the user explicitly authorizes it. Every task therefore includes static verification as the default gate and marks executable test commands as optional authorization-only follow-ups.

---

## File Map

**Create**

- `Viabar/Models/TrashItem.swift`: persisted trash model, versioned payloads, retention policy, search result formatting, copy text, and restore availability.
- `Viabar/Services/TrashService.swift`: snapshot capture, restoration, cleanup, ordering normalization, and `ServiceContainer` registration.
- `Viabar/Views/Component/TrashBrowserView.swift`: wide trash browser sheet with search, deletion timestamps, context menu, copy, restore, and disabled explanations.
- `Viabar/Views/Component/PermanentProjectDeletionModifier.swift`: shared two-step confirmation flow for project deletion.

**Modify**

- `Viabar/Services/ProjectService.swift`: require `TrashService` for task, subtask, and memo deletions.
- `Viabar/System/SharedModelContainer.swift`: include `TrashItem` in the shared SwiftData schema.
- `Viabar/Models/AppSettings.swift`: store and backfill the selected trash-retention policy.
- `Viabar/ViabarApp.swift`: register `TrashService` and run cleanup once at startup.
- `Viabar/Models/BackupSnapshot.swift`: include retention settings and backward-compatible trash snapshots.
- `Viabar/Services/BackupService.swift`: capture, replace, restore, and immediately clean restored trash.
- `Viabar/Views/Settings/SettingsView.swift`: add the trash-retention settings group.
- `Viabar/Views/Sidebar/SidebarView.swift`: add bottom trash entry, browser sheet, shared hover polish, and shared project deletion modifier.
- `Viabar/ContentView.swift`: replace overview-card project deletion alert with the shared two-step modifier.
- `Viabar/en.lproj/Localizable.strings`: English copy.
- `Viabar/zh-Hans.lproj/Localizable.strings`: Simplified Chinese copy.
- `ViabarTests/ViabarTests.swift`: focused model, service, retention, backup, and restore tests.

**Xcode project note:** `Viabar.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` for `Viabar`, so newly created Swift files under `Viabar/` should be discovered automatically. Do not edit `project.pbxproj` unless a static check proves the files are not included.

---

### Task 1: Add The Trash Snapshot Domain Model

**Files:**
- Create: `Viabar/Models/TrashItem.swift`
- Modify: `Viabar/System/SharedModelContainer.swift:21-34`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Write focused trash-model tests**

Append tests that define the required payload, search, sorting, copy, and retention behavior:

```swift
struct TrashItemModelTests {
    @Test func taskPayloadCopiesNestedSubtasksAsHierarchy() throws {
        let payload = TrashPayload.task(
            TrashTaskSnapshot(
                title: "发布准备",
                isCompleted: false,
                completedAt: nil,
                reminder: nil,
                subtasks: [
                    TrashSubTaskSnapshot(title: "打包", isCompleted: false, completedAt: nil, orderIndex: 0, reminder: nil),
                    TrashSubTaskSnapshot(title: "上传", isCompleted: true, completedAt: Date(timeIntervalSince1970: 10), orderIndex: 1, reminder: nil),
                ]
            )
        )
        let item = try TrashItem.fixture(projectTitle: "Viabar", payload: payload)

        #expect(try item.copyText() == "发布准备\n- 打包\n- 上传")
        #expect(try item.matches("viabar"))
        #expect(try item.matches("上传"))
    }

    @Test func newestTrashItemsSortFirst() throws {
        let older = try TrashItem.fixture(deletedAt: Date(timeIntervalSince1970: 10), payload: .memo(.init(content: "旧", createdAt: .distantPast)))
        let newer = try TrashItem.fixture(deletedAt: Date(timeIntervalSince1970: 20), payload: .memo(.init(content: "新", createdAt: .distantPast)))

        #expect(TrashItemIndex.sortedNewestFirst([older, newer]).map(\.trashItemId) == [newer.trashItemId, older.trashItemId])
    }

    @Test func retentionDeletesExpiredItemsUnlessPolicyIsForever() throws {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let recent = try TrashItem.fixture(deletedAt: now.addingTimeInterval(-29 * 86_400))
        let expired = try TrashItem.fixture(deletedAt: now.addingTimeInterval(-31 * 86_400))

        #expect(TrashRetentionPolicy.thirtyDays.expiredItems(from: [recent, expired], now: now).map(\.trashItemId) == [expired.trashItemId])
        #expect(TrashRetentionPolicy.forever.expiredItems(from: [recent, expired], now: now).isEmpty)
    }
}
```

Add a `TrashItem.fixture(...)` helper inside the test file so tests can build encoded items without repeating encoding code.

- [ ] **Step 2: Add the persisted model and versioned payloads**

Create `Viabar/Models/TrashItem.swift` with these public boundaries:

```swift
import Foundation
import SwiftData

enum TrashItemKind: String, Codable {
    case milestone
    case subTask
    case memo
}

enum TrashRetentionPolicy: String, CaseIterable, Identifiable, Codable {
    case thirtyDays = "30-days"
    case sixtyDays = "60-days"
    case ninetyDays = "90-days"
    case forever

    static let defaultValue = TrashRetentionPolicy.ninetyDays
    var id: String { rawValue }

    static func resolve(_ rawValue: String?) -> TrashRetentionPolicy {
        TrashRetentionPolicy(rawValue: rawValue ?? "") ?? .defaultValue
    }

    var dayCount: Int? {
        switch self {
        case .thirtyDays: 30
        case .sixtyDays: 60
        case .ninetyDays: 90
        case .forever: nil
        }
    }

    func expiredItems(from items: [TrashItem], now: Date) -> [TrashItem] {
        guard let dayCount else { return [] }
        let cutoff = now.addingTimeInterval(-Double(dayCount) * 86_400)
        return items.filter { $0.deletedAt < cutoff }
    }
}

struct TrashReminderSnapshot: Codable, Equatable {
    let type: String
    let fireTime: String?
    let fireTimestamp: Date?
    let repeatIntervalDays: Int?
    let lastTriggeredTimestamp: Date?
}

struct TrashSubTaskSnapshot: Codable, Equatable {
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let orderIndex: Int
    let reminder: TrashReminderSnapshot?
}

struct TrashTaskSnapshot: Codable, Equatable {
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let reminder: TrashReminderSnapshot?
    let subtasks: [TrashSubTaskSnapshot]
}

struct TrashMemoSnapshot: Codable, Equatable {
    let content: String
    let createdAt: Date
}

enum TrashPayload: Codable, Equatable {
    case task(TrashTaskSnapshot)
    case subTask(TrashSubTaskSnapshot)
    case memo(TrashMemoSnapshot)
}

@Model
final class TrashItem {
    @Attribute(.unique) var trashItemId: UUID
    var kind: String
    var deletedAt: Date
    var originalProjectId: UUID
    var originalProjectTitle: String
    var originalProjectAccentColor: String
    var originalProjectSymbolName: String
    var originalParentTaskId: UUID?
    var originalOrderIndex: Int
    var payloadVersion: Int
    var payloadData: Data
}
```

Implement:

```swift
extension TrashItem {
    static let currentPayloadVersion = 1

    func payload() throws -> TrashPayload
    func copyText() throws -> String
    func matches(_ query: String) throws -> Bool
    var displayText: String
    var displayPath: String
}

enum TrashItemIndex {
    static func results(matching query: String, items: [TrashItem]) -> [TrashItem]
    static func sortedNewestFirst(_ items: [TrashItem]) -> [TrashItem]
}
```

Use `JSONEncoder.backupEncoder` and `JSONDecoder.backupDecoder` for stable date encoding. For `displayPath`, compact the parent task title using the same 10-character behavior as global search.

- [ ] **Step 3: Register `TrashItem` in the shared schema**

Add:

```swift
TrashItem.self,
```

to `SharedModelContainer.schema`.

- [ ] **Step 4: Perform static verification**

Run:

```bash
rg -n "TrashItem|TrashRetentionPolicy|TrashPayload|TrashItemIndex" Viabar/Models/TrashItem.swift Viabar/System/SharedModelContainer.swift ViabarTests/ViabarTests.swift
git diff --check
```

Expected: model, policy, index, schema, and tests are present; `git diff --check` prints nothing.

- [ ] **Step 5: Optionally run tests only after explicit authorization**

Run:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/TrashItemModelTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -- Viabar/Models/TrashItem.swift Viabar/System/SharedModelContainer.swift ViabarTests/ViabarTests.swift
git commit -m "feat: add trash snapshot model"
```

---

### Task 2: Add Trash Service Capture, Restore, And Cleanup

**Files:**
- Create: `Viabar/Services/TrashService.swift`
- Modify: `Viabar/Services/ProjectService.swift:24-47,191-276,703-714`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Write service tests for delete, restore, and invalid restore**

Add `@MainActor struct TrashServiceTests` with an in-memory schema that includes `TrashItem.self`. Cover:

```swift
@Test func deletingTaskStoresOneSnapshotAndRestoreRecreatesChildren() throws
@Test func deletingSubtaskStoresOneSnapshotAndRestoreRequiresOriginalParent() throws
@Test func deletingMemoStoresSnapshotAndRestoreRecreatesMemo() throws
@Test func cleanupDeletesOnlyExpiredTrashItems() throws
@Test func restoringTaskRebuildsReminderTimelineButSnapshotAloneDoesNot() throws
```

The parent-task test must assert that deleting one task with two subtasks creates exactly one `TrashItem`, and restoring it recreates one `Milestone` plus two `SubTask` values.

- [ ] **Step 2: Implement `TrashService`**

Create a main-actor observable service:

```swift
import AppKit
import Observation
import SwiftData

enum TrashRestoreAvailability: Equatable {
    case available
    case missingProject
    case missingParentTask
}

@MainActor
@Observable
final class TrashService {
    private let modelContext: ModelContext
    private let notificationScheduleService: NotificationScheduleService

    init(modelContext: ModelContext, notificationScheduleService: NotificationScheduleService) {
        self.modelContext = modelContext
        self.notificationScheduleService = notificationScheduleService
    }

    func store(_ milestone: Milestone, deletedAt: Date = Date()) throws
    func store(_ subTask: SubTask, deletedAt: Date = Date()) throws
    func store(_ memo: Memo, deletedAt: Date = Date()) throws
    func restoreAvailability(for item: TrashItem) -> TrashRestoreAvailability
    func restore(_ item: TrashItem) throws
    func copyToPasteboard(_ item: TrashItem) throws
    func cleanupExpired(policy: TrashRetentionPolicy, now: Date = Date()) throws
}
```

Implement restoration with helpers:

```swift
private func project(id: UUID) -> Project?
private func milestone(id: UUID, in project: Project) -> Milestone?
private func restoreReminder(_ snapshot: TrashReminderSnapshot?) -> Reminder?
private func normalizeMilestoneOrder(in project: Project)
private func normalizeSubTaskOrder(in milestone: Milestone)
private func normalizeMemoOrder(in project: Project)
```

Restore task and subtask reminders by calling the existing notification sync boundaries after active entities exist. Snapshot creation must not create schedule entries.

- [ ] **Step 3: Register `TrashService` in `ServiceContainer`**

Add:

```swift
extension ServiceContainer {
    var trashService: TrashService? {
        resolve(TrashService.self)
    }

    func registerTrashService(
        modelContext: ModelContext,
        notificationScheduleService: NotificationScheduleService
    ) -> TrashService {
        let service = TrashService(
            modelContext: modelContext,
            notificationScheduleService: notificationScheduleService
        )
        register(service)
        return service
    }
}
```

- [ ] **Step 4: Route active deletion through `TrashService`**

In `ProjectService`, require a trash snapshot before deleting recoverable content. If the
snapshot cannot be written, keep the active entity intact:

```swift
func deleteMilestone(_ milestone: Milestone) {
    let project = milestone.project
    guard let trashService = container.trashService else { return }
    do {
        try trashService.store(milestone)
    } catch {
        return
    }
    notificationScheduleService?.removeEntry(ownerId: milestone.milestoneId)
    milestone.subtasks.forEach { notificationScheduleService?.removeEntry(ownerId: $0.taskId) }
    modelContext.delete(milestone)
    save()
    if let project { syncProjectReminder(project) }
}
```

Apply the same pattern to `deleteSubTask(_:)` and `deleteMemo(_:)`. Do not
change `deleteProject(_:)`: projects remain permanently deleted without
generating trash entries. Keep these methods returning `Void`; a follow-up UI
error surface is out of scope because the current deletion API has no failure
presentation channel.

- [ ] **Step 5: Perform static verification**

Run:

```bash
rg -n "trashService\\.store|func restore\\(|cleanupExpired|deleteProject" Viabar/Services/ProjectService.swift Viabar/Services/TrashService.swift
git diff --check
```

Expected: milestone, subtask, and memo deletion store snapshots; project deletion does not; whitespace check prints nothing.

- [ ] **Step 6: Optionally run focused tests only after explicit authorization**

Run:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/TrashServiceTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -- Viabar/Services/TrashService.swift Viabar/Services/ProjectService.swift ViabarTests/ViabarTests.swift
git commit -m "feat: capture and restore trash items"
```

---

### Task 3: Persist Retention Settings And Clean Up Once At Launch

**Files:**
- Modify: `Viabar/Models/AppSettings.swift:190-288`
- Modify: `Viabar/ViabarApp.swift:24-40,65-72`
- Modify: `Viabar/Views/Settings/SettingsView.swift:286-332`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add settings backfill tests**

Extend `AppSettingsTests`:

```swift
@Test func defaultsTrashRetentionToNinetyDays() {
    #expect(TrashRetentionPolicy.resolve(AppSettings().trashRetentionPolicy) == .ninetyDays)
}

@Test func ensureDefaultSettingsRepairsInvalidTrashRetention() throws {
    let container = try makeSettingsContainer()
    let settings = AppSettings(trashRetentionPolicy: "invalid")
    container.mainContext.insert(settings)

    let resolved = AppSettingsStore.ensureDefaultSettings(in: container.mainContext)

    #expect(resolved.trashRetentionPolicy == TrashRetentionPolicy.ninetyDays.rawValue)
}
```

- [ ] **Step 2: Persist and repair the setting**

Add to `AppSettings`:

```swift
var trashRetentionPolicy: String = TrashRetentionPolicy.defaultValue.rawValue
```

Add initializer parameter and assignment:

```swift
trashRetentionPolicy: String = TrashRetentionPolicy.defaultValue.rawValue
self.trashRetentionPolicy = trashRetentionPolicy
```

In `ensureDefaultSettings`, repair invalid stored values alongside `weekStartDay`:

```swift
if TrashRetentionPolicy(rawValue: settings.trashRetentionPolicy) == nil {
    settings.trashRetentionPolicy = TrashRetentionPolicy.defaultValue.rawValue
    needsSave = true
}
```

Use one `needsSave` flag so backfills save once.

- [ ] **Step 3: Register and clean up trash during app startup**

In `ViabarApp.init`, register after `NotificationScheduleService`:

```swift
let trashService = container.registerTrashService(
    modelContext: sharedModelContainer.mainContext,
    notificationScheduleService: notificationScheduleService
)
try? trashService.cleanupExpired(
    policy: TrashRetentionPolicy.resolve(settings.trashRetentionPolicy)
)
```

This is the only startup cleanup trigger. Do not run cleanup whenever the picker changes.

- [ ] **Step 4: Add the settings group**

Insert between data sync and backup:

```swift
SettingsGroup("回收站") {
    SettingsRow("保留期限", description: "过期的将从本地和云端永久抹除") {
        Picker("", selection: $settings.trashRetentionPolicy) {
            Text("30天").tag(TrashRetentionPolicy.thirtyDays.rawValue)
            Text("60天").tag(TrashRetentionPolicy.sixtyDays.rawValue)
            Text("90天").tag(TrashRetentionPolicy.ninetyDays.rawValue)
            Text("永久").tag(TrashRetentionPolicy.forever.rawValue)
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 96)
    }
}
```

- [ ] **Step 5: Perform static verification**

Run:

```bash
rg -n "trashRetentionPolicy|registerTrashService|cleanupExpired|SettingsGroup\\(\"回收站\"" Viabar/Models/AppSettings.swift Viabar/ViabarApp.swift Viabar/Views/Settings/SettingsView.swift ViabarTests/ViabarTests.swift
git diff --check
```

Expected: setting, startup registration, one cleanup trigger, picker, and tests are present; whitespace check prints nothing.

- [ ] **Step 6: Commit**

```bash
git add -- Viabar/Models/AppSettings.swift Viabar/ViabarApp.swift Viabar/Views/Settings/SettingsView.swift ViabarTests/ViabarTests.swift
git commit -m "feat: add trash retention setting"
```

---

### Task 4: Include Trash In Complete Backup And Full Restore

**Files:**
- Modify: `Viabar/Models/BackupSnapshot.swift:3-64`
- Modify: `Viabar/Services/BackupService.swift:120-210,299-455`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Extend backup tests**

Update existing snapshot initializers to include `trashItems: []`. Add:

```swift
@Test func decodesLegacyBackupWithoutTrashItems() throws {
    let snapshot = try JSONDecoder.backupDecoder.decode(
        BackupSnapshot.self,
        from: Data(legacyBackupWithoutTrashItems.utf8)
    )
    #expect(snapshot.trashItems.isEmpty)
}

@Test func restoreRecreatesTrashAndImmediatelyRemovesExpiredItems() throws {
    // Build a snapshot with ninety-day retention, one recent trash item,
    // and one item older than ninety days. Restore with a fixed now value.
    // Assert only the recent item remains and no NotificationScheduleEntry
    // is generated from dormant trash reminder snapshots.
}
```

Refactor `BackupService.restore(snapshot:)` to accept `now: Date = Date()` so cleanup is deterministic in tests.

- [ ] **Step 2: Add backup trash snapshots with legacy decoding**

In `BackupSnapshot`, add:

```swift
let trashItems: [BackupTrashItemSnapshot]
```

Add:

```swift
struct BackupTrashItemSnapshot: Codable, Equatable {
    let trashItemId: UUID
    let kind: String
    let deletedAt: Date
    let originalProjectId: UUID
    let originalProjectTitle: String
    let originalProjectAccentColor: String
    let originalProjectSymbolName: String
    let originalParentTaskId: UUID?
    let originalOrderIndex: Int
    let payloadVersion: Int
    let payloadData: Data
}
```

Provide a custom `BackupSnapshot.init(from:)` that decodes:

```swift
trashItems = try container.decodeIfPresent([BackupTrashItemSnapshot].self, forKey: .trashItems) ?? []
```

Because adding a custom decoder suppresses the synthesized memberwise
initializer, also add an explicit initializer:

```swift
init(
    formatVersion: Int,
    createdAt: Date,
    settings: BackupSettingsSnapshot,
    folders: [BackupFolderSnapshot],
    projects: [BackupProjectSnapshot],
    templates: [BackupTemplateSnapshot],
    trashItems: [BackupTrashItemSnapshot]
) {
    self.formatVersion = formatVersion
    self.createdAt = createdAt
    self.settings = settings
    self.folders = folders
    self.projects = projects
    self.templates = templates
    self.trashItems = trashItems
}
```

Keep `currentFormatVersion = 1` so pre-trash backups remain restorable.

Add `trashRetentionPolicy: String?` to `BackupSettingsSnapshot`. Decode it as optional so legacy settings snapshots remain valid; apply it with:

```swift
settings.trashRetentionPolicy = TrashRetentionPolicy.resolve(snapshot.trashRetentionPolicy).rawValue
```

- [ ] **Step 3: Capture and restore trash**

In `makeSnapshot`, fetch:

```swift
let trashItems = try modelContext.fetch(FetchDescriptor<TrashItem>())
```

Serialize with a helper:

```swift
private func trashSnapshot(_ item: TrashItem) -> BackupTrashItemSnapshot
```

In `deleteExistingRecoverableData`, delete existing `TrashItem` records. In `restore(snapshot:now:)`, recreate trash records before saving:

```swift
restoreTrashItems(snapshot.trashItems)
try modelContext.save()
try trashService.cleanupExpired(
    policy: TrashRetentionPolicy.resolve(settings.trashRetentionPolicy),
    now: now
)
notificationScheduleService.rebuildTimeline(from: projects)
```

`BackupService` does not currently hold `ServiceContainer`. Inject
`TrashService` directly into its initializer and registration method, then call
`trashService.cleanupExpired(...)`. Update the existing registration call in
`ViabarApp.init`:

```swift
_ = container.registerBackupService(
    modelContext: sharedModelContainer.mainContext,
    notificationScheduleService: notificationScheduleService,
    trashService: trashService
)
```

- [ ] **Step 4: Perform static verification**

Run:

```bash
rg -n "BackupTrashItemSnapshot|trashItems|decodeIfPresent|trashRetentionPolicy|restoreTrashItems|cleanupExpired" Viabar/Models/BackupSnapshot.swift Viabar/Services/BackupService.swift ViabarTests/ViabarTests.swift
git diff --check
```

Expected: legacy decode, capture, replacement, restoration, cleanup, and dormant reminder test coverage are visible; whitespace check prints nothing.

- [ ] **Step 5: Optionally run focused tests only after explicit authorization**

Run:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/BackupMetadataTests -only-testing:ViabarTests/BackupRestoreTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -- Viabar/Models/BackupSnapshot.swift Viabar/Services/BackupService.swift ViabarTests/ViabarTests.swift
git commit -m "feat: include trash in backup restore"
```

---

### Task 5: Add The Trash Browser Sheet

**Files:**
- Create: `Viabar/Views/Component/TrashBrowserView.swift`
- Modify: `Viabar/Views/Sidebar/SidebarView.swift:105-205`

- [ ] **Step 1: Create the wide trash browser**

Implement:

```swift
import SwiftData
import SwiftUI

struct TrashBrowserView: View {
    @Environment(ServiceContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TrashItem.deletedAt, order: .reverse) private var trashItems: [TrashItem]
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var query = ""
    @State private var errorMessage: String?

    private var results: [TrashItem] {
        TrashItemIndex.results(matching: query, items: trashItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            resultContent
        }
        .frame(width: 720, height: 520)
    }
}
```

Create row rendering that mirrors `GlobalSearchResultRow`:

```swift
private struct TrashResultRow: View {
    let item: TrashItem
    let onRestore: () -> Void
    let onCopy: () -> Void
    let availability: TrashRestoreAvailability
}
```

The row displays original project symbol/color, `displayText`, `displayPath`,
and
`AppDateFormatter.string(from:item.deletedAt, pattern: settingsRecords.first?.dateFormat)`
as gray right-aligned text.

- [ ] **Step 2: Add context menu restore and copy behavior**

Use:

```swift
.contextMenu {
    Button("恢复", action: onRestore)
        .disabled(availability != .available)
    Button("复制内容", action: onCopy)
    if availability == .missingProject {
        Divider()
        Text("原项目已不存在")
    } else if availability == .missingParentTask {
        Divider()
        Text("原任务已不存在")
    }
}
```

On restore failure, display a localized alert. Do not add permanent deletion.

- [ ] **Step 3: Present the browser from sidebar state**

In `SidebarView`, add:

```swift
@State private var isTrashBrowserPresented = false
```

and:

```swift
.sheet(isPresented: $isTrashBrowserPresented) {
    TrashBrowserView()
}
```

The actual bottom entry is added in Task 6.

- [ ] **Step 4: Perform static verification**

Run:

```bash
rg -n "TrashBrowserView|TrashResultRow|复制内容|原项目已不存在|原任务已不存在|isTrashBrowserPresented" Viabar/Views/Component/TrashBrowserView.swift Viabar/Views/Sidebar/SidebarView.swift
git diff --check
```

Expected: wide sheet, list, restore, copy, disabled reasons, and presentation state are present; whitespace check prints nothing.

- [ ] **Step 5: Commit**

```bash
git add -- Viabar/Views/Component/TrashBrowserView.swift Viabar/Views/Sidebar/SidebarView.swift
git commit -m "feat: add trash browser sheet"
```

---

### Task 6: Add Sidebar Entry, Hover Polish, And Shared Two-Step Project Deletion

**Files:**
- Create: `Viabar/Views/Component/PermanentProjectDeletionModifier.swift`
- Modify: `Viabar/Views/Sidebar/SidebarView.swift:52-205,207-248,253-520,549-765,1160-1320`
- Modify: `Viabar/ContentView.swift:18-28,118-148`

- [ ] **Step 1: Add reusable two-step deletion modifier**

Create:

```swift
import SwiftUI

struct PermanentProjectDeletionModifier: ViewModifier {
    @Binding var project: Project?
    let onDelete: (Project) -> Void
    @State private var projectAwaitingFinalConfirmation: Project?

    func body(content: Content) -> some View {
        content
            .alert("删除项目？", isPresented: firstConfirmationBinding) {
                Button("继续", role: .destructive) {
                    projectAwaitingFinalConfirmation = project
                    project = nil
                }
                Button("取消", role: .cancel) { project = nil }
            } message: {
                if let project {
                    Text("“\(project.title)”包含 \(project.milestones.count) 条任务和 \(project.memos.count) 条备忘录。删除项目后不可恢复。")
                }
            }
            .alert("再次确认删除项目", isPresented: finalConfirmationBinding) {
                Button("确认删除", role: .destructive) {
                    guard let projectAwaitingFinalConfirmation else { return }
                    onDelete(projectAwaitingFinalConfirmation)
                    self.projectAwaitingFinalConfirmation = nil
                }
                Button("取消", role: .cancel) {
                    projectAwaitingFinalConfirmation = nil
                }
            } message: {
                Text("是否确认永久删除这个项目？")
            }
    }
}

extension View {
    func permanentProjectDeletionConfirmation(
        project: Binding<Project?>,
        onDelete: @escaping (Project) -> Void
    ) -> some View
}
```

- [ ] **Step 2: Replace both single-confirmation paths**

In `SidebarView`, remove project handling from `DeleteConfirmation`; keep folder confirmation separate. Attach:

```swift
.permanentProjectDeletionConfirmation(project: $projectPendingDeletion) { project in
    if selection == .project(project) { selection = .overview }
    projectService?.deleteProject(project)
}
```

In `ContentView`, replace the overview-card alert with:

```swift
.permanentProjectDeletionConfirmation(project: $overviewDeleteProject) { project in
    if selection == .project(project) { selection = .overview }
    projectService?.deleteProject(project)
}
```

- [ ] **Step 3: Add bottom trash row without divider**

Wrap the sidebar list:

```swift
VStack(spacing: 0) {
    List(selection: $selection) {
        overviewSection
        projectsSection
        archiveSection
    }
    .listStyle(.sidebar)

    Button {
        isTrashBrowserPresented = true
    } label: {
        Label("回收站", systemImage: "trash")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: ActiveProjectRowMetrics.defaultRowHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(isTrashHovered ? ActiveProjectRowMetrics.sidebarHoverColor : .clear)
            }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, ActiveProjectRowMetrics.defaultHorizontalInset)
    .padding(.bottom, 8)
    .onHover { isTrashHovered = $0 }
}
```

Do not insert a divider above this button.

- [ ] **Step 4: Add shared gray capsule hover presentation**

Add:

```swift
static let sidebarHoverColor = Color(nsColor: .controlAccentColor).opacity(0.10)
```

or a neutral adaptive `NSColor` provider if accent-derived gray is not visually neutral enough.

Track `@State private var isHovered = false` in:

- the overview button;
- `ActiveProjectRow`;
- `ArchivedProjectSelectableRow`;
- the bottom trash button.

Render a capsule hover layer only when a row is not selected:

```swift
Capsule(style: .continuous)
    .fill(!isSelected && isHovered ? ActiveProjectRowMetrics.sidebarHoverColor : .clear)
```

Do not change folder-header hover styling unless source inspection shows it uses the same project-row component.

- [ ] **Step 5: Perform static verification**

Run:

```bash
rg -n "permanentProjectDeletionConfirmation|再次确认删除项目|isTrashBrowserPresented|Label\\(\"回收站\", systemImage: \"trash\"\\)|sidebarHoverColor|onHover" Viabar/ContentView.swift Viabar/Views/Sidebar/SidebarView.swift Viabar/Views/Component/PermanentProjectDeletionModifier.swift
git diff --check
```

Expected: both deletion surfaces share the modifier; bottom row has no divider; overview, active project, archived project, and trash rows have hover state; whitespace check prints nothing.

- [ ] **Step 6: Commit**

```bash
git add -- Viabar/Views/Component/PermanentProjectDeletionModifier.swift Viabar/Views/Sidebar/SidebarView.swift Viabar/ContentView.swift
git commit -m "feat: add trash entry and safer project deletion"
```

---

### Task 7: Localize New Trash And Project Deletion Copy

**Files:**
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add Simplified Chinese strings**

Add keys:

```text
"回收站" = "回收站";
"保留期限" = "保留期限";
"过期的将从本地和云端永久抹除" = "过期的将从本地和云端永久抹除";
"30天" = "30天";
"60天" = "60天";
"90天" = "90天";
"永久" = "永久";
"搜索项目、任务、子任务和备忘录" = "搜索项目、任务、子任务和备忘录";
"回收站中没有内容" = "回收站中没有内容";
"复制内容" = "复制内容";
"原项目已不存在" = "原项目已不存在";
"原任务已不存在" = "原任务已不存在";
"无法恢复回收站内容" = "无法恢复回收站内容";
"继续" = "继续";
"再次确认删除项目" = "再次确认删除项目";
"确认删除" = "确认删除";
"“%@”包含 %lld 条任务和 %lld 条备忘录。删除项目后不可恢复。" = "“%@”包含 %lld 条任务和 %lld 条备忘录。删除项目后不可恢复。";
"是否确认永久删除这个项目？" = "是否确认永久删除这个项目？";
```

- [ ] **Step 2: Add English strings**

Add:

```text
"回收站" = "Trash";
"保留期限" = "Retention";
"过期的将从本地和云端永久抹除" = "Expired items are permanently erased locally and from the cloud.";
"30天" = "30 days";
"60天" = "60 days";
"90天" = "90 days";
"永久" = "Forever";
"搜索项目、任务、子任务和备忘录" = "Search projects, tasks, subtasks, and memos";
"回收站中没有内容" = "Trash is empty";
"复制内容" = "Copy Content";
"原项目已不存在" = "The original project no longer exists";
"原任务已不存在" = "The original task no longer exists";
"无法恢复回收站内容" = "Unable to Restore Trash Item";
"继续" = "Continue";
"再次确认删除项目" = "Confirm Project Deletion Again";
"确认删除" = "Delete Permanently";
"“%@”包含 %lld 条任务和 %lld 条备忘录。删除项目后不可恢复。" = "\"%@\" contains %lld tasks and %lld memos. Deleting this project cannot be undone.";
"是否确认永久删除这个项目？" = "Are you sure you want to permanently delete this project?";
```

- [ ] **Step 3: Perform static verification**

Run:

```bash
rg -n '"回收站"|"保留期限"|"复制内容"|"再次确认删除项目"|"是否确认永久删除这个项目？"' Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git diff --check
```

Expected: both localization files contain every new key; whitespace check prints nothing.

- [ ] **Step 4: Commit**

```bash
git add -- Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git commit -m "feat: localize trash flows"
```

---

### Task 8: Update Preview Schemas And Run Final Static Verification

**Files:**
- Modify: `Viabar/ContentView.swift:1015-1031`
- Modify: `Viabar/Views/Sidebar/SidebarView.swift:1630-1646`
- Modify: any other in-memory `Schema([...])` arrays found by search
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add `TrashItem.self` to every relevant schema**

Search:

```bash
rg -n "Schema\\(\\[" Viabar ViabarTests --glob '*.swift'
```

For any schema used with `ProjectService`, `TrashService`, `BackupService`, app previews, or test helpers, add:

```swift
TrashItem.self,
```

- [ ] **Step 2: Confirm delete call sites remain centralized**

Run:

```bash
rg -n "modelContext\\.delete\\((milestone|subTask|memo)\\)|deleteMilestone\\(|deleteSubTask\\(|deleteMemo\\(" Viabar --glob '*.swift'
```

Expected: view call sites invoke `ProjectService`; active entity deletion occurs only in `ProjectService`; `TrashService` deletes consumed `TrashItem` records after restore and expired items during cleanup.

- [ ] **Step 3: Confirm backup and startup wiring**

Run:

```bash
rg -n "TrashItem\\.self|registerTrashService|cleanupExpired|trashItems|restoreTrashItems|trashRetentionPolicy" Viabar ViabarTests --glob '*.swift'
```

Expected: shared schema, preview/test schemas, startup cleanup, backup capture, full restore, settings persistence, and tests are visible.

- [ ] **Step 4: Run whitespace verification**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` prints nothing; status contains only intended implementation files.

- [ ] **Step 5: Optionally run the complete test target only after explicit authorization**

Run:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -- Viabar ViabarTests
git commit -m "test: cover trash retention restore flow"
```

---

## Final Review Checklist

- [ ] Deleting a task creates one trash row even when it contains subtasks.
- [ ] Deleting a subtask directly creates one trash row and restores only to its original task.
- [ ] Deleting a memo creates one trash row.
- [ ] Deleting a project creates no trash rows and requires two confirmations from sidebar and overview.
- [ ] Existing trash items remain visible and copyable after their source project is deleted.
- [ ] Trash search matches project name, top-level content, and nested subtask content with localized case-insensitive contains matching.
- [ ] Trash list defaults to newest deletion first and shows deletion time at right.
- [ ] Context menu contains restore and copy only; no manual permanent delete exists.
- [ ] Startup cleanup runs once and respects 30, 60, 90, and forever policies.
- [ ] Backup captures trash; full restore replaces trash; restored expired items are cleaned immediately.
- [ ] Trash reminder snapshots remain dormant until restored.
- [ ] Bottom trash row has no divider and hover polish matches overview shape.
- [ ] Overview, active projects, and archived projects receive neutral gray capsule hover feedback.
- [ ] English and Simplified Chinese strings cover all new UI.
- [ ] `git diff --check` prints nothing.
- [ ] No build or test command runs without explicit user authorization.
