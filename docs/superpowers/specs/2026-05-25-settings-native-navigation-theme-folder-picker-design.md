# Native Tabbed Settings, Theme, And Folder Picker Design

## Goal

Replace the failed sidebar-based Settings experiment with Finder-style native
macOS Settings tabs, while retaining aligned settings controls, shortcut
recording, the folder picker, and whole-app theme selection.

## Official API Basis

The implementation now follows the standard Finder preferences model:

- Use SwiftUI's native `Settings` scene, which supplies the conventional app
  menu entry, `Command+,`, system traffic-light controls, and system window
  shape.
- Use `TabView` with icon-and-title tab items across the top for `通用`,
  `显示`, `快捷键`, `数据`, and `关于`.
- Remove the custom `Window`, custom sidebar, custom traffic-light controls,
  draggable header, transparent-background window bridge, and custom outer
  corner clipping.
- Keep standard SwiftUI controls within each tab, with aligned trailing
  control columns and compact configuration groups.

Relevant Apple references:

- <https://developer.apple.com/documentation/swiftui/settings>
- <https://developer.apple.com/documentation/swiftui/tabview>
- <https://developer.apple.com/documentation/appkit/nsapplication/appearance>
- <https://developer.apple.com/videos/play/wwdc2025/323>

## Window And Tab Structure

The Settings scene presents a fixed-size, native preference window. The
top-level `TabView` renders icon-and-title category selectors at the top in
the style of Finder settings. Each category displays its existing settings
groups beneath the tab strip. System window chrome, traffic-light controls,
dragging, and window rounding are left entirely to macOS.

## Detail Layout And Control Alignment

The detail pane keeps compact grouped configuration sections. It changes in
these ways:

- in light mode, a settings group uses the explicit `#ECECEC` requested
  surface instead of rendering as white or too dark against the window;
- in dark mode, a moderately elevated gray surface separates each settings
  group from the dark detail background;
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

The shared settings record remains the source of truth. One application-level
`AppAppearanceController` applies its value through
`NSApplication.shared.appearance`: light maps to `.aqua`, dark maps to
`.darkAqua`, and system clears the override with `nil`. AppKit then propagates
one effective appearance to all application windows, panels, controls, and
SwiftUI-hosted content.

The controller is called from the main scene's first mounted content task,
after AppKit has established the application object and the shared settings
record can be read safely. It is also called immediately when the theme picker
changes. It must not be called from `ViabarApp.init()`, where the `NSApp`
implicit application reference is not yet guaranteed to exist. No root-content
`.preferredColorScheme(...)`, `NSWindow.appearance` bridge, or per-window
observer remains. This follows Apple's application appearance inheritance
model and ensures the native Settings scene and main window use the same
source of appearance truth.

Runtime investigation rejected both partial approaches: content-only
`.preferredColorScheme(...)` left SwiftUI content dark after its window had
returned to Aqua until focus changed; window-level appearance writes then
caused lagging mixed surfaces and a re-entrant SwiftUI update hang when
selecting dark mode. Both paths are removed rather than patched further.
Applying `NSApp.appearance` from `ViabarApp.init()` was also rejected after it
crashed on launch while the implicit AppKit application reference was nil.

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

- `Viabar/Views/Settings/SettingsView.swift` defines the native top-tab
  selection layout, compact detail groups, aligned trailing controls, and
  invokes the folder chooser from the backup path row.
- `Viabar/Views/Settings/ShortcutRecorderField.swift` remains the scoped
  AppKit first-responder bridge for shortcut recording, with reduced standard
  control sizing.
- A narrowly scoped native folder-picker helper, either within the settings
  file or beside it, owns the open-panel interaction and returns a selected
  path through a callback.
- `Viabar/Models/AppSettings.swift` stores the selected theme choice and
  returns the shared settings record during startup bootstrap.
- `Viabar/System/AppAppearanceController.swift` is the sole runtime theme
  applier and maps persisted choices to `NSApplication.shared.appearance`.
- `Viabar/ViabarApp.swift` applies the saved theme during application startup,
  gives the main window a normal default launch size and useful minimum content
  size, and declares the native `Settings` scene without theme wrappers.
- `Viabar/Views/Settings/SettingsView.swift` persists a changed theme and
  immediately delegates its live application to `AppAppearanceController`.

## Verification

Use runtime visual checking when the user authorizes compilation and launch:

- Settings presents native system window chrome and Finder-style top tabs;
- switching among `通用`, `显示`, `快捷键`, `数据`, and `关于` changes the
  visible tab content;
- light-mode setting groups use `#ECECEC`, and dark-mode groups remain visibly
  separated from the detail background;
- trailing controls align consistently;
- shortcut fields are compact;
- the browse button updates backup path after choosing a folder;
- switching dark -> system immediately applies a coherent appearance rather
  than mixed light/dark content, without requiring focus to move to another
  application.

Per repository instruction, do not compile, test, or launch until the user
explicitly requests that verification.
