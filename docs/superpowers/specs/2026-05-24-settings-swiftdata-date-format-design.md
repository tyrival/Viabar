# Settings Window, SwiftData Preferences, And Date Format Design

## Goal

Add a native macOS Settings window reached from the application menu, with a
sidebar of settings categories and a detail panel. Persist all configurable
settings in SwiftData as one app settings record so that a future macOS/iOS
sync implementation can use the same data model. In this change, only the
selected date format affects existing product behavior.

## Scope

This change includes:

- a native `Settings` scene that exposes the system application-menu Settings
  command;
- a sidebar-detail settings window with five categories: General, Display,
  Shortcuts, Sync & Backup, and About;
- a single persisted SwiftData `AppSettings` record with initial defaults for
  every configurable settings item;
- editable setting controls that save their selected values;
- one shared date formatting path applied to overview reminder timestamps,
  milestone-list reminder timestamps, and memo-card timestamps.

This change does not include:

- a system menu bar status-item component or `MenuBarExtra`;
- launch-at-login behavior;
- menu bar component behavior;
- applying theme or language changes to the application UI;
- changing overview filtering behavior or weekday filtering behavior;
- registering or remapping keyboard shortcuts;
- data sync, backup, import, or export execution;
- external navigation for Telegram, App Store rating, licenses, or agreements;
- any change to reminder scheduling, repeat processing, notifications, or
  persisted notification timeline behavior.

## Entry Point And Window Layout

Add a SwiftUI `Settings` scene in `ViabarApp`. macOS then presents the standard
Settings command in the top application menu and opens a dedicated settings
window. Do not add a system status-bar icon or menu-bar-extra scene.

The settings window uses a stable sidebar-detail layout:

- the left sidebar contains `通用`, `显示`, `快捷键`, `数据同步与备份`, and
  `关于`;
- the selected sidebar row determines the right-side panel;
- `通用` is selected by default when the window is first opened;
- category selection is window-local state and is not persisted as an app
  preference.

The right side presents native controls grouped into concise sections. Actions
that are visible but not implemented remain visibly inactive rather than
pretending to succeed.

## SwiftData Settings Model

Add one SwiftData entity, `AppSettings`, and register it in the model schema.
The application obtains the settings record through a small root/settings
lookup path:

- if one record exists, views consume that record;
- if no record exists, create and save a default record before controls or date
  rendering need values;
- the app treats this as a singleton preference record and does not expose a UI
  for creating additional records;
- if multiple records are ever encountered due to later synchronization
  conflicts, use a deterministic existing record and keep conflict resolution
  outside this feature.

All persisted fields are stored together in this record, including macOS-only
values. This is a deliberate product choice: a future iOS application may
ignore fields that have no meaning on iOS instead of introducing a second
preference store. Because the record may eventually sync, a device can
overwrite values that another device does not use, such as backup paths or
shortcuts; this risk is accepted for the single-record management model.

## Fields And Defaults

### General

- `launchAtLogin: Bool = false`
- `menuBarComponentEnabled: Bool = false`

Both controls persist their toggled state only. The application does not
register a login item or create a menu bar component in this change.

### Display

- `theme: String = "system"` with choices `系统`, `浅色`, and `深色`
- `language: String = "system"` with choices `系统`, `English`, and `简体中文`
- `overviewScope: String = "allProjects"` with choices `所有项目` and
  `星标项目`
- `weekdayFilterEnabled: Bool = false`
- `dateFormat: String = "yyyy/MM/dd HH:mm"`

Theme, language, overview scope, and weekday filtering persist only. Date
format is the only display preference wired into existing screens now.

Date format choices, in displayed order, are:

1. `yyyy/MM/dd HH:mm`, for example `2026/05/24 14:30`
2. `yyyy-MM-dd HH:mm`, for example `2026-05-24 14:30`
3. `MM/dd HH:mm`, for example `05/24 14:30`
4. `dd/MM/yyyy HH:mm`, for example `24/05/2026 14:30`

### Shortcuts

- `toggleMainPanelShortcut: String = "Option+V"`, displayed as `⌥ + V`
- `openSearchShortcut: String = "Command+F"`, displayed as `⌘ + F`

The settings panel stores shortcut values in a simple representation suitable
for later shortcut registration work. This change does not intercept key
events, register global shortcuts, or alter any existing search action.

### Sync And Backup

- `syncEnabled: Bool = true`
- `lastSyncAt: Date? = nil`
- `backupEnabled: Bool = true`
- `backupPath: String = "~/Documents/Viabar"`

The sync section displays an enable toggle and an unsynchronized placeholder
when `lastSyncAt` is `nil`; its `立即同步` action is shown but disabled.

The backup section displays an enable toggle and editable saved backup path.
The `数据导入` and `数据导出` actions are shown but disabled. No folder access,
bookmarks, file I/O, backup creation, import, or export runs in this change.

### About

The About panel displays the bundle version value when available and visible
rows for Telegram, App Store rating, licenses, and agreements. These rows do
not require persisted fields and are inactive placeholders in this change.

## Date Formatting Behavior

Add a shared date-formatting utility that receives the saved `AppSettings`
date-format choice and formats a `Date` using the corresponding pattern. If
the settings record or its date-format value cannot be resolved, the formatter
falls back to `yyyy/MM/dd HH:mm`.

Use that formatter for:

- the reminder date shown in each overview project card;
- reminder summaries shown alongside milestones and subtasks in the milestone
  list;
- the timestamp at the upper-left of each memo card.

The current screens contain different relative and abbreviated formatting
rules, such as time-only text for today's reminders or memo entries. Once the
shared setting is applied, these three surfaces render the complete selected
format consistently. Status color logic for overdue or upcoming reminders is
preserved; only the timestamp text formatting changes.

Reminder timestamps continue to be computed from existing `Reminder` data.
This change does not modify `Reminder`, `NotificationScheduleEntry`,
`NotificationScheduleService`, project archive handling, or due-entry
processing.

## View And Code Boundaries

- `ViabarApp.swift` registers `AppSettings` in the schema and adds the native
  settings scene using the shared model container.
- A focused new settings view file owns sidebar selection and panel
  composition.
- A focused settings model/support file contains the SwiftData entity,
  persisted-value constants or enums, and default-value definitions.
- A shared date-format helper owns the supported options, fallback behavior,
  and date-to-text transformation.
- Existing overview, milestone-list, and memo-card views read the available
  settings record and call the shared formatter instead of retaining separate
  formatting implementations for the affected text.
- Notification scheduling services and reminder edit controls remain outside
  the settings work.

## Error And Empty States

- If settings have never been saved, the application creates defaults and
  displays controls populated with those defaults.
- If a saved string no longer matches a supported selection, its UI and date
  formatting fall back to the documented default rather than showing a blank
  selection or invalid date text.
- If version metadata is unavailable, the About panel displays a stable
  fallback such as `--`.
- Disabled unimplemented buttons communicate that their backing feature is not
  available yet and must not mutate model data.

## Verification

Add test coverage where the behavior can be isolated:

- default `AppSettings` values match the specified defaults;
- each supported date-format option produces its expected timestamp text;
- an unsupported saved date-format value uses the default format fallback.

During implementation, inspect all three affected date displays so that no
old relative formatter remains on their user-visible timestamp paths.

In accordance with the repository instruction, do not compile the app or run
build/test commands unless explicitly requested. Use source inspection and
`git diff --check` as the non-compiling verification for this work.
