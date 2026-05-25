# Backup, Restore, And Retention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complete local `.viabackup` export, browsing, full restore, and in-process tiered automatic retention from the Data settings panel.

**Architecture:** Introduce versioned Codable snapshot types and a main-actor `BackupService` that owns SwiftData mapping, `ditto` ZIP packaging, candidate discovery, restore replacement, scheduling, and retention. Settings renders controls and summary state, while a focused browser view handles selection and the two restore confirmations; notification timeline records remain derived and are rebuilt after import.

**Tech Stack:** SwiftUI, SwiftData, Foundation `Process` with macOS `/usr/bin/ditto`, Codable JSON, Swift Testing.

**Repository Constraint:** Do not run `xcodebuild`, Swift tests, previews, or the application unless the user explicitly authorizes compilation. Author test sources before production code, then use `git diff --check` and resource linting as the available verification.

---

## File Map

- Create `Viabar/Models/BackupSnapshot.swift`: versioned Codable entity DTOs, file-name parsing, display date formatting, and retention decisions.
- Create `Viabar/Services/BackupService.swift`: database export/import, ZIP archive I/O, discovery, automatic timer, retention cleanup, and error/status publication.
- Modify `Viabar/Services/NotificationScheduleService.swift`: add a public full timeline rebuild operation after restore.
- Modify `Viabar/Services/ProjectService.swift`: expose a refresh/rebuild boundary only if restore needs it; do not place backup I/O here.
- Modify `Viabar/ViabarApp.swift`: register and start `BackupService`.
- Create `Viabar/Views/Settings/BackupBrowserView.swift`: backup list, selection, restore action, and two destructive confirmations.
- Modify `Viabar/Views/Settings/SettingsView.swift`: add Backup action row, backup policy summary, service wiring, and localized failure reporting.
- Modify `Viabar/en.lproj/Localizable.strings` and `Viabar/zh-Hans.lproj/Localizable.strings`: backup UI, warnings, and status text.
- Modify `ViabarTests/ViabarTests.swift`: pure behavior expectations for filename parsing, retention, snapshot round-trip, and imported entity semantics.

### Task 1: Specify Snapshot And Retention Rules In Tests

**Files:**
- Modify: `ViabarTests/ViabarTests.swift`
- Create: `Viabar/Models/BackupSnapshot.swift`

- [ ] **Step 1: Add source-first expectations for backup filenames and retention**

Add tests that exercise the intended pure API before implementation:

```swift
struct BackupMetadataTests {
    @Test func parsesAndSortsBackupFilesNewestFirst() throws {
        let older = try #require(BackupFileMetadata(url: URL(fileURLWithPath: "/tmp/20260524-101000.viabackup")))
        let newer = try #require(BackupFileMetadata(url: URL(fileURLWithPath: "/tmp/20260525-211900.viabackup")))
        #expect(BackupFileMetadata.sortedNewestFirst([older, newer]).map(\.url.lastPathComponent) == [
            "20260525-211900.viabackup",
            "20260524-101000.viabackup",
        ])
        #expect(BackupFileMetadata(url: URL(fileURLWithPath: "/tmp/not-a-backup.viabackup")) == nil)
    }

    @Test func retainsHourlyDailyWeeklyAndDeletesExpiredBackups() {
        let now = ISO8601DateFormatter().date(from: "2026-05-25T13:00:00Z")!
        let dates = [
            "2026-05-25T12:00:00Z", "2026-05-25T12:15:00Z",
            "2026-05-23T10:00:00Z", "2026-05-23T11:00:00Z",
            "2026-05-04T09:00:00Z", "2026-05-05T09:00:00Z",
            "2025-10-01T09:00:00Z",
        ].compactMap(ISO8601DateFormatter().date(from:))
        let result = BackupRetentionPolicy.urlsToDelete(from: dates.map(BackupFileMetadata.stub), now: now)
        #expect(result.count == 4)
    }
}
```

- [ ] **Step 2: Add a representative snapshot round-trip contract**

```swift
@Test func roundTripsVersionedBackupSnapshot() throws {
    let snapshot = BackupSnapshot(
        formatVersion: 1,
        createdAt: Date(timeIntervalSince1970: 0),
        settings: BackupSettingsSnapshot(backupEnabled: true, backupPath: "~/Documents/Viabar"),
        folders: [],
        projects: [],
        templates: []
    )
    let encoded = try JSONEncoder.backupEncoder.encode(snapshot)
    #expect(try JSONDecoder.backupDecoder.decode(BackupSnapshot.self, from: encoded) == snapshot)
}
```

- [ ] **Step 3: Record the intentionally unavailable red verification**

Do not run test commands because the user explicitly prohibited compilation. Keep these expectations source-authored and report them as unexecuted.

- [ ] **Step 4: Implement pure Codable/metadata types**

Create snapshot structs that model every persisted included field:

```swift
struct BackupSnapshot: Codable, Equatable {
    static let currentFormatVersion = 1
    let formatVersion: Int
    let createdAt: Date
    let settings: BackupSettingsSnapshot
    let folders: [BackupFolderSnapshot]
    let projects: [BackupProjectSnapshot]
    let templates: [BackupTemplateSnapshot]
}

struct BackupFileMetadata: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    var id: URL { url }
    init?(url: URL)
    static func sortedNewestFirst(_ files: [BackupFileMetadata]) -> [BackupFileMetadata]
}

enum BackupRetentionPolicy {
    static func urlsToDelete(from files: [BackupFileMetadata], now: Date, calendar: Calendar = .current) -> Set<URL>
}
```

Include DTOs for settings, folders (`folderId`, `parentId`), projects
(`archiveFolderId`, nested memos/tasks/reminders), templates, and reminder
fields. Use `JSONEncoder` / `JSONDecoder` extensions configured with ISO-8601
date encoding.

### Task 2: Implement Backup File And Database Service

**Files:**
- Create: `Viabar/Services/BackupService.swift`
- Modify: `Viabar/Services/NotificationScheduleService.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Add source tests describing import exclusion of notification entries**

```swift
@Test func restoreRebuildsDerivedTimelineInsteadOfImportingEntries() throws {
    let snapshot = makeSnapshotWithProjectReminder()
    let (service, context) = try makeBackupService()
    try service.restore(snapshot: snapshot)
    #expect((try context.fetch(FetchDescriptor<Project>())).map(\.title) == ["Recovered"])
    #expect((try context.fetch(FetchDescriptor<NotificationScheduleEntry>())).count == 1)
}
```

Do not execute it under the no-compile instruction.

- [ ] **Step 2: Implement `BackupService` state and discovery**

Use one observable main-actor service:

```swift
@MainActor
@Observable
final class BackupService {
    private let modelContext: ModelContext
    private let notificationScheduleService: NotificationScheduleService
    private var timer: Timer?
    private(set) var availableBackups: [BackupFileMetadata] = []
    private(set) var latestBackup: BackupFileMetadata?

    func refreshBackups(path: String) throws
    func createBackup(settings: AppSettings, now: Date = Date()) throws -> BackupFileMetadata
    func restore(file: BackupFileMetadata) throws
    func setAutomaticBackupEnabled(_ enabled: Bool, settings: AppSettings)
}
```

Resolve `~/` in `backupPath`, list files with extension `viabackup`, parse only
valid timestamp filenames, sort newest-first, and publish `latestBackup`.

- [ ] **Step 3: Implement ZIP write/read through `/usr/bin/ditto`**

For backup creation:

```swift
try data.write(to: payloadURL, options: .atomic)
try runDitto(["-c", "-k", "--sequesterRsrc", "--keepParent", payloadURL.path, zipURL.path])
try fileManager.moveItem(at: zipURL, to: finalURL)
```

For reading, extract into a unique temporary directory with:

```swift
try runDitto(["-x", "-k", archiveURL.path, extractionDirectory.path])
let payloadURL = extractionDirectory.appendingPathComponent("backup.json")
```

The service must remove temporary directories with `defer`, reject missing
`backup.json`, reject unsupported `formatVersion`, and keep failed partial
archives out of the backup directory.

- [ ] **Step 4: Implement snapshot export and destructive restore**

Fetch every included SwiftData type and map it into `BackupSnapshot`. For
restore, decode/validate before deletion; then delete `NotificationScheduleEntry`,
templates, archive folders and projects (letting cascade relationships remove
nested entities), replace `AppSettings` fields from the snapshot, recreate
folders, templates, projects and nested items with preserved UUID fields, save,
and invoke timeline rebuild.

- [ ] **Step 5: Add notification timeline rebuild boundary**

In `NotificationScheduleService` expose:

```swift
func rebuildTimeline(from projects: [Project]) {
    allEntries().forEach { modelContext.delete($0) }
    save()
    for project in projects where !project.isArchived {
        syncProject(project)
        for milestone in project.milestones {
            syncMilestone(milestone, project: project)
            for subTask in milestone.subtasks {
                syncSubTask(subTask, project: project)
            }
        }
    }
}
```

### Task 3: Add Automatic Scheduling And Tiered Cleanup

**Files:**
- Modify: `Viabar/Services/BackupService.swift`
- Modify: `Viabar/ViabarApp.swift`
- Test: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Implement retention cleanup using the tested pure policy**

After each successful manual or automatic backup:

```swift
let expiredURLs = BackupRetentionPolicy.urlsToDelete(from: availableBackups, now: now)
for url in expiredURLs {
    try fileManager.removeItem(at: url)
}
try refreshBackups(path: settings.backupPath)
```

Use one latest item per hourly/day/week calendar bucket and delete files older
than six calendar months.

- [ ] **Step 2: Add in-process automatic timer**

```swift
func start(settings: AppSettings) {
    setAutomaticBackupEnabled(settings.backupEnabled, settings: settings)
}

func setAutomaticBackupEnabled(_ enabled: Bool, settings: AppSettings) {
    timer?.invalidate()
    timer = nil
    guard enabled else { return }
    createAutomaticBackupIfNeeded(settings: settings)
    timer = .scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
        Task { @MainActor in
            self?.createAutomaticBackupIfNeeded(settings: settings)
        }
    }
}
```

`createAutomaticBackupIfNeeded` skips creation when `latestBackup` already
falls within the current hourly bucket.

- [ ] **Step 3: Register service during app startup**

Create/register `BackupService` after `NotificationScheduleService` in
`ViabarApp.init()`, add a `ServiceContainer.backupService` accessor, and start
the automatic service from the main window task using the shared settings
record.

### Task 4: Build Settings And Backup Browser UI

**Files:**
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Create: `Viabar/Views/Settings/BackupBrowserView.swift`
- Modify: `Viabar/en.lproj/Localizable.strings`
- Modify: `Viabar/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add actions and policy summary in the Data panel**

Inject `ServiceContainer`, track browser presentation and error state, and
render:

```swift
SettingsRow("Backup") {
    HStack(spacing: 8) {
        Button("立即备份") { createBackup() }
        Button("浏览备份") { showBackupBrowser = true }
    }
    .controlSize(.small)
}

BackupPolicySummaryView(latestBackup: backupService?.latestBackup)
```

The summary displays the confirmed three retention lines plus localized latest
timestamp/no-backup copy. Reconfigure automatic backup when the enable toggle
or backup path changes.

- [ ] **Step 2: Create backup browser list and confirmation flow**

`BackupBrowserView` receives `BackupService` and `AppSettings`, refreshes
candidates on appear, renders a two-column newest-first list grouped visually
by repeated day label, enables `恢复` only when selected, and uses two chained
alerts before invoking restore.

```swift
.alert("恢复当前备份？", isPresented: $showsFirstWarning) { ... }
.alert("再次确认恢复", isPresented: $showsFinalWarning) { ... }
```

- [ ] **Step 3: Add localization resources**

Add matched English/Simplified-Chinese keys for `Backup`, buttons, policy
summary, available-backups heading, restore warnings, status/errors and
latest-backup formatting. Keep the `iCloud` resource already introduced by the
preceding Settings cleanup.

### Task 5: Static Verification Under No-Compile Constraint

**Files:**
- Inspect all modified and added files.

- [ ] **Step 1: Confirm source formatting and resource validity**

Run:

```bash
git diff --check
plutil -lint Viabar/en.lproj/Localizable.strings Viabar/zh-Hans.lproj/Localizable.strings
```

Expected: no whitespace errors and both resource files report `OK`.

- [ ] **Step 2: Confirm paired localization keys and required backup symbols**

Run key-set comparison and focused `rg` checks for:

```text
BackupService
BackupSnapshot
backup.json
viabackup
rebuildTimeline
立即备份
浏览备份
恢复
过去 24 小时每小时备份
```

Expected: English and Simplified-Chinese resource key sets match and every
required implementation boundary is present.

- [ ] **Step 3: Report non-executed verification explicitly**

Do not claim builds or tests pass. State that the test sources were authored
before implementation but not executed because compilation was not authorized.
