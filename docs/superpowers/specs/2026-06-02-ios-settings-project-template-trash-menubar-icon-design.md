# iOS Settings, Project Creation, Templates, Trash, and Menu Bar Icon Design

## Goal

Extend the iOS app from the persistent browsing shell into a testable daily-use shell while keeping macOS, iOS, and Widget on the same App Group SwiftData store.

## Constraints

- Do not change the SwiftData schema.
- Reuse `AppSettings`, `ProjectService`, `TrashService`, `ProjectTemplate`, `TemplateMilestone`, and `TemplateSubTask`.
- Keep CloudKit disabled. The iOS iCloud switch stores `AppSettings.syncEnabled` only.
- Keep trash items in the separate App Group `trash.store`.
- Do not compile or run tests unless explicitly requested.

## iOS Display Name

Add `CFBundleDisplayName = Viabar` to the iOS app plist. This changes the system notification permission prompt without renaming the Xcode target or bundle identifier.

## Overview and Project Detail

- Replace the overview top-right trash shortcut with a circular `plus.app` new-project button.
- Keep trash access under Settings > Features.
- Add a project-detail menu action that toggles `Project.hideCompleted`.
- Filter completed milestones and completed subtasks from the task list when the setting is enabled.

## iOS Settings

Use a navigation-based mobile settings surface:

- Features
  - Trash
  - Templates
- Display
  - Theme
  - Language
  - Overview
  - Week Starts On
  - Date Format
- Data
  - iCloud Sync
  - Trash Retention
- About
  - Version
  - Telegram

Settings reuse the macOS stores. Theme and language apply immediately in iOS. Trash retention remains in `TrashRetentionSettingsStore`, and startup cleanup remains in `ViabariOSApp`.

## iOS Project Creation

Present a mobile sheet from the overview `plus.app` button. Support:

- project title
- optional template selection
- project symbol
- project accent color
- create and cancel actions

Creating a project uses `ProjectService.createProject(title:template:)`, then applies the selected symbol and color and saves through `updateProject`.

## iOS Template Management

Settings > Templates opens a navigation page:

- list templates
- create template
- edit template
- delete template with confirmation
- edit template title, default symbol, default accent color, completed-task visibility, milestones, and subtasks

The UI is mobile-specific but uses the existing macOS template blueprint service methods.

## iOS Trash Browser

Settings > Trash opens a navigation page:

- lazy scrolling rows from `TrashService.items`
- load the next page through `TrashService.loadNextPage()` when the loading row appears
- bottom search field using `TrashItemIndex.results`
- context menu actions for restore and copy
- restore error alerts matching macOS semantics

## macOS Menu Bar Icon

Add the supplied 22x22 and 44x44 transparent PNG files as a macOS asset named `MenuBarViabar`. Extend menu bar icon selection so existing SF Symbol candidates stay available and the custom asset becomes the default. Rendering uses template mode so the status item follows the system menu bar tint.

Because `AppSettings.menuBarIcon` is already a string, using `MenuBarViabar` as a new stored value does not change the schema.

For existing macOS installs, use a one-time local `UserDefaults` adoption marker. If the stored icon is still the historical `bookmark.fill` default, switch it to `MenuBarViabar` once. A later user selection is never overwritten.
