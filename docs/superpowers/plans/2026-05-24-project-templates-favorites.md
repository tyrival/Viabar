# Project Templates And Favorites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independently managed project templates that initialize new projects with style and two-level tasks, plus persistent project favorites visible in the sidebar and overview.

**Architecture:** Store templates as dedicated SwiftData entities so they never enter live project, reminder, archive, or search flows. Route template copying and favorite persistence through `ProjectService`, keep selection in `NewProjectView`, and isolate template management/editor UI in a focused component file.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing source coverage, existing `ProjectService` and project-row/card UI.

---

## Constraints

- Templates save only their name, color, icon, completed-visibility preference, milestones, and subtasks; they never store reminders, memos, archive state, completion state, or favorite state.
- A selected template seeds color and icon immediately, but the current new-project form values win if changed afterward.
- The user's repository instruction forbids compiling unless separately requested. XCTest/Swift Testing execution compiles the target, so this implementation adds coverage source but verifies only with static checks.
- This work runs on `feature/project-templates-favorites` in the isolated worktree.

## File Structure

- Modify `Viabar/Models/Project.swift`: add favorite persistence and dedicated template entity relationships.
- Modify `Viabar/ViabarApp.swift`: register template model entities with the application container.
- Modify `Viabar/Services/ProjectService.swift`: add template CRUD, template-to-project deep copying, and favorite toggling.
- Modify `Viabar/Views/Component/NewProjectView.swift`: show searchable template selection only for project creation and launch template management.
- Create `Viabar/Views/Component/ProjectTemplateViews.swift`: implement template list, deletion confirmation, editor, color/icon inputs, and two-level task editing.
- Modify `Viabar/Views/Sidebar/SidebarView.swift`: show and toggle the sidebar favorite star.
- Modify `Viabar/ContentView.swift`: show and toggle favorite state on overview project cards.
- Modify `ViabarTests/ViabarTests.swift`: describe template-copy and favorite-state behavior with Swift Testing coverage to run only when compilation is authorized.

### Task 1: Add Persistent Template And Favorite Models

**Files:**
- Modify: `Viabar/Models/Project.swift`
- Modify: `Viabar/ViabarApp.swift`

- [x] **Step 1: Add project favorite storage**

Add `var isFavorite: Bool = false` beside the existing project state fields so
new and migrated projects default to not favorited.

- [x] **Step 2: Add dedicated template entities**

Add SwiftData models whose relationships mirror only the live task hierarchy:

```swift
@Model
final class ProjectTemplate {
    @Attribute(.unique) var templateId: UUID
    var name: String
    var hideCompleted: Bool
    var orderIndex: Int
    var accentColor: String
    var sfSymbolName: String

    @Relationship(deleteRule: .cascade, inverse: \TemplateMilestone.template)
    var milestones: [TemplateMilestone] = []
}

@Model
final class TemplateMilestone {
    @Attribute(.unique) var milestoneId: UUID
    var title: String
    var orderIndex: Int
    var template: ProjectTemplate?

    @Relationship(deleteRule: .cascade, inverse: \TemplateSubTask.milestone)
    var subtasks: [TemplateSubTask] = []
}

@Model
final class TemplateSubTask {
    @Attribute(.unique) var taskId: UUID
    var title: String
    var orderIndex: Int
    var milestone: TemplateMilestone?
}
```

- [x] **Step 3: Register all template entities in the app schema**

Append `ProjectTemplate.self`, `TemplateMilestone.self`, and
`TemplateSubTask.self` to the `Schema` in `ViabarApp`.

### Task 2: Implement Template Copy And Favorite Service Behavior

**Files:**
- Modify: `Viabar/Services/ProjectService.swift`
- Modify: `ViabarTests/ViabarTests.swift`

- [x] **Step 1: Add behavior coverage source**

Add Swift Testing cases that instantiate a template with one milestone and one
subtask, call the service creation path, and assert new identifiers, preserved
order/style/visibility, unfinished state, nil reminders, source independence,
and favorite toggling. These tests are intentionally not executed until the
user permits compilation.

- [x] **Step 2: Extend the service protocol and creation path**

Extend creation to accept `template: ProjectTemplate? = nil`; after inserting
the new project, copy sorted template milestones and subtasks into new live
entities. When a template is supplied use its `hideCompleted`, while keeping
the caller-provided final icon and color updates in the view.

- [x] **Step 3: Add template CRUD and favorite toggling**

Provide `saveTemplate(...)`, `deleteTemplate(_:)`, and
`toggleFavorite(_:)`. Template deletion cascades only through template
relationships; toggling favorite changes `Project.isFavorite` and saves.

### Task 3: Replace The New-Project Template Placeholder

**Files:**
- Modify: `Viabar/Views/Component/NewProjectView.swift`

- [x] **Step 1: Query and track templates only for creation behavior**

Add a sorted `@Query` for templates, selected-template ID, typed filter text,
and template-management presentation state. Resolve selection by ID so deletion
of the template while the sheet stays open safely yields no source template.

- [x] **Step 2: Render a searchable selection row only in create mode**

Replace the placeholder with a search field plus a filtered menu of templates
and a `square.3.layers.3d.middle.filled` management button. Wrap the section in
`if editingProject == nil` so project editing exposes no template UI.

- [x] **Step 3: Seed form style and copy template contents on creation**

When a template is selected assign its color and icon to the existing form
state. During create, pass the currently resolved template to the service; when
editing, keep the existing project-update path untouched.

### Task 4: Build Template Management And Editing UI

**Files:**
- Create: `Viabar/Views/Component/ProjectTemplateViews.swift`

- [x] **Step 1: Build the management sheet**

Query templates ordered by `orderIndex`, render horizontal rows with icon,
color, name, and task count, expose `plus.app`, and attach edit/delete context
actions. Use an alert before invoking `deleteTemplate(_:)` and state that
existing projects are unchanged.

- [x] **Step 2: Build the template editor inputs**

Provide template name, the existing `ColorCircle`/`CustomColorCircle` style
controls, a selected icon button with an icon-grid popover on its trailing
edge, and a "展示已完成任务" toggle bound inversely to `hideCompleted`.

- [x] **Step 3: Build editable two-level task drafts and save conversion**

Use local draft structs with stable IDs for milestones and subtasks; allow add,
delete, rename, and button-based up/down ordering. On save, discard blank
titles and rebuild the template's cascade-owned task tree in draft order,
without reminders or completion state.

### Task 5: Add Favorite Menus And Indicators

**Files:**
- Modify: `Viabar/Views/Sidebar/SidebarView.swift`
- Modify: `Viabar/ContentView.swift`

- [x] **Step 1: Add the sidebar star and context action**

Insert a yellow `star.fill` after the existing alarm and before percentage in
the dark sidebar content layer only, so it does not turn white beneath progress
fill. Add `收藏` / `取消收藏` in the row context menu backed by
`toggleFavorite(_:)`.

- [x] **Step 2: Add the overview card star and context action**

Resolve `ProjectService` from the environment in `OverviewProjectCard`, render
a yellow `star.fill` at the trailing end of the colored card header when
favorited, and add the matching context-menu action.

### Task 6: Static Verification

**Files:**
- Verify all modified and newly created feature files.

- [x] **Step 1: Inspect requirement coverage**

Search for the three template entities, template selection/menu management,
deletion confirmation text, `isFavorite`, `star.fill`, and favorite toggle
calls in their expected files.

- [x] **Step 2: Check diff formatting**

Run:

```bash
git diff --check
```

Expected: exit code `0` and no output.

- [x] **Step 3: Report the explicit validation boundary**

State that static checks ran, while build and automated test execution were not
run because the user instructed that code should not be compiled unless
requested.
