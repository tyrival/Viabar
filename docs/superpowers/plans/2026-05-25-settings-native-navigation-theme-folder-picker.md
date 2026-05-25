# Native Tabbed Settings Theme And Folder Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Viabar Settings use Finder-style native top tabs, align its controls consistently, support choosing a backup folder, and apply a coherent selected appearance across the whole app.

**Architecture:** Present Settings from SwiftUI's native `Settings` scene with top-level `TabView` category tabs and system-owned window chrome. Keep preferences in the shared SwiftData `AppSettings` record, apply theme exactly once through `NSApplication.shared.appearance` at the application boundary, and invoke `NSOpenPanel` only for folder selection.

**Tech Stack:** SwiftUI, SwiftData, AppKit (`NSOpenPanel`), Swift Testing.

**Repository Constraint:** Do not run `xcodebuild`, tests, previews, or launch workflows unless the user explicitly authorizes compilation. Add test expectations first, but validate this pass using source inspection and `git diff --check`.

---

### Task 1: Establish The Whole-App Theme Contract

**Files:**
- Modify: `ViabarTests/ViabarTests.swift`
- Modify: `Viabar/Models/AppSettings.swift`

- [x] Keep persisted `AppTheme` choices as `system`, `light`, and `dark`, defaulting new settings records to `system`.
- [x] Remove the superseded SwiftUI `ColorScheme` mapping API and its assertions after runtime evidence moved theme application to the AppKit application boundary.
- [x] Keep `automaticallyChecksForUpdates` defaulted to `true` and preserve all existing persisted preferences.

### Task 2: Use Native Tabbed Settings Layout

**Files:**
- Modify: `Viabar/Views/Settings/SettingsView.swift`

- [x] Restore SwiftUI's native `Settings` scene so macOS owns the settings window chrome and standard command.
- [x] Replace the fixed floating sidebar and custom traffic-light implementation with a top-level `TabView` whose icon-and-title items match Finder-style settings categories.
- [x] Give settings groups a `#ECECEC` surface in light appearance and an elevated gray surface in dark appearance.
- [x] Put row controls in a consistent trailing column so switches, pickers, fields, and recorder views align.

### Task 3: Refine Controls And Add Folder Selection

**Files:**
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Modify: `Viabar/Views/Settings/ShortcutRecorderField.swift`

- [x] Reduce the shortcut recorder to the size of a small normal input control and keep it in the trailing control column.
- [x] Cancel any in-progress shortcut recording when its settings tab disappears.
- [x] Add a compact `选择...` button beside the stored backup path.
- [x] Present a directory-only `NSOpenPanel`; persist the selected folder path and leave the existing value untouched on cancel.

### Task 4: Apply Appearance To Every Window

**Files:**
- Create: `Viabar/System/AppAppearanceController.swift`
- Modify: `Viabar/Models/AppSettings.swift`
- Modify: `Viabar/ViabarApp.swift`
- Modify: `Viabar/Views/Settings/SettingsView.swift`

- [x] Make the settings bootstrap return the shared `AppSettings` record so the startup theme can be applied without a view-level query.
- [x] Add `AppAppearanceController` as the only mapping from `AppTheme` to `NSApplication.shared.appearance`: `system` clears it, `light` uses `.aqua`, and `dark` uses `.darkAqua`.
- [x] Apply the persisted theme from the first mounted main-scene content task, not `ViabarApp.init()`, and apply new selections immediately from the Settings theme picker.
- [x] Access `NSApplication.shared` inside the controller rather than the `NSApp` implicitly unwrapped reference, avoiding a nil startup dereference.
- [x] Delete `ThemedRoot`, `ObservedThemeContent`, `WindowThemeApplier`, `.preferredColorScheme` forcing, and all per-window theme updates.
- [x] Record that runtime investigation rejected both content-only and window-level appearance forcing because they produced mixed rendering and a dark-mode hang.
- [x] Give the main window an explicit normal initial size and practical minimum size.

### Task 5: Verify Without Compiling

**Files:**
- Inspect: `Viabar/Models/AppSettings.swift`
- Inspect: `Viabar/Views/Settings/SettingsView.swift`
- Inspect: `Viabar/Views/Settings/ShortcutRecorderField.swift`
- Inspect: `Viabar/ViabarApp.swift`
- Inspect: `ViabarTests/ViabarTests.swift`

- [x] Confirm native `Settings`/`TabView` structure, removal of custom window chrome, coherent theme propagation, folder picker wiring, compact recorder sizing, data label, and update toggle defaults by focused source search.
- [x] Run `git diff --check` for whitespace/patch integrity.
- [x] Report that executable tests and visual runtime validation remain unrun because compilation was not authorized.
