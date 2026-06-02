# iOS Archive And Search Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the iOS static prototype search flow, archive tree, deletion confirmations, favorite refresh, compact bottom bars, and detail tap targets.

**Architecture:** Keep all changes inside the in-memory iOS prototype. Extend the prototype model with stable search destinations and archive folders, let the store own mutations and reveal state, and keep screen views focused on presentation. Reuse the macOS search semantics: compact rows, precise destination IDs, ancestor expansion for archived hits, and five-second orange feedback.

**Tech Stack:** SwiftUI, Observation, UIKit pasteboard, iOS 17 APIs, shell static checks.

---

### Task 1: Lock The New Static Contract

**Files:**
- Modify: `scripts/tests/test_ios_static_prototype.sh`

- [ ] Add static assertions for compact tab metrics, one-line overview percent, stable search destinations, archive lazy tree, folder actions, project deletion confirmation, favorite toolbar star, and the absence of project deletion from the detail toolbar.
- [ ] Run `./scripts/tests/test_ios_static_prototype.sh`.
- [ ] Confirm it fails before implementation because the new archive/search contract is missing.

### Task 2: Extend Prototype Models And Store

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeModels.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeStore.swift`

- [ ] Add `IOSPrototypeArchiveFolder` with stable ID, name, parent ID, and order index.
- [ ] Add archived project folder IDs and stable search target entity IDs.
- [ ] Add store operations for folder creation, rename, recursive deletion, ancestor reveal, unarchive, and target navigation request.
- [ ] Include archived projects in search results and use archive-prefixed paths.

### Task 3: Add Shared Highlight And Compact Bottom Metrics

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeComponents.swift`

- [ ] Add compact bottom-bar constants and apply them to home tabs, detail tabs, and detached action buttons.
- [ ] Allow progress rings to opt into a smaller archive size.
- [ ] Add reusable five-second orange outline highlight for project and memo surfaces.

### Task 4: Refine Overview Search And Project Deletion

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeOverviewView.swift`

- [ ] Force overview percentages to one line with enough width for `100%`.
- [ ] Replace the search footer with a left-expanding field that hides home tabs and keeps results above the field.
- [ ] Render compact macOS-style search rows with a small SF Symbol, title, and path.
- [ ] Route search selection through a path-based navigation destination.
- [ ] Add two-stage project deletion confirmation for overview cards.
- [ ] Add the top-right trash placeholder entry.

### Task 5: Add Detail Target Navigation And Full Tap Areas

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeProjectDetailView.swift`

- [ ] Remove project deletion from the detail toolbar.
- [ ] Add a warning-colored favorite star after the toolbar title.
- [ ] Scroll to milestone, subtask, and memo destination IDs.
- [ ] Apply five-second orange row fills for milestone and subtask hits and outline feedback for memo hits.
- [ ] Make task and subtask rows editable from the full non-reminder surface and memo cards editable from the full card.

### Task 6: Implement Lazy Archive Tree

**Files:**
- Create: `ViabariOS/Prototype/IOSPrototypeArchiveView.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeOverviewView.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeStore.swift`

- [ ] Render root folders with `LazyVStack`.
- [ ] Recursively instantiate children only for expanded folders.
- [ ] Render compact archive project rows with project-color SF Symbol, title, and smaller progress ring.
- [ ] Add root folder creation from the detached bottom-right button.
- [ ] Add child-folder creation, rename, and delete context-menu actions.
- [ ] Delete empty folders immediately and require confirmation for folders containing child folders or archived projects.
- [ ] Support unarchive and two-stage project deletion from archived project rows.

### Task 7: Static Verification

**Files:**
- Verify only.

- [ ] Run:

```bash
./scripts/tests/test_ios_static_prototype.sh
./scripts/tests/test_ios_foundation_static.sh
bash scripts/tests/test_widget_static.sh
plutil -lint ViabariOS/Info.plist ViabariOSWidget/Info.plist ViabarWidget/Info.plist Viabar.xcodeproj/project.pbxproj
git diff --check
```

- [ ] Hand off Xcode Run verification to the user. Do not compile unless explicitly requested.
