# iOS Settings, Project Creation, Templates, Trash, and Menu Bar Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the iOS operational settings and creation surfaces, plus a custom default macOS menu bar icon, without changing shared SwiftData schema.

**Architecture:** Reuse the existing shared models and services from the App Group store. Add focused iOS SwiftUI views under `ViabariOS/Persistence`, route them from the persistent overview, and extend macOS menu bar rendering to support one asset-backed icon alongside existing SF Symbols.

**Tech Stack:** SwiftUI, SwiftData, WidgetKit refresh through existing `ProjectService`, App Group shared store, Asset Catalog.

---

### Task 1: Fix iOS Product Display Name

**Files:**
- Modify: `ViabariOS/Info.plist`

- [ ] Add `CFBundleDisplayName` with value `Viabar`.
- [ ] Validate plist syntax with `plutil -lint ViabariOS/Info.plist`.

### Task 2: Add iOS Settings Navigation

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistentSettingsView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentRootView.swift`

- [ ] Add the grouped mobile settings list.
- [ ] Bind display and data rows to the existing settings stores.
- [ ] Add version and Telegram rows.
- [ ] Route the overview gear button into settings.

### Task 3: Add iOS Trash Browser

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistentTrashView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentSettingsView.swift`

- [ ] Render paginated trash rows using `TrashService.items`.
- [ ] Load additional pages lazily.
- [ ] Add the bottom search composer.
- [ ] Add restore, copy, and restore-error handling.

### Task 4: Add iOS Project Creation and Template Management

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistentProjectCreationView.swift`
- Create: `ViabariOS/Persistence/IOSPersistentTemplateViews.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentSettingsView.swift`

- [ ] Replace the overview trash shortcut with `plus.app`.
- [ ] Add new-project title, template, symbol, and color controls.
- [ ] Create projects through `ProjectService.createProject(title:template:)`.
- [ ] Add template list, create, edit, and confirmed deletion.
- [ ] Save template blueprints through `ProjectService.saveTemplate`.

### Task 5: Add Completed-Task Visibility Toggle

**Files:**
- Modify: `ViabariOS/Persistence/IOSPersistentProjectDetailView.swift`

- [ ] Add a top-right menu action for `Project.hideCompleted`.
- [ ] Filter completed milestones and subtasks when enabled.
- [ ] Persist changes through `ProjectService.updateProject`.

### Task 6: Add the Custom macOS Menu Bar Icon

**Files:**
- Create: `Viabar/Assets.xcassets/MenuBarViabar.imageset/Contents.json`
- Create: `Viabar/Assets.xcassets/MenuBarViabar.imageset/MenuBarViabar.png`
- Create: `Viabar/Assets.xcassets/MenuBarViabar.imageset/MenuBarViabar@2x.png`
- Modify: `Viabar/Models/AppSettings.swift`
- Modify: `Viabar/Models/BackupSnapshot.swift`
- Modify: `Viabar/Views/MenuBar/MenuBarPanelView.swift`
- Modify: `Viabar/Views/Settings/SettingsView.swift`
- Modify: `Viabar/ViabarApp.swift`

- [ ] Add the supplied 1x and 2x template image assets.
- [ ] Add `MenuBarIcon.viabar`.
- [ ] Make `viabar` the fallback and new-settings default.
- [ ] Adopt the new icon once for existing macOS installs that still store the historical default.
- [ ] Render asset-backed and SF Symbol-backed candidates correctly.
- [ ] Keep backup defaults aligned with the new default.

### Task 7: Static Verification

**Files:**
- Inspect all changed files.

- [ ] Run `plutil -lint` for the app plist, project file, asset catalog JSON, and localization files.
- [ ] Run targeted `rg` checks for display name, iCloud placeholder semantics, trash pagination, template service reuse, completed-task filtering, and custom menu bar asset rendering.
- [ ] Run `git diff --check`.
- [ ] Do not compile or run tests unless the user explicitly requests it.
