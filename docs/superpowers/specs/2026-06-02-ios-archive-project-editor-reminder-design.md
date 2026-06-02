# iOS Archive, Project Editor, and Reminder Design

## Goal

Extend the iOS app with archive-folder selection, archived-project relocation, full-row global-search navigation, a shared create/edit project form, and explicit-save reminder editing for projects, milestones, and subtasks.

## Constraints

- Reuse the shared App Group main store and existing SwiftData models.
- Reuse `ProjectService`, `Reminder`, `NotificationScheduleEntry`, and `NotificationScheduleService`.
- Do not add, remove, or modify persisted model fields.
- Keep archived project details read-only.
- Keep project templates available only while creating a project.
- Preserve Widget access to the same shared main store.

## Archive Folder Selection

### Active Project Archive

Archiving an active project must open an iOS archive-folder picker sheet instead of selecting the first root folder automatically.

The picker:

- Displays existing archive folders as a multi-level tree.
- Allows selection of any existing folder.
- Does not create folders.
- Shows an empty state when no archive folders exist and directs the user to create one from the archive page.
- Enables the confirmation button only after a folder is selected.

On confirmation, call:

```swift
projectService.archiveProject(project, to: selectedFolder)
```

### Archived Project Relocation

The archived-project context menu adds `移动至...`.

It opens the same folder picker. The current folder remains visible but cannot be submitted again. On confirmation, call:

```swift
projectService.moveProjectToFolder(project, folder: selectedFolder)
```

The existing archive tree remains lazily rendered with `LazyVStack`.

## Global Search Hit Testing

Every global-search result row must navigate when the user taps its icon, text, or trailing empty space.

The result button label must fill the available width and apply:

```swift
.contentShape(Rectangle())
```

Navigation continues to use `IOSPersistenceCoordinator.navigate(to:)`, archive-ancestor expansion, and the existing one-shot highlight path.

## Shared iOS Project Form

Replace the iOS create-only form with a shared create/edit form.

### Shared Fields

Both create and edit modes contain:

- Project name
- Project-level reminder button aligned to the right of the name field
- SF Symbol selection
- Accent color selection

### Create Mode

Create mode additionally contains:

- Template selection

Submitting creates a project through the existing service, applies the selected symbol, color, and copied reminder draft, then calls `updateProject`.

### Edit Mode

Edit mode:

- Loads title, symbol, color, and a copied reminder draft from the selected project.
- Does not show template selection.
- Updates the existing project only after the user taps Save.

The overview-card context-menu Edit action opens this form instead of the bottom title composer.

### Layout

The form uses content-driven compact layout. It must avoid fixed excessive vertical space and keep actions reachable near the form content. Edit mode is naturally shorter because it excludes template selection.

## iOS Reminder Editor

Create an iOS-specific reminder sheet. Do not reuse the macOS popover lifecycle because the macOS implementation commits on disappearance.

### Fields

The reminder editor mirrors the macOS reminder configuration:

- Date
- Time
- Repeat option

It loads an existing reminder into local draft state. Changing controls must not mutate the model or timeline.

### Toolbar Actions

- Top-left red Delete: immediately submits `nil` to the editor's callback and closes the sheet. Disable it when no reminder exists.
- Top-right Save: builds a new `Reminder`, submits it to the editor's callback, and closes the sheet.
- Interactive dismissal or navigation dismissal: discard draft changes.

The callback determines when the timeline changes:

- Project-form callback: update only the local form draft.
- Milestone or subtask callback: call `ProjectService.updateReminder`, which synchronizes the timeline immediately.

### Project Reminder

The project form owns a local project-reminder draft. Saving or deleting inside the reminder sheet updates only the form draft. The project model and timeline change only when the entire project form is submitted.

This matches form semantics: canceling the project form discards edits to title, symbol, color, and project reminder together.

### Milestone and Subtask Reminders

Active project details show an alarm button for each milestone and subtask.

- Save calls `ProjectService.updateReminder(_:for:)`.
- Delete calls the same service method with `nil`.
- Existing `NotificationScheduleService` logic updates timeline entries.

Archived project details display reminder status but expose no reminder editing controls.

## Read-Only Archive Detail

Archived project detail continues to allow:

- Viewing tasks, subtasks, and memos
- Copying task, subtask, and memo text
- Switching task and memo tabs
- Unarchiving the project

It must not allow:

- Adding, editing, deleting, or completing tasks and subtasks
- Adding, editing, or deleting memos
- Editing reminders
- Starring or unstarring the project
- Mutating hide-completed state

## Localization

Add every new user-visible string to:

- `ViabariOS/en.lproj/Localizable.strings`
- `ViabariOS/zh-Hans.lproj/Localizable.strings`

Required additions include archive-picker titles, empty states, `移动至...`, reminder-editor labels, and Save/Delete actions where missing.

## Data and Widget Compatibility

This feature requires no SwiftData schema migration.

The existing shared persistence remains unchanged:

```text
group.com.tyrival.Viabar
ViabarSharedStore/default.store
```

`Reminder` remains the configuration model. `NotificationScheduleEntry` remains rebuildable runtime timeline state. Widget timelines continue to reload through existing `ProjectService.save()` behavior.

## Static Verification

Without compiling unless explicitly requested:

```bash
git diff --check
plutil -lint ViabariOS/Info.plist Viabar.xcodeproj/project.pbxproj
plutil -lint ViabariOS/en.lproj/Localizable.strings ViabariOS/zh-Hans.lproj/Localizable.strings
rg -n "@Model|Schema\\(|ModelContainer|ModelConfiguration" Viabar ViabarWidget ViabarTests --glob '*.swift'
rg -n "legacyStoreURL|applicationSupportDirectory|default\\.store|trash\\.store|ViabarSharedStore|cloudKitDatabase" Viabar ViabarWidget ViabarTests --glob '*.swift'
rg -n "BackupSnapshot|BackupSettingsSnapshot|decodeIfPresent|init\\(from decoder" Viabar ViabarTests --glob '*.swift'
```

Manual verification after the user builds:

1. Archive an active project into a nested folder.
2. Move an archived project to a different nested folder.
3. Tap the trailing empty area of a global-search result row.
4. Edit an existing project's title, icon, color, and reminder.
5. Confirm create mode shows templates and edit mode does not.
6. Confirm the project form is compact without excessive bottom whitespace.
7. Save and delete milestone and subtask reminders.
8. Dismiss a reminder editor without saving and confirm timeline state is unchanged.
9. Open archived detail and confirm every mutation path remains unavailable.
