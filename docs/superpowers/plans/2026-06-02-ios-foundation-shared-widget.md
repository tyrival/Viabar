# iOS Foundation And Shared Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iOS app foundation and iOS Widget extension that use an iOS-only App Group while reusing the existing macOS Widget implementation.

**Architecture:** Keep `ViabarWidget/` as the shared Widget implementation compiled by both Widget extension targets. Keep `ViabariOSWidget/` as the iOS extension's resource and entitlement folder. Make `SharedModelContainer` platform-aware only at the App Group and iOS first-store creation boundary.

**Tech Stack:** SwiftUI, SwiftData, WidgetKit, App Intents, Xcode project configuration, shell static checks.

---

### Task 1: Add Static Foundation Checks

**Files:**
- Create: `scripts/tests/test_ios_foundation_static.sh`

- [ ] Assert stable deployment targets, iOS bundle identifiers, directory naming, entitlements, platform-aware App Group selection, iOS container entry point, shared Widget target membership, and removal of template Widget code.
- [ ] Run `./scripts/tests/test_ios_foundation_static.sh` and confirm it fails before implementation.

### Task 2: Rename The iOS Widget Resource Folder

**Files:**
- Rename: `ViabariOSWidgetExtension/` to `ViabariOSWidget/`
- Modify: `Viabar.xcodeproj/project.pbxproj`
- Create: `ViabariOS/ViabariOS.entitlements`
- Create: `ViabariOSWidget/ViabariOSWidget.entitlements`
- Delete: `ViabariOSWidget/AppIntent.swift`
- Delete: `ViabariOSWidget/ViabariOSWidgetExtension.swift`
- Delete: `ViabariOSWidget/ViabariOSWidgetExtensionBundle.swift`

- [ ] Rename the source folder while preserving the target and `.appex` names.
- [ ] Update the iOS Widget bundle identifier to `com.tyrival.ViabariOS.Widget`.
- [ ] Add `group.com.tyrival.ViabariOS` entitlement files and wire them to the iOS targets.
- [ ] Add the existing `ViabarWidget/` synchronized group to the iOS Widget target so both extensions compile the same Widget source and strings.

### Task 3: Make Shared Sources Build On iOS

**Files:**
- Modify: `Viabar/System/SharedModelContainer.swift`
- Modify: `Viabar/System/ViabarColor.swift`
- Modify: `Viabar/Views/Component/Color+Hex.swift`
- Modify: `Viabar.xcodeproj/project.pbxproj`

- [ ] Resolve the local App Group by platform: macOS uses `group.com.tyrival.Viabar`, iOS uses `group.com.tyrival.ViabariOS`.
- [ ] Add `makeIOSAppContainer()` that creates and opens the iOS App Group store without macOS legacy-store migration.
- [ ] Keep macOS `makeMainAppContainer()` behavior unchanged.
- [ ] Use conditional imports and color conversion so shared model and Widget files remain portable.
- [ ] Add the narrow shared model source set to the iOS App target.

### Task 4: Wire The iOS App Placeholder

**Files:**
- Modify: `ViabariOS/ViabariOSApp.swift`
- Modify: `ViabariOS/ContentView.swift`

- [ ] Open the iOS App Group SwiftData container during app initialization.
- [ ] Ensure the default settings record exists.
- [ ] Inject the container into the placeholder root view.
- [ ] Keep the placeholder intentionally small and add `.onOpenURL` as the future Widget navigation handoff point.

### Task 5: Verify Without Compiling

**Files:**
- Verify: `scripts/tests/test_ios_foundation_static.sh`
- Verify: `Viabar.xcodeproj/project.pbxproj`
- Verify: all entitlement and plist files

- [ ] Run `./scripts/tests/test_ios_foundation_static.sh`.
- [ ] Run the SwiftData and App Group `rg` inspections from the design spec.
- [ ] Run negative `rg` checks for the old iOS Widget folder and duplicated `Extension` name.
- [ ] Run `git diff --check`.
- [ ] Run `plutil -lint` on the project, plist, and entitlement files.
- [ ] Report that compilation and runtime validation remain for the user's Xcode hand test.
