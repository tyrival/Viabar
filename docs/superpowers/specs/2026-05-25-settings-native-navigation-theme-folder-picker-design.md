# Settings Native Navigation, Theme, And Folder Picker Design

## Goal

Correct the Settings window implementation by using macOS 26 native window
and sidebar structure, then add live whole-app theme application and a native
backup-folder picker. This design supersedes only the layout implementation
choices in the prior settings-sidebar design; persisted settings, shortcut
recording, and automatic-update requirements remain in scope.

## Official API Basis

The implementation follows Apple platform facilities rather than recreating
the macOS 26 Settings appearance manually:

- `NavigationSplitView` is the native sidebar/detail structure and receives
  the new macOS 26 Liquid Glass sidebar appearance.
- `toolbar(removing: .sidebarToggle)` removes the sidebar-collapse control
  supplied by `NavigationSplitView`.
- `toolbar(removing: .title)` hides the visible title presentation while
  preserving a logical window title for system use.
- `toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` removes the
  visible toolbar background so the sidebar/content presentation reaches the
  top of the window around the system traffic-light controls.

The prior custom `HStack` plus hand-built glass sidebar is replaced. The
application must not draw imitation traffic-light controls.

Relevant Apple references:

- <https://developer.apple.com/documentation/swiftui/navigationsplitview>
- <https://developer.apple.com/documentation/SwiftUI/View/toolbar%28removing%3A%29>
- <https://developer.apple.com/documentation/SwiftUI/Customizing-window-styles-and-state-restoration-behavior-in-macOS>
- <https://developer.apple.com/videos/play/wwdc2025/323>

## Window And Sidebar Structure

The Settings root returns to a native two-column `NavigationSplitView`:

- the left column contains `通用`, `显示`, `快捷键`, `数据`, and `关于`;
- the detail column displays the currently selected category;
- the sidebar is shown by default and the sidebar-toggle toolbar item is
  removed;
- no forward/back controls or visible title label appear in the top toolbar;
- native traffic-light controls remain system-owned and should visually sit
  within the top-left sidebar region once toolbar title/background are hidden.

The sidebar rows retain standard macOS selection appearance. Their full
available row bounds must be hit-testable so clicks to the empty trailing
space still select the row.

## Detail Layout And Control Alignment

The detail pane keeps compact grouped configuration sections. It changes in
these ways:

- in light mode, a settings group uses a lightly gray semantic surface instead
  of rendering as visually white against the window background;
- in dark mode, it remains system adaptive rather than hardcoding a fixed
  palette;
- every row allocates a consistent trailing control column, so switches,
  menus, text fields, buttons, and shortcut recorders share right alignment;
- the shortcut recorder adopts the same small control height as a standard
  small text field and does not consume excessive horizontal width.

Standard SwiftUI `Toggle`, `Picker`, `TextField`, and `Button` controls remain
preferred over custom replicas.

## Backup Folder Selection

The `数据` category keeps its `数据同步` and `数据备份` sections. The backup
path row changes from a lone text field to:

- the persisted `backupPath` text field;
- a small adjacent browse button such as `选择...`;
- selecting the button opens the native macOS folder selection interface;
- choosing a folder writes its display path into `settings.backupPath`;
- cancelling the panel leaves the current path unchanged.

The folder choice does not create backups, start file copying, or store a
security-scoped bookmark in this change. It selects and persists the visible
configured path only.

## Whole-App Theme Application

The existing `theme` setting changes from storage-only to active behavior for
the whole Viabar application:

- `system` maps to no forced scheme and follows the current macOS appearance;
- `light` forces light appearance;
- `dark` forces dark appearance;
- changing the picker updates visible Viabar windows immediately, including
  the main window and Settings window;
- reopening the application continues to use the persisted selected value.

The shared settings record remains the source of truth. A small root wrapper
queries that record and applies the resolved `ColorScheme?` via
`preferredColorScheme` to each scene's root content rather than duplicating
theme state in individual views.

This change applies only color appearance. It does not implement language,
overview filtering, launch-at-login, menu-bar components, sync execution, or
automatic-update execution.

## Retained Features

The following already-approved behavior remains required:

- the sidebar category label is `数据`;
- shortcut items use keyboard recording rather than editable free text;
- recorded shortcuts persist in the documented canonical representation;
- the About panel contains `自动更新`, enabled by default;
- no runtime global hotkey registration or update checker is introduced.

## View And Code Boundaries

- `Viabar/Views/Settings/SettingsView.swift` returns to native
  `NavigationSplitView`, defines compact detail groups and aligned trailing
  controls, and invokes the folder chooser from the backup path row.
- `Viabar/Views/Settings/ShortcutRecorderField.swift` remains the scoped
  AppKit first-responder bridge for shortcut recording, with reduced standard
  control sizing.
- A narrowly scoped native folder-picker helper, either within the settings
  file or beside it, owns the open-panel interaction and returns a selected
  path through a callback.
- `Viabar/Models/AppSettings.swift` provides a pure mapping from saved theme
  choice to `ColorScheme?`.
- `Viabar/ViabarApp.swift` wraps both root scene contents with the shared
  theme-applier view and configures the Settings toolbar presentation.
- `ViabarTests/ViabarTests.swift` covers the pure theme-to-color-scheme mapping
  in addition to existing settings and shortcut tests.

## Verification

Use tests first for the pure theme mapping when compile authorization is
available:

- system returns `nil`;
- light returns `.light`;
- dark returns `.dark`;
- unsupported saved input resolves to system behavior.

Use runtime visual checking when the user authorizes compilation and launch:

- Settings displays the native macOS 26 sidebar reaching the traffic-light
  region without a visible title row;
- no sidebar toggle appears;
- clicking anywhere in a sidebar row selects it;
- light-mode setting groups are visibly gray against the window background;
- trailing controls align consistently;
- shortcut fields are compact;
- the browse button updates backup path after choosing a folder;
- switching theme immediately changes both the main window and Settings.

Per repository instruction, do not compile, test, or launch until the user
explicitly requests that verification.
