# Settings Runtime Behaviors, Localization, And Search Overlay Design

## Goal

Turn the previously persisted-but-inactive General, Display, and Shortcut
settings into real macOS application behavior while preserving the existing
native tabbed Settings window, shared SwiftData settings record, and live theme
support. Also correct the global-search toolbar gradient so search results
remain a floating overlay without washing out adjacent panels.

This design extends:

- `2026-05-24-settings-swiftdata-date-format-design.md`;
- `2026-05-24-settings-native-sidebar-shortcut-recorder-design.md`;
- `2026-05-25-settings-native-navigation-theme-folder-picker-design.md`;
- `2026-05-24-global-search-design.md`.

## Confirmed Product Decisions

- `开机启动` now performs real login-item registration for the main Viabar
  application.
- The app supports system-following language, English, and Simplified Chinese,
  and language changes apply immediately to every visible Viabar window.
- In system-following language mode, Simplified Chinese system preferences use
  Simplified Chinese; English and every other system language, including
  Traditional Chinese, fall back to English.
- The overview setting changes which cards are visible: all active projects or
  starred active projects only.
- `工作日过滤` is removed from Settings because it is not currently needed.
- The two recorded shortcuts become active global shortcuts only while the
  Viabar process is already running. They do not launch a terminated app.
- The shortcut rows no longer show the instructional description text beneath
  their titles.
- Global-search results continue floating above the main panel; the white
  toolbar gradient remains fixed in height and never covers the sidebar or memo
  drawer.

## Approach Choice

The implementation uses macOS system APIs at the application boundary and
continues using the existing `AppSettings` record as the persisted source of
user choice:

- `SMAppService.mainApp` manages launch-at-login state;
- a small global hot-key controller registers only the two configured runtime
  commands and dispatches them into the application UI;
- localized string resources plus an application language resolver supply
  immediate English or Simplified Chinese presentation;
- existing SwiftUI view state applies overview scope and search layout changes.

This is preferred over adding a shortcut package for two commands, and over
monitoring all keyboard events, which would broaden dependencies or introduce
an unnecessary permission-oriented interaction model.

## Launch At Login

The `通用` tab keeps the `开机启动` switch and changes its behavior from stored
preference only to real Service Management registration:

- enabling the switch requests registration through `SMAppService.mainApp`;
- disabling it unregisters the main application login item;
- when Settings is presented, the displayed setting is reconciled with the
  actual service registration status instead of trusting stale persisted data;
- on successful changes, `AppSettings.launchAtLogin` stores the effective state;
- if registration or unregistration fails, the switch returns to the actual
  effective state and presents a localized error message.

No helper application or menu-bar-extra target is introduced. Login-item
approval remains subject to macOS system policy.

## Live Application Localization

### Supported Choices

`AppLanguage` remains persisted in `AppSettings.language` with:

- `system`;
- `english`;
- `simplifiedChinese`.

The app resolves the selected presentation locale as follows:

| Saved Selection | Effective UI Language |
| --- | --- |
| `english` | English |
| `simplifiedChinese` | Simplified Chinese |
| `system`, system preference starts with `zh-Hans` or simplified-Chinese equivalent | Simplified Chinese |
| `system`, any other preference including `en`, `zh-Hant`, or another language | English |
| invalid persisted value | Same resolution rules as `system` |

### Immediate Application

User-facing strings are moved into localized resources for English and
Simplified Chinese. The root application content derives one effective locale
from the shared settings record and injects it into both:

- the main window content;
- the native Settings scene content.

Changing the language picker updates the record and immediately causes active
SwiftUI content in both windows to render using the newly resolved localized
strings. This behavior does not require restarting Viabar and does not alter
the theme application mechanism.

The localization pass covers visible application copy in views owned by the
current project, including navigation labels, form labels, search text,
dialogs, context-menu actions, empty states, settings copy, and accessibility
labels/help text. User-created project, milestone, memo, template, or archive
folder content remains unmodified.

### Formatting Boundary

The existing user-selected date format stays independent of language choice.
Selecting English does not overwrite `dateFormat`, and selecting Simplified
Chinese does not impose a different timestamp pattern.

## Overview Scope

The `显示` tab retains `总览` with the existing persisted choices:

- `所有项目` / `allProjects`;
- `星标项目` / `favoriteProjects`.

`OverviewDashboardView` reads the shared setting and filters its existing
active-project card list:

- all-project scope shows every project that is not archived;
- favorite-project scope shows only projects that are not archived and have
  `isFavorite == true`.

The scope affects only overview cards. It does not filter the sidebar list,
archived folders, search results, or open project detail views.

## Settings Cleanup

- Remove the visible `工作日过滤` row from the Display tab.
- Retain `weekdayFilterEnabled` in `AppSettings` for storage compatibility with
  existing local data, but do not read or write it through active UI.
- Remove the supporting descriptions from both shortcut rows:
  `点击快捷键区域后按新的组合键` and `按 Esc 取消录制`.
- Keep shortcut recording itself unchanged: clicking a field starts recording
  and pressing Escape still silently cancels the in-progress recording.

## Runtime Global Shortcuts

### Commands

The saved shortcut strings already recorded by Settings now control two
application commands:

- `显示 / 隐藏主面板` toggles the main Viabar panel while Viabar is running;
- `打开搜索框` brings the main panel forward if necessary and then presents and
  focuses global search exactly as clicking the toolbar magnifying-glass button
  does.

The commands are global while the app process is alive. If Viabar has been
quit, pressing either shortcut performs no action and does not relaunch it.

### Window Behavior

For `显示 / 隐藏主面板`:

- if no main panel is visible, activate Viabar and make its main window key and
  front;
- if the main panel is currently visible, order that window out so it can be
  recalled with the same shortcut;
- the Settings window is not treated as the main panel and does not substitute
  for it.

For `打开搜索框`:

- ensure the main window is visible, active, and frontmost;
- send one search-presentation command into `ContentView`;
- `ContentView` uses the same `isGlobalSearchPresented` and focus path already
  used by toolbar activation.

### Registration And Failure Handling

A focused application-level shortcut controller owns registration, unregisters
superseded values, and publishes command callbacks. It is configured from
persisted settings on app startup after the application is available, and
reconfigured whenever a recorder saves a new shortcut.

When registering a changed shortcut fails, such as because the key combination
is unavailable:

- restore the last working persisted shortcut value for that action;
- keep the last working registered hot key active;
- show a localized error in Settings.

The two Viabar actions cannot share the same combination. A newly recorded
duplicate is rejected through the same restore-and-error behavior.

## Global Search Toolbar Gradient Fix

### Existing Problem

The search panel is hosted in a top-level toolbar overlay in `ContentView`.
The toolbar gradient is sized and layered at the outer content level rather
than being constrained to the central detail area. When search results appear,
this creates a pale washed-out region that visually reaches into the sidebar
and behaves as though it belongs to the expanding results panel.

### Required Layout

- The search panel continues expanding downward as a floating result panel over
  the central content.
- The toolbar gradient has a fixed height based solely on the toolbar strip; it
  does not increase as the search result list appears or grows.
- The gradient begins after the sidebar and ends before an open memo drawer.
- The sidebar and memo drawer keep their own normal backgrounds while search is
  open.
- Search keyboard navigation, selection, dismissal, and result routing remain
  unchanged.

The fix belongs in the central toolbar layer ownership and geometry in
`ContentView`, not by hiding results or applying a compensating color over
adjacent panes.

## Code Boundaries

- `Viabar/Models/AppSettings.swift` retains persisted settings definitions and
  gains pure effective-language resolution and overview-scope filtering helpers
  where testability benefits.
- `Viabar/System/AppLaunchAtLoginController.swift` owns
  `SMAppService.mainApp` status and update operations.
- `Viabar/System/AppGlobalShortcutController.swift` owns global shortcut
  registration and command dispatch for the two settings-backed actions.
- `Viabar/System/AppLanguageController.swift` resolves effective locale from
  persisted selection and system preferences.
- `Viabar/ViabarApp.swift` creates application-level controllers, applies
  persisted startup configuration, and injects effective language and shortcut
  actions into scene content.
- `Viabar/Views/Settings/SettingsView.swift` removes obsolete rows/copy,
  applies login-item changes, reconfigures shortcuts when recordings succeed,
  and renders localized errors when system operations fail.
- `Viabar/ContentView.swift` reads overview scope, receives the present-search
  command, and constrains the toolbar gradient to the main panel.
- Existing feature views replace visible literal text with localizable resource
  keys while leaving user content untouched.
- `Viabar/Localizable.xcstrings` stores English and Simplified Chinese
  translations for supported application copy.

## Error And Edge States

- A login-item registration failure never leaves the saved toggle claiming a
  state that macOS rejected.
- An invalid saved language value behaves as `system`, using Simplified Chinese
  only for a Simplified Chinese system preference and English otherwise.
- A saved overview-scope value that is no longer recognized behaves as
  `allProjects`.
- Shortcut registration failure preserves the last working registered shortcut
  and exposes a localized settings error.
- If the current search query has no results, its normal floating empty-result
  row remains visible; it must not alter the fixed gradient height.

## Verification

Add test definitions first for isolated logic:

- effective-language resolution maps `zh-Hans` system preference to Simplified
  Chinese and maps English, Traditional Chinese, and another language to
  English while in `system` mode;
- explicit English and Simplified Chinese selections override system preference;
- invalid language values use system-resolution fallback;
- overview filtering returns all active projects or only favorite active
  projects as selected, never archived projects;
- duplicate shortcut configuration is rejected before system registration where
  pure validation can isolate the behavior.

By repository instruction, implementation must not compile, run tests, launch
the app, or run UI previews unless the user separately authorizes compilation.
The implementation pass will therefore use focused source inspection and
`git diff --check`; executable verification of login-item behavior, active
global shortcuts, live window-language switching, and the visual search-overlay
correction remains pending runtime authorization.

## Primary API References

- Apple Service Management `SMAppService.mainApp`:
  <https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp>
- Apple Service Management registration:
  <https://developer.apple.com/documentation/servicemanagement/smappservice/register()>
- Apple localization guidance:
  <https://developer.apple.com/documentation/xcode/localization/>
