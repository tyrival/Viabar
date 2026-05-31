# Desktop Large Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configurable, interactive macOS Large desktop Widget that reads Viabar projects from an App Group SwiftData store, lets users choose an active project through the system Edit Widget flow, and completes visible tasks directly from the desktop.

**Architecture:** Keep SwiftData as the single source of truth. Extract pure task-state mutation and Widget snapshot projection into shared model helpers, move production persistence behind a shared-store factory that migrates the legacy default store into an App Group container, and add a Widget Extension using `AppIntentConfiguration`, a dynamic project entity query, and an interactive completion intent. Keep CloudKit disabled in this release while constructing the shared store with an explicit `.none` CloudKit database so a later iCloud phase remains possible.

**Tech Stack:** SwiftUI, WidgetKit, App Intents, SwiftData, App Group entitlements, Swift Testing, Xcode project target configuration.

**Repository Constraint:** Do not run `xcodebuild`, Swift tests, previews, app-launch workflows, or Widget installation workflows unless the user explicitly authorizes compilation. This plan specifies test-first source changes; without later authorization, verification is limited to source inspection, `plutil -lint`, `git diff --check`, and project-file inspection.

---

## File Map

- Create `Viabar/Models/TaskCompletionMutation.swift`: pure milestone/subtask completion mutation shared by `ProjectService` and Widget intents.
- Modify `Viabar/Services/ProjectService.swift`: delegate existing task completion entry points to the shared mutation helper while preserving reminder timeline synchronization.
- Create `Viabar/Models/WidgetContent.swift`: pure active-project projection, reminder tone classification, task flattening, row-budget truncation, and lightweight Widget snapshots.
- Create `Viabar/System/SharedModelContainer.swift`: canonical Schema, App Group configuration, production container construction, legacy store migration, and failure fallback.
- Modify `Viabar/ViabarApp.swift`: construct the application container through the shared-store factory.
- Create `ViabarWidget/ViabarWidgetBundle.swift`: Widget Extension entry point.
- Create `ViabarWidget/WidgetProjectIntent.swift`: dynamic active-project entity query and nullable Widget configuration intent.
- Create `ViabarWidget/ToggleWidgetTaskIntent.swift`: interactive desktop checkbox action that updates the shared SwiftData store and refreshes timelines.
- Create `ViabarWidget/ViabarLargeWidget.swift`: provider, timeline entry, Large Widget view, task rows, reminder colors, truncation footer, and empty states.
- Create `ViabarWidget/ViabarWidget.entitlements`: App Group entitlement for the Widget Extension.
- Create `ViabarWidget/en.lproj/Localizable.strings`: English Widget copy.
- Create `ViabarWidget/zh-Hans.lproj/Localizable.strings`: Simplified-Chinese Widget copy.
- Modify `Viabar/Viabar.entitlements`: add the same App Group entitlement to the main application.
- Modify `Viabar/en.lproj/Localizable.strings`: main-target English copy needed by shared code.
- Modify `Viabar/zh-Hans.lproj/Localizable.strings`: main-target Simplified-Chinese copy needed by shared code.
- Modify `Viabar.xcodeproj/project.pbxproj`: add Widget Extension target, embed phase, product, synchronized source group, target dependency, build settings, and target membership for the shared Swift files.
- Modify `ViabarTests/ViabarTests.swift`: specify mutation, projection, row-budget, reminder-tone, active-project filtering, and migration behavior.

## Shared Target Membership

The Widget Extension needs the complete persistent Schema, not a hand-picked subset. Add these existing files to the Widget target membership:

- `Viabar/Models/Project.swift`
- `Viabar/Models/AppSettings.swift`
- `Viabar/Models/ReminderDisplay.swift`
- `Viabar/System/ViabarColor.swift`
- `Viabar/Views/Component/Color+Hex.swift`
- `Viabar/System/AppLanguageController.swift`
- `Viabar/Models/TaskCompletionMutation.swift`
- `Viabar/Models/WidgetContent.swift`
- `Viabar/System/SharedModelContainer.swift`

Do not add application views, Sparkle-dependent services, backup services, notification services, or `ViabarApp.swift` to the Widget target.

### Task 1: Extract Shared Task Completion Mutation

**Files:**
- Create: `Viabar/Models/TaskCompletionMutation.swift`
- Modify: `Viabar/Services/ProjectService.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add failing shared-mutation tests**

Append a focused suite:

```swift
struct TaskCompletionMutationTests {
    @Test func togglingParentTaskCompletesEveryChild() {
        let milestone = Milestone(title: "Release")
        let first = SubTask(title: "Package")
        let second = SubTask(title: "Publish")
        first.milestone = milestone
        second.milestone = milestone
        milestone.subtasks = [first, second]

        TaskCompletionMutation.toggle(milestone)

        #expect(milestone.isCompleted)
        #expect(milestone.completedAt != nil)
        #expect(milestone.subtasks.allSatisfy(\.isCompleted))
        #expect(milestone.subtasks.allSatisfy { $0.completedAt != nil })
    }

    @Test func togglingLastChildCompletesParentTask() {
        let milestone = Milestone(title: "Release")
        let first = SubTask(title: "Package", isCompleted: true)
        let second = SubTask(title: "Publish")
        first.milestone = milestone
        second.milestone = milestone
        milestone.subtasks = [first, second]

        TaskCompletionMutation.toggle(second)

        #expect(second.isCompleted)
        #expect(milestone.isCompleted)
        #expect(milestone.completedAt != nil)
    }
}
```

- [ ] **Step 2: Leave red execution paused under the repository constraint**

Do not invoke the `ViabarTests` target unless the user separately approves compilation. Record that the new expectations are authored but intentionally unexecuted.

- [ ] **Step 3: Add the pure mutation helper**

Create `TaskCompletionMutation.swift`:

```swift
import Foundation

enum TaskCompletionMutation {
    static func toggle(_ milestone: Milestone, now: Date = Date()) {
        if milestone.subtasks.isEmpty {
            milestone.isCompleted.toggle()
            milestone.completedAt = milestone.isCompleted ? now : nil
            return
        }

        let target = !milestone.isCompleted
        let completedAt = target ? now : nil
        for subtask in milestone.subtasks {
            subtask.isCompleted = target
            subtask.completedAt = completedAt
        }
        milestone.isCompleted = target
        milestone.completedAt = completedAt
    }

    static func toggle(_ subtask: SubTask, now: Date = Date()) {
        subtask.isCompleted.toggle()
        subtask.completedAt = subtask.isCompleted ? now : nil
        subtask.milestone?.syncCompletionFromSubtasks()
    }
}
```

- [ ] **Step 4: Reuse the helper from `ProjectService`**

Replace the duplicated mutation bodies:

```swift
func toggleMilestoneComplete(_ milestone: Milestone) {
    TaskCompletionMutation.toggle(milestone)
    save()
    if let project = milestone.project {
        syncReminderTimeline(for: project)
    }
}

func toggleSubTaskComplete(_ subTask: SubTask) {
    TaskCompletionMutation.toggle(subTask)
    save()
    if let project = subTask.milestone?.project {
        syncReminderTimeline(for: project)
    }
}
```

- [ ] **Step 5: Commit the shared mutation**

```bash
git add -- Viabar/Models/TaskCompletionMutation.swift Viabar/Services/ProjectService.swift ViabarTests/ViabarTests.swift
git commit -m "refactor: share task completion mutation"
```

### Task 2: Build Pure Widget Snapshot Projection

**Files:**
- Create: `Viabar/Models/WidgetContent.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add failing projection and reminder-tone tests**

Append:

```swift
struct WidgetContentTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func activeProjectsExcludeArchivedProjectsAndPreserveOrder() {
        let second = Project(title: "Second", orderIndex: 1)
        let first = Project(title: "First", orderIndex: 0)
        let archived = Project(title: "Archived", orderIndex: 2)
        archived.isArchived = true

        #expect(WidgetContentBuilder.activeProjects(from: [second, archived, first]).map(\.title) == ["First", "Second"])
    }

    @Test func flattensUnfinishedParentsAndChildrenWithoutParentSubtitle() {
        let project = Project(title: "Release")
        let milestone = Milestone(title: "Prepare", orderIndex: 0)
        let child = SubTask(title: "Package", orderIndex: 0)
        let done = SubTask(title: "Already done", orderIndex: 1, isCompleted: true)
        milestone.project = project
        child.milestone = milestone
        done.milestone = milestone
        milestone.subtasks = [done, child]
        project.milestones = [milestone]

        let items = WidgetContentBuilder.items(for: project, now: Date(), calendar: calendar)

        #expect(items.map(\.title) == ["Prepare", "Package"])
        #expect(items.map(\.kind) == [.milestone, .subTask])
        #expect(items.map(\.isIndented) == [false, true])
    }

    @Test func classifiesOverdueTodayPendingAndFutureReminders() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 12))!

        #expect(WidgetReminderTone.resolve(fireDate: now.addingTimeInterval(-60), now: now, calendar: calendar) == .overdue)
        #expect(WidgetReminderTone.resolve(fireDate: now.addingTimeInterval(60), now: now, calendar: calendar) == .todayPending)
        #expect(WidgetReminderTone.resolve(fireDate: now.addingTimeInterval(86_400), now: now, calendar: calendar) == .future)
        #expect(WidgetReminderTone.resolve(fireDate: nil, now: now, calendar: calendar) == nil)
    }

    @Test func truncatesByRowBudgetAndReportsHiddenCount() {
        let project = Project(title: "Release")
        project.milestones = (0..<5).map { Milestone(title: "Task \($0)", orderIndex: $0) }

        let content = WidgetContentBuilder.content(for: project, rowBudget: 3, now: Date(), calendar: calendar)

        #expect(content.visibleItems.map(\.title) == ["Task 0", "Task 1", "Task 2"])
        #expect(content.hiddenItemCount == 2)
    }

    @Test func reminderSubtitleConsumesASecondBudgetRow() {
        let now = Date()
        let project = Project(title: "Release")
        let reminded = Milestone(title: "Reminded", orderIndex: 0)
        reminded.reminder = Reminder(type: "single", fireTimestamp: now.addingTimeInterval(60))
        let plain = Milestone(title: "Plain", orderIndex: 1)
        project.milestones = [reminded, plain]

        let content = WidgetContentBuilder.content(for: project, rowBudget: 2, now: now, calendar: calendar)

        #expect(content.visibleItems.map(\.title) == ["Reminded"])
        #expect(content.hiddenItemCount == 1)
    }
}
```

- [ ] **Step 2: Leave red execution paused under the repository constraint**

Do not compile. Keep the expected failing state documented until compilation is separately authorized.

- [ ] **Step 3: Add snapshot value types**

Create `WidgetContent.swift` with the value model:

```swift
import Foundation

enum WidgetTaskKind: String, Codable, Equatable {
    case milestone
    case subTask
}

enum WidgetReminderTone: Equatable {
    case overdue
    case todayPending
    case future

    static func resolve(fireDate: Date?, now: Date, calendar: Calendar) -> WidgetReminderTone? {
        guard let fireDate else { return nil }
        if fireDate < now { return .overdue }
        return calendar.isDate(fireDate, inSameDayAs: now) ? .todayPending : .future
    }
}

struct WidgetTaskItem: Identifiable, Equatable {
    let id: UUID
    let kind: WidgetTaskKind
    let title: String
    let isIndented: Bool
    let reminderDate: Date?
    let reminderTone: WidgetReminderTone?

    var rowCost: Int { reminderDate == nil ? 1 : 2 }
}

struct WidgetProjectContent: Equatable {
    let projectID: UUID
    let title: String
    let sfSymbolName: String
    let accentColor: String
    let progress: Double
    let visibleItems: [WidgetTaskItem]
    let hiddenItemCount: Int
}
```

- [ ] **Step 4: Implement flattening and budget projection**

Add:

```swift
enum WidgetContentBuilder {
    static func activeProjects(from projects: [Project]) -> [Project] {
        projects
            .filter { !$0.isArchived }
            .sorted {
                $0.orderIndex == $1.orderIndex
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.orderIndex < $1.orderIndex
            }
    }

    static func items(for project: Project, now: Date, calendar: Calendar = .current) -> [WidgetTaskItem] {
        project.milestones
            .sorted { $0.orderIndex < $1.orderIndex }
            .flatMap { milestone -> [WidgetTaskItem] in
                guard !milestone.isCompleted else { return [] }
                let parent = item(
                    id: milestone.milestoneId,
                    kind: .milestone,
                    title: milestone.title,
                    isIndented: false,
                    reminder: milestone.reminder,
                    now: now,
                    calendar: calendar
                )
                let children = milestone.subtasks
                    .filter { !$0.isCompleted }
                    .sorted { $0.orderIndex < $1.orderIndex }
                    .map {
                        item(
                            id: $0.taskId,
                            kind: .subTask,
                            title: $0.title,
                            isIndented: true,
                            reminder: $0.reminder,
                            now: now,
                            calendar: calendar
                        )
                    }
                return [parent] + children
            }
    }

    static func content(
        for project: Project,
        rowBudget: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> WidgetProjectContent {
        let allItems = items(for: project, now: now, calendar: calendar)
        var remaining = max(0, rowBudget)
        var visible: [WidgetTaskItem] = []
        for item in allItems {
            guard item.rowCost <= remaining else { break }
            visible.append(item)
            remaining -= item.rowCost
        }
        return WidgetProjectContent(
            projectID: project.projectId,
            title: project.title,
            sfSymbolName: project.sfSymbolName,
            accentColor: project.accentColor,
            progress: project.progress,
            visibleItems: visible,
            hiddenItemCount: allItems.count - visible.count
        )
    }

    private static func item(
        id: UUID,
        kind: WidgetTaskKind,
        title: String,
        isIndented: Bool,
        reminder: Reminder?,
        now: Date,
        calendar: Calendar
    ) -> WidgetTaskItem {
        let reminderDate = reminder?.displayFireDate
        return WidgetTaskItem(
            id: id,
            kind: kind,
            title: title,
            isIndented: isIndented,
            reminderDate: reminderDate,
            reminderTone: WidgetReminderTone.resolve(fireDate: reminderDate, now: now, calendar: calendar)
        )
    }
}
```

When implementing, use a manual `for` loop that stops at the first item that cannot fit. Do not skip an expensive reminder row and display later items out of order.

- [ ] **Step 5: Commit Widget projection**

```bash
git add -- Viabar/Models/WidgetContent.swift ViabarTests/ViabarTests.swift
git commit -m "feat: add desktop widget content projection"
```

### Task 3: Add App Group Store Factory And Legacy Migration

**Files:**
- Create: `Viabar/System/SharedModelContainer.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add failing store-path and migration tests**

Append:

```swift
@MainActor
struct SharedModelContainerTests {
    @Test func migratesLegacyStoreFilesBeforeOpeningSharedContainer() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let legacy = root.appending(path: "legacy/default.store")
        let shared = root.appending(path: "group/default.store")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("store".utf8).write(to: legacy)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))

        try SharedStoreMigrator.migrateStoreFilesIfNeeded(
            legacyStoreURL: legacy,
            sharedStoreURL: shared,
            validate: { candidate in
                #expect(FileManager.default.fileExists(atPath: candidate.path))
            }
        )

        #expect(FileManager.default.fileExists(atPath: shared.path))
        #expect(FileManager.default.fileExists(atPath: shared.path + "-wal"))
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(
            FileManager.default.fileExists(
                atPath: shared.deletingLastPathComponent()
                    .appending(path: SharedModelContainer.migrationMarkerFileName).path
            )
        )
    }

    @Test func failedValidationKeepsLegacyStoreAndDoesNotPublishSharedStore() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let legacy = root.appending(path: "legacy/default.store")
        let shared = root.appending(path: "group/default.store")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("store".utf8).write(to: legacy)

        #expect(throws: Error.self) {
            try SharedStoreMigrator.migrateStoreFilesIfNeeded(
                legacyStoreURL: legacy,
                sharedStoreURL: shared,
                validate: { _ in throw SharedStoreError.validationFailed }
            )
        }
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: shared.path))
    }
}
```

- [ ] **Step 2: Leave red execution paused under the repository constraint**

Do not run tests until the user authorizes compilation.

- [ ] **Step 3: Define the canonical Schema and App Group identifiers**

Create `SharedModelContainer.swift`:

```swift
import Foundation
import OSLog
import SwiftData

enum SharedModelContainer {
    static let appGroupIdentifier = "group.com.tyrival.Viabar"
    static let storeFileName = "default.store"
    static let migrationMarkerFileName = ".viabar-shared-store-v1"
    static let widgetKind = "ViabarLargeWidget"
    static let logger = Logger(subsystem: "com.tyrival.Viabar", category: "SharedModelContainer")

    static var schema: Schema {
        Schema([
            Project.self,
            Milestone.self,
            SubTask.self,
            Memo.self,
            Reminder.self,
            NotificationScheduleEntry.self,
            ArchiveFolder.self,
            ProjectTemplate.self,
            TemplateMilestone.self,
            TemplateSubTask.self,
            AppSettings.self,
        ])
    }
}
```

- [ ] **Step 4: Add production URL resolution and explicit CloudKit-disabled configuration**

Add focused constructors:

```swift
extension SharedModelContainer {
    static func sharedStoreURL(fileManager: FileManager = .default) throws -> URL {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedStoreError.appGroupUnavailable
        }
        return containerURL
            .appending(path: "ViabarSharedStore", directoryHint: .isDirectory)
            .appending(path: storeFileName)
    }

    static func legacyStoreURL(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: storeFileName)
    }

    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Viabar",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

During implementation, verify the exact SwiftData initializer labels against the installed SDK without compiling. If the SDK exposes the App Group convenience parameter reliably, prefer:

```swift
groupContainer: .identifier(appGroupIdentifier),
cloudKitDatabase: .none
```

Keep the explicit store URL available because migration needs a concrete destination.

- [ ] **Step 5: Implement conservative sidecar-file migration**

Add:

```swift
enum SharedStoreError: Error {
    case appGroupUnavailable
    case validationFailed
}

enum SharedStoreMigrator {
    private static let suffixes = ["", "-wal", "-shm"]

    static func migrateStoreFilesIfNeeded(
        legacyStoreURL: URL,
        sharedStoreURL: URL,
        fileManager: FileManager = .default,
        validate: (URL) throws -> Void
    ) throws {
        guard fileManager.fileExists(atPath: legacyStoreURL.path),
              !fileManager.fileExists(atPath: sharedStoreURL.path)
        else { return }

        let sharedStoreDirectory = sharedStoreURL.deletingLastPathComponent()
        let temporaryDirectory = sharedStoreDirectory
            .deletingLastPathComponent()
            .appending(path: ".viabar-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        let candidateURL = temporaryDirectory.appending(path: sharedStoreURL.lastPathComponent)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        do {
            for suffix in suffixes {
                let source = URL(fileURLWithPath: legacyStoreURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(
                    at: source,
                    to: URL(fileURLWithPath: candidateURL.path + suffix)
                )
            }
            try validate(candidateURL)
            try Data().write(
                to: temporaryDirectory
                    .appending(path: SharedModelContainer.migrationMarkerFileName)
            )
            try fileManager.moveItem(at: temporaryDirectory, to: sharedStoreDirectory)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
        try? fileManager.removeItem(at: temporaryDirectory)
    }
}
```

- [ ] **Step 6: Add main-app fallback and Widget strict constructors**

Add:

```swift
extension SharedModelContainer {
    static func makeMainAppContainer(fileManager: FileManager = .default) throws -> ModelContainer {
        let legacy = try legacyStoreURL(fileManager: fileManager)
        do {
            let shared = try sharedStoreURL(fileManager: fileManager)
            try SharedStoreMigrator.migrateStoreFilesIfNeeded(
                legacyStoreURL: legacy,
                sharedStoreURL: shared,
                fileManager: fileManager,
                validate: { candidate in _ = try makeContainer(storeURL: candidate) }
            )
            try fileManager.createDirectory(
                at: shared.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try makeContainer(storeURL: shared)
        } catch {
            logger.error("Shared store migration failed; using legacy store: \(String(describing: error), privacy: .public)")
            return try makeContainer(storeURL: legacy)
        }
    }

    static func makeWidgetContainer(fileManager: FileManager = .default) throws -> ModelContainer {
        let shared = try sharedStoreURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: shared.path) else {
            throw SharedStoreError.validationFailed
        }
        return try makeContainer(storeURL: shared)
    }
}
```

Do not silently create an empty Widget database when migration has failed or the main app has never initialized shared storage.

- [ ] **Step 7: Commit shared persistence**

```bash
git add -- Viabar/System/SharedModelContainer.swift ViabarTests/ViabarTests.swift
git commit -m "feat: migrate viabar data into shared app group store"
```

### Task 4: Route The Main Application Through The Shared Store

**Files:**
- Modify: `Viabar/ViabarApp.swift`
- Modify: `Viabar/Viabar.entitlements`

- [ ] **Step 1: Add the App Group entitlement**

Add:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.tyrival.Viabar</string>
</array>
```

Keep existing sandbox, network, and user-selected-file entitlements intact.

- [ ] **Step 2: Replace inline Schema construction**

In `ViabarApp.init()`, replace the inline Schema and `ModelConfiguration` block with:

```swift
do {
    sharedModelContainer = try SharedModelContainer.makeMainAppContainer()
} catch {
    fatalError("Could not create ModelContainer: \(error)")
}
```

Do not change service registration, Settings bootstrap, main window, menu bar panel, or Settings scene wiring.

- [ ] **Step 3: Run static entitlement validation**

Run:

```bash
plutil -lint Viabar/Viabar.entitlements
git diff --check -- Viabar/ViabarApp.swift Viabar/Viabar.entitlements
```

Expected: `Viabar/Viabar.entitlements: OK` and no whitespace diagnostics.

- [ ] **Step 4: Commit main-app shared store wiring**

```bash
git add -- Viabar/ViabarApp.swift Viabar/Viabar.entitlements
git commit -m "feat: use shared app group model container"
```

### Task 5: Add Widget Project Configuration And Interactive Completion

**Files:**
- Create: `ViabarWidget/WidgetProjectIntent.swift`
- Create: `ViabarWidget/ToggleWidgetTaskIntent.swift`

- [ ] **Step 1: Add dynamic project entity query**

Create `WidgetProjectIntent.swift`:

```swift
import AppIntents
import SwiftData

struct WidgetProjectEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "项目")
    static var defaultQuery = WidgetProjectEntityQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct WidgetProjectEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetProjectEntity] {
        try fetchActiveProjects().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetProjectEntity] {
        try fetchActiveProjects()
    }

    private func fetchActiveProjects() throws -> [WidgetProjectEntity] {
        let container = try SharedModelContainer.makeWidgetContainer()
        let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
        return WidgetContentBuilder.activeProjects(from: projects).map {
            WidgetProjectEntity(id: $0.projectId, title: $0.title)
        }
    }
}

struct SelectWidgetProjectIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "选择项目"
    static var description = IntentDescription("选择桌面小组件要显示的项目")

    @Parameter(title: "项目")
    var project: WidgetProjectEntity?
}
```

The nullable parameter is intentional. Do not auto-select the first active project.

- [ ] **Step 2: Add interactive completion intent**

Create `ToggleWidgetTaskIntent.swift`:

```swift
import AppIntents
import SwiftData
import WidgetKit

struct ToggleWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "完成任务"
    static var openAppWhenRun = false

    @Parameter(title: "任务类型")
    var kind: String

    @Parameter(title: "任务 ID")
    var taskID: String

    init() {}

    init(kind: WidgetTaskKind, taskID: UUID) {
        self.kind = kind.rawValue
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let kind = WidgetTaskKind(rawValue: kind),
              let id = UUID(uuidString: taskID)
        else { return .result() }

        let container = try SharedModelContainer.makeWidgetContainer()
        let context = container.mainContext

        switch kind {
        case .milestone:
            let descriptor = FetchDescriptor<Milestone>(
                predicate: #Predicate { $0.milestoneId == id }
            )
            if let milestone = try context.fetch(descriptor).first {
                TaskCompletionMutation.toggle(milestone)
            }
        case .subTask:
            let descriptor = FetchDescriptor<SubTask>(
                predicate: #Predicate { $0.taskId == id }
            )
            if let subtask = try context.fetch(descriptor).first {
                TaskCompletionMutation.toggle(subtask)
            }
        }

        try context.save()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedModelContainer.widgetKind)
        return .result()
    }
}
```

- [ ] **Step 3: Inspect target-independent source dependencies**

Run:

```bash
rg -n "Sparkle|AppKit|ServiceContainer|NotificationScheduleService|BackupService" \
  Viabar/Models/Project.swift \
  Viabar/Models/AppSettings.swift \
  Viabar/Models/ReminderDisplay.swift \
  Viabar/Models/TaskCompletionMutation.swift \
  Viabar/Models/WidgetContent.swift \
  Viabar/System/SharedModelContainer.swift \
  Viabar/System/ViabarColor.swift \
  Viabar/Views/Component/Color+Hex.swift \
  Viabar/System/AppLanguageController.swift
```

Expected: no dependency on main-app-only services or Sparkle. `SwiftUI` imports used for localized keys and colors are acceptable.

- [ ] **Step 4: Commit Widget intents**

```bash
git add -- ViabarWidget/WidgetProjectIntent.swift ViabarWidget/ToggleWidgetTaskIntent.swift
git commit -m "feat: add desktop widget app intents"
```

### Task 6: Add Large Widget View, Empty States, And Localization

**Files:**
- Create: `ViabarWidget/ViabarWidgetBundle.swift`
- Create: `ViabarWidget/ViabarLargeWidget.swift`
- Create: `ViabarWidget/en.lproj/Localizable.strings`
- Create: `ViabarWidget/zh-Hans.lproj/Localizable.strings`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Create the Widget bundle**

Create `ViabarWidgetBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct ViabarWidgetBundle: WidgetBundle {
    var body: some Widget {
        ViabarLargeWidget()
    }
}
```

- [ ] **Step 2: Add provider states and timeline entry**

Create `ViabarLargeWidget.swift` with:

```swift
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

enum ViabarWidgetState {
    case needsProjectSelection
    case unavailableProject
    case unreadableData
    case content(WidgetProjectContent)
}

struct ViabarWidgetEntry: TimelineEntry {
    let date: Date
    let state: ViabarWidgetState
}

struct ViabarWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ViabarWidgetEntry {
        ViabarWidgetEntry(date: .now, state: .needsProjectSelection)
    }

    func snapshot(for configuration: SelectWidgetProjectIntent, in context: Context) async -> ViabarWidgetEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectWidgetProjectIntent, in context: Context) async -> Timeline<ViabarWidgetEntry> {
        let entry = entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    @MainActor
    private func entry(for configuration: SelectWidgetProjectIntent) -> ViabarWidgetEntry {
        guard let selectedID = configuration.project?.id else {
            return ViabarWidgetEntry(date: .now, state: .needsProjectSelection)
        }
        do {
            let container = try SharedModelContainer.makeWidgetContainer()
            let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
            guard let project = WidgetContentBuilder.activeProjects(from: projects)
                .first(where: { $0.projectId == selectedID })
            else {
                return ViabarWidgetEntry(date: .now, state: .unavailableProject)
            }
            return ViabarWidgetEntry(
                date: .now,
                state: .content(
                    WidgetContentBuilder.content(for: project, rowBudget: 8, now: .now)
                )
            )
        } catch {
            return ViabarWidgetEntry(date: .now, state: .unreadableData)
        }
    }
}
```

During implementation, tune `rowBudget` only by editing the explicit constant after visual validation. Preserve the projection behavior: ordered prefix only, no font shrinking to force extra rows.

- [ ] **Step 3: Add the configured Large Widget**

Add:

```swift
struct ViabarLargeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SharedModelContainer.widgetKind,
            intent: SelectWidgetProjectIntent.self,
            provider: ViabarWidgetProvider()
        ) { entry in
            ViabarLargeWidgetView(entry: entry)
        }
        .configurationDisplayName("Viabar 项目")
        .description("在桌面查看并完成项目任务")
        .supportedFamilies([.systemLarge])
    }
}
```

- [ ] **Step 4: Render the confirmed compact layout**

Implement `ViabarLargeWidgetView` with these exact boundaries:

```swift
struct ViabarLargeWidgetView: View {
    let entry: ViabarWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .needsProjectSelection:
                emptyState("请选择项目", detail: "右键小组件 > 编辑小组件")
            case .unavailableProject:
                emptyState("项目不可用，请重新选择项目", detail: "右键小组件 > 编辑小组件")
            case .unreadableData:
                emptyState("暂时无法读取数据", detail: nil)
            case .content(let content):
                contentView(content)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}
```

Build `contentView(_:)` as:

- one compact header row;
- SF Symbol and bold project title at task-body scale;
- right-aligned short progress track and percentage;
- flattened unfinished task prefix;
- indented subtasks without parent subtitles;
- `Button(intent:)` checkboxes using `ToggleWidgetTaskIntent`;
- reminder second line only when `reminderDate != nil`;
- reminder style `.red` for `.overdue`, `.orange` for `.todayPending`, `.secondary` for `.future`;
- footer `还有 %lld 项未完成` only when `hiddenItemCount > 0`;
- completed project empty text `当前没有未完成任务` when `visibleItems` and hidden count are both empty.

Use this button shape:

```swift
Button(intent: ToggleWidgetTaskIntent(kind: item.kind, taskID: item.id)) {
    Image(systemName: "circle")
        .font(.system(size: 14))
}
.buttonStyle(.plain)
```

- [ ] **Step 5: Add bilingual Widget copy**

Add to both Widget Extension localization files, translating the right-hand values in `en.lproj` and preserving Chinese in `zh-Hans.lproj`:

```text
"Viabar 项目" = "Viabar Project";
"在桌面查看并完成项目任务" = "View and complete project tasks from your desktop";
"选择项目" = "Choose Project";
"选择桌面小组件要显示的项目" = "Choose the project to show in this desktop widget";
"项目" = "Project";
"完成任务" = "Complete Task";
"任务类型" = "Task Type";
"任务 ID" = "Task ID";
"请选择项目" = "Choose a project";
"右键小组件 > 编辑小组件" = "Right-click the widget > Edit Widget";
"项目不可用，请重新选择项目" = "Project unavailable. Choose another project";
"暂时无法读取数据" = "Unable to read data right now";
"当前没有未完成任务" = "No unfinished tasks";
"还有 %lld 项未完成" = "%lld more unfinished tasks";
```

Append the same keys to the main-target localization files as well. Shared source code must not depend on which bundle initiated the lookup. Keep Widget-specific resources in the extension in all cases.

- [ ] **Step 6: Commit the Widget view**

```bash
git add -- ViabarWidget/ViabarWidgetBundle.swift ViabarWidget/ViabarLargeWidget.swift ViabarWidget/en.lproj/Localizable.strings ViabarWidget/zh-Hans.lproj/Localizable.strings Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add large desktop widget view"
```

### Task 7: Add Widget Extension Target And Perform Static Verification

**Files:**
- Create: `ViabarWidget/ViabarWidget.entitlements`
- Modify: `Viabar.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add Widget Extension entitlements**

Create:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.tyrival.Viabar</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Add the Widget Extension target in Xcode project metadata**

Update `project.pbxproj` so the project contains:

- a `ViabarWidgetExtension.appex` product reference;
- a `ViabarWidget` file-system synchronized root group;
- a `PBXNativeTarget` with product type `com.apple.product-type.app-extension`;
- Sources, Frameworks, and Resources phases for the Widget target;
- an app `Embed Foundation Extensions` copy phase containing the Widget product with `CodeSignOnCopy` and `RemoveHeadersOnCopy`;
- an app target dependency on the Widget target;
- Debug and Release build configurations for bundle identifier `com.tyrival.Viabar.Widget`;
- `CODE_SIGN_ENTITLEMENTS = ViabarWidget/ViabarWidget.entitlements`;
- `GENERATE_INFOPLIST_FILE = YES`;
- `INFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier = "com.apple.widgetkit-extension"`;
- `SKIP_INSTALL = YES`;
- the same deployment target and Swift language settings as the main app;
- target membership for the shared source files listed under **Shared Target Membership**.

Use Xcode’s Widget Extension template metadata as the reference when editing project configuration. Do not add Sparkle to the Widget target.

- [ ] **Step 3: Validate project metadata without compiling**

Run:

```bash
plutil -lint Viabar/Viabar.entitlements ViabarWidget/ViabarWidget.entitlements
rg -n "ViabarWidget|com\\.apple\\.widgetkit-extension|group\\.com\\.tyrival\\.Viabar|Embed Foundation Extensions|com\\.tyrival\\.Viabar\\.Widget" \
  Viabar.xcodeproj/project.pbxproj \
  Viabar/Viabar.entitlements \
  ViabarWidget/ViabarWidget.entitlements
git diff --check
git status --short
```

Expected:

- both entitlement files report `OK`;
- the project file contains the Widget Extension product, extension point, embed phase, dependency, and bundle identifier;
- both entitlement files contain `group.com.tyrival.Viabar`;
- `git diff --check` prints no whitespace errors;
- `build/DerivedData/SourcePackages/` remains untouched.

- [ ] **Step 4: Inspect configuration semantics**

Run:

```bash
rg -n "AppIntentConfiguration|WidgetConfigurationIntent|supportedFamilies|systemLarge|StaticConfiguration|isArchived|reloadTimelines|cloudKitDatabase|\\.none" \
  Viabar ViabarWidget ViabarTests
```

Expected:

- `AppIntentConfiguration` and `WidgetConfigurationIntent` are present;
- `.supportedFamilies([.systemLarge])` is present;
- no Widget uses `StaticConfiguration`;
- project query filters archived projects;
- completion intent reloads the Widget timeline;
- production shared configuration explicitly disables CloudKit for this release.

- [ ] **Step 5: Commit project wiring**

```bash
git add -- ViabarWidget/ViabarWidget.entitlements Viabar.xcodeproj/project.pbxproj
git commit -m "build: add viabar widget extension target"
```

- [ ] **Step 6: Pause before any compile or desktop installation**

Ask the user for explicit authorization before running any of:

```bash
xcodebuild -list -project Viabar.xcodeproj
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests
xcodebuild -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' build
```

Without authorization, report that implementation has passed static verification only.

- [ ] **Step 7: After authorization, run manual desktop Widget verification**

Build and launch the app, then verify:

1. Existing projects, settings, reminders, templates, and archive data remain present after App Group migration.
2. The Widget gallery exposes the Viabar Large Widget.
3. The newly added Widget starts in the unselected empty state.
4. Desktop right-click exposes the system `Edit Widget` action.
5. Edit Widget lists only active projects.
6. Selecting a project updates the compact header, progress, task list, and overflow count.
7. Overdue reminders are red, pending-today reminders orange, and future reminders gray.
8. Clicking a parent task completes its children, removes completed rows, and fills the available space with later tasks.
9. Clicking the last unfinished child completes its parent and refreshes immediately.
10. Archiving or deleting the configured project changes the Widget to the unavailable-project state.

If `Edit Widget` is absent despite correct `AppIntentConfiguration`, record the installed macOS version and test a clean Widget removal/re-add before treating the behavior as a system regression.
