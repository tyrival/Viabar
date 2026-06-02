# iOS Prototype Interaction Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the iOS static prototype overview visuals and project-detail composer behavior with the confirmed macOS interaction semantics.

**Architecture:** Keep the in-memory prototype boundary. Use a single bottom composer for add and edit sessions. Rows and cards remain display-only; they route edit targets upward, and the owning screen commits through the paper-plane button only. Use UIKit pasteboard narrowly for context-menu copy actions.

**Tech Stack:** SwiftUI, Observation, SF Symbols, iOS 17 APIs, shell static checks.

---

### Task 1: Lock The Confirmed Interaction Contract

**Files:**
- Modify: `scripts/tests/test_ios_static_prototype.sh`

- [ ] Add static assertions for:
  - macOS ring colors `#00BBE1` and `#00F9D0`.
  - `AngularGradient`.
  - `mappin.and.ellipse` and `list.bullet.indent`.
  - `ViabarColor.warning`.
  - `paperplane.fill`.
  - `IOSPrototypeDetailComposer`.
  - `新增子任务`.
  - absence of `Button("完成")`.

- [ ] Run:

```bash
./scripts/tests/test_ios_static_prototype.sh
```

Expected: FAIL before implementation because the current progress ring and composer do not satisfy the contract.

### Task 2: Align Overview Card And Shared Progress Visuals

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeComponents.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeOverviewView.swift`

- [ ] Replace `IOSPrototypeProgressRing` with a fixed macOS-style angular gradient ring:
  - track: `#00BBE1` at `0.2` opacity.
  - stroke: `#00BBE1 -> #00F9D0 -> #00BBE1`.
  - percent color helper: `#00BBE1`.

- [ ] Align `IOSOverviewProjectCard` with macOS:
  - leading rectangle width `4`, full card height.
  - success color for completed project accent.
  - fixed warning color for `star.fill`.
  - `mappin.and.ellipse` and `list.bullet.indent`.
  - macOS-equivalent title, milestone, subtask, reminder, and progress spacing.

### Task 3: Add Shared Composer And Editing Sessions

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeComponents.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeProjectDetailView.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeStore.swift`

- [ ] Keep `IOSPrototypeDetailComposer` as the only multiline editor with:
  - auto-focused `TextEditor`.
  - no keyboard toolbar.
  - no focus-loss commit callback.
  - trailing paper-plane button remains outside the composer.

- [ ] Add store mutation:

```swift
func addSubtask(to milestoneID: UUID, in projectID: UUID, title: String)
```

- [ ] Replace inline edit state with detail editing-session enum cases that retain target IDs:

```swift
enum IOSPrototypeDetailSession {
    case idle
    case addMilestone
    case addSubtask(milestoneID: UUID)
    case addMemo
    case editMilestone(milestoneID: UUID)
    case editSubtask(milestoneID: UUID, subtaskID: UUID)
    case editMemo(memoID: UUID)
}
```

- [ ] Footer behavior:
  - idle: show task/memo Tab capsule and detached `+`.
  - add: hide Tabs, expand composer toward the left, show detached `paperplane.fill`.
  - edit: hide Tabs, show the same bottom composer prefilled with source text, show detached `paperplane.fill`.

- [ ] Commit only when the paper-plane button is tapped. External taps must not save or close add/edit sessions.

### Task 4: Route Display Rows Through Bottom Composer

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeProjectDetailView.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeStore.swift`

- [ ] Pass narrow edit callbacks to milestone, subtask, and memo rows.
- [ ] A row tap or context-menu edit action starts a bottom composer session prefilled with source text.
- [ ] Rows and memo cards remain display-only during editing.
- [ ] Footer paper plane directly renames or deletes the active target.
- [ ] Empty edit deletes the milestone, subtask, or memo.
- [ ] Add “新增子任务” as the first milestone context-menu item, routing to `.addSubtask(milestoneID:)`.

### Task 5: Add Copy Menus And Completed-Row Hit Areas

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeComponents.swift`
- Modify: `ViabariOS/Prototype/IOSPrototypeProjectDetailView.swift`

- [ ] Add a narrow UIKit pasteboard helper.
- [ ] Add “复制” to milestone, subtask, and memo context menus.
- [ ] Apply rectangular content shapes to task rows so completed rows retain a full-width long-press target.

### Task 6: Route Overview Project Editing Through Bottom Composer

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeOverviewView.swift`

- [ ] Replace card-local inline title editing with a home-owned bottom composer.
- [ ] Context-menu “编辑” starts a prefilled project title session.
- [ ] Paper plane is the only project-title commit path.

### Task 7: Align Detail Header

**Files:**
- Modify: `ViabariOS/Prototype/IOSPrototypeProjectDetailView.swift`

- [ ] Use the shared macOS-style gradient ring and fixed percent color.
- [ ] Keep the project title in the toolbar.
- [ ] Tint the toolbar SF Symbol with the project accent, or success color when completed.

### Task 8: Static Verification

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
