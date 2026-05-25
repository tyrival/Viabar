# Backup, Restore, And Retention Design

## Goal

Turn the saved Data Backup preferences into a working, local snapshot system
for Viabar. Users can create a backup immediately, browse stored backups,
restore the entire application state after two confirmations, and enable
automatic in-process backups with tiered history retention.

This design extends:

- `2026-05-24-settings-swiftdata-date-format-design.md`;
- `2026-05-25-settings-runtime-behaviors-localization-search-overlay-design.md`.

## Confirmed Product Decisions

- Backup lives in `设置 > 数据 > 数据备份`.
- Add a `Backup` row after the backup-path row, with `立即备份` and
  `浏览备份` buttons.
- Each backup is a complete recoverable snapshot, not a partial export.
- Restore replaces the current recoverable database state after two destructive
  confirmations; it does not merge with current data.
- A backup contains project templates, but it does not contain
  `NotificationScheduleEntry` records.
- After restore, notification schedule entries are rebuilt from the restored
  reminder configuration.
- The on-disk format is one UTF-8 `backup.json` file inside a ZIP container
  whose extension is `.viabackup`.
- Automatic backups run only while Viabar is running and Data Backup is
  enabled.
- History is retained in tiers: hourly for 24 hours, daily for 7 days, weekly
  for 6 months, then removed.
- The data panel displays a short backup-policy explanation and the latest
  backup timestamp beneath the controls.
- English and Simplified Chinese copy are supplied through the existing live
  localization system.
- Source work and static verification proceed without compiling unless the user
  explicitly authorizes a build or test run.

## Settings Layout

The Data panel keeps the existing `数据同步` group separately from the backup
feature. The `数据备份` group contains:

1. `启用`, bound to the existing `AppSettings.backupEnabled` setting.
2. `备份路径`, bound to `AppSettings.backupPath`, with its folder-picker
   action.
3. `Backup`, containing two small actions:
   - `立即备份`;
   - `浏览备份`.

Below the groups, place a secondary-text explanation panel following the visual
reference. It reads, in Simplified Chinese:

```text
Viabar 自动保存各级备份

• 过去 24 小时每小时备份
• 过去 7 天每天备份
• 过去 6 个月每周备份

最新备份：今天 21:19
```

The product name is `Viabar`, rather than the app name shown in the provided
reference. The latest-backup line uses the most recent valid backup file under
the selected backup path. When no valid backup exists, show `最新备份：暂无备份`.
In English, use concise equivalent copy:

```text
Viabar keeps backups automatically

• Hourly backups for the past 24 hours
• Daily backups for the past 7 days
• Weekly backups for the past 6 months

Latest backup: Today 21:19
```

## Backup Snapshot Format

Each file is named with its creation time in a stable sortable format:

```text
yyyyMMdd-HHmmss.viabackup
```

For example:

```text
20260525-213000.viabackup
```

The file is a ZIP container with exactly one required entry:

```text
backup.json
```

`backup.json` is an UTF-8 JSON document containing:

- `formatVersion`, initially `1`;
- `createdAt`, encoded as an ISO-8601 timestamp;
- an app-settings snapshot;
- archive-folder hierarchy;
- all active and archived projects;
- each project's milestones, subtasks, memos, reminder configuration, ordering,
  favorite/archive/style fields, and archive-folder relationship;
- all project templates and their template milestone/subtask structures.

The snapshot does not contain transient UI state, runtime shortcut
registration, application windows, or `NotificationScheduleEntry` records.

## Entity Boundaries

### Included

- `AppSettings`, as the application's single persisted personal-settings
  record;
- `ArchiveFolder` hierarchy;
- `Project`, including active and archived projects;
- `Milestone`;
- `SubTask`;
- `Memo`;
- stored `Reminder` configuration attached to projects, milestones, and
  subtasks;
- `ProjectTemplate`;
- `TemplateMilestone`;
- `TemplateSubTask`.

### Excluded And Rebuilt

`NotificationScheduleEntry` is excluded because it is a derived active
notification time axis rather than the user's reminder intent. After a restore,
delete existing schedule entries and recreate applicable ones from the restored
project, milestone, and subtask reminder configuration through the scheduling
service's existing sync boundaries.

## Manual Backup Creation

When the user presses `立即备份`:

1. Resolve `backupPath`, expanding the stored home-directory shorthand where
   applicable, and create the directory if it does not yet exist.
2. Read the current SwiftData entities on the main data boundary and convert
   them into a versioned `BackupSnapshot`.
3. Serialize one UTF-8 `backup.json` file.
4. Package it into a temporary ZIP archive.
5. Move it atomically into `backupPath` with a timestamp `.viabackup` file
   name.
6. Re-scan valid backups, update the latest-backup summary, and run retention
   cleanup.

If serialization, packaging, or writing fails, no partial backup is shown as a
valid restore candidate and the Settings window presents a localized error.

## Backup Browser Window

`浏览备份` presents a dedicated window or sheet associated with Settings. It
reads only valid `.viabackup` files in the current `backupPath` and displays
them newest first.

The visible list follows the provided reference:

- header text: `可用的备份：`;
- one row per valid backup;
- a date column and time column;
- the first row for a given calendar date displays the localized date;
- following rows on the same date omit the repeated date while still showing
  their time;
- today's date is displayed as `今天` / `Today`;
- selection is single-choice;
- a `恢复` / `Restore` button at bottom right is disabled until one file is
  selected.

The list derives timestamps from the validated backup filename and rejects
unrecognized, malformed, or unsupported archive files from restore selection.

## Full Restore Flow

Restore is deliberately destructive and atomic at the product level:

1. The user selects one backup and presses `恢复`.
2. Show the first localized warning: restoring will replace all current
   projects, archive data, templates, reminders, and personal settings.
3. After confirmation, show a second localized warning: the operation cannot
   be undone except by restoring another backup.
4. Only after the second confirmation, decode and validate `backup.json`
   completely, including `formatVersion`, before deleting current data.
5. Replace all included entities with the selected snapshot.
6. Delete existing `NotificationScheduleEntry` entities and rebuild active
   schedule entries from restored reminder configuration.
7. Save the imported state, refresh Settings/app-visible state, and report a
   localized success or failure result.

A missing/corrupt file, unsupported format version, or validation error must
leave the current database unchanged and display an error. The implementation
must validate before beginning destructive replacement.

## Automatic Backup And Retention

An application-lifetime `BackupService` observes the persisted
`backupEnabled`/`backupPath` settings. It does not run after Viabar exits and
does not introduce a helper process or launch agent.

When enabled:

- configure a one-hour repeating in-process timer;
- on startup or enablement, perform an eligibility check and avoid creating
  multiple backups within the same hourly bucket;
- after each created backup, apply retention cleanup to valid backup files in
  the configured path.

Retention groups backup timestamps from newest to oldest:

| Age From Now | Retention |
| --- | --- |
| Up to 24 hours | Keep at most one latest backup per hour |
| More than 24 hours through 7 days | Keep at most one latest backup per calendar day |
| More than 7 days through 6 months | Keep at most one latest backup per calendar week |
| Older than 6 months | Delete |

Manual backups participate in the same retention set. Therefore a manual
backup may be retained as the latest snapshot for its hourly, daily, or weekly
bucket, and redundant older snapshots in that bucket may be removed during the
next cleanup.

## Code Boundaries

- `Viabar/Models/BackupSnapshot.swift`: Codable snapshot DTOs, format version,
  and mappings needed to represent every included persisted entity.
- `Viabar/Services/BackupService.swift`: snapshot creation, ZIP read/write,
  valid-file discovery, latest backup lookup, restore transaction orchestration,
  scheduler ownership, and retention cleanup.
- `Viabar/Models/AppSettings.swift`: retain existing backup enable/path
  settings; add only state strictly needed for scheduling if required by the
  implementation plan.
- `Viabar/Services/NotificationScheduleService.swift`: expose or reuse focused
  synchronization entry points for rebuilding derived schedule entries after
  restore.
- `Viabar/ViabarApp.swift`: construct/register the backup service beside the
  existing project and notification services, and start its app-lifetime
  observation.
- `Viabar/Views/Settings/SettingsView.swift`: add manual/browse actions, status
  summary, errors, and backup policy explanatory copy.
- `Viabar/Views/Settings/BackupBrowserView.swift`: show sorted available
  backups, selection, restore button, and two confirmation alerts.
- `Viabar/en.lproj/Localizable.strings` and
  `Viabar/zh-Hans.lproj/Localizable.strings`: all new backup and restore UI
  copy.
- `ViabarTests/ViabarTests.swift`: source-level behavioral tests for snapshot
  mapping, filename parsing/order, retention selection, and restore semantics.

## Failure Handling

- A path that cannot be created or written shows a localized backup error.
- A malformed `.viabackup` file is excluded from valid candidates, or surfaces
  a clear localized error if it changes between listing and restore.
- Restore never begins entity deletion until the selected archive has been
  completely decoded and validated.
- If replacement fails while saving, present a failure rather than claiming
  restoration succeeded; the implementation plan must use the safest available
  SwiftData operation ordering for replacement.
- Deleting an old backup file during retention is best-effort per file: a
  failure is reported without invalidating a newly created backup.

## Verification

Author test definitions first for:

- encoding and decoding one representative complete snapshot including
  archived projects, nested folders, reminders, templates, and settings;
- parsing valid `.viabackup` names, excluding malformed candidates, and sorting
  newest first;
- retention selection across hourly, daily, weekly, and expired time bands;
- restoring snapshot entities while omitting and rebuilding
  `NotificationScheduleEntry` records;
- localized latest-backup date/time presentation boundary where pure helpers
  make it testable.

By repository instruction, do not compile, run tests, or launch the app unless
the user explicitly requests compilation. During implementation, verification
will therefore be limited to source inspection, `git diff --check`, and
relevant resource-file validation; executable proof remains pending explicit
authorization.
