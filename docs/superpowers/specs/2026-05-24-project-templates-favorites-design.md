# Project Templates And Favorites Design

## Goal

Add reusable project templates for initializing new projects, and add a favorite
marker that highlights selected projects in the active-project sidebar and
overview cards.

## Scope

This change includes:

- independently managed project templates;
- template selection in the new-project form only;
- initialization of new projects from template style and two-level task content;
- project favorite state and favorite toggling;
- favorite indicators in active sidebar rows and overview project cards.

This change does not include:

- deriving a template from an existing project;
- template reminders, memos, archive state, completion state, or favorite state;
- showing template selection while editing an existing project;
- favorite indicators in archived-project rows.

## Data Model

### Template Models

Templates are stored separately from real projects using SwiftData entities:

- `ProjectTemplate`
  - `templateId: UUID`
  - `name: String`
  - `hideCompleted: Bool`
  - `accentColor: String`
  - `sfSymbolName: String`
  - `orderIndex: Int`
  - cascade relationship to `TemplateMilestone`
- `TemplateMilestone`
  - `milestoneId: UUID`
  - `title: String`
  - `orderIndex: Int`
  - relationship back to `ProjectTemplate`
  - cascade relationship to `TemplateSubTask`
- `TemplateSubTask`
  - `taskId: UUID`
  - `title: String`
  - `orderIndex: Int`
  - relationship back to `TemplateMilestone`

Template tasks have no completion state and no reminder relationship. This keeps
templates as creation blueprints rather than live project content.

### Favorite State

Add `isFavorite: Bool = false` to `Project`. Favorite state belongs only to a
created project; templates do not store or initialize it.

## Template Creation Behavior

Creating a new project without a selected template keeps the existing flow:
the entered title, current form color, current form icon, and empty task list
create the project.

Selecting a template in the new-project form:

- applies the template's `accentColor` to the form color selection;
- applies the template's `sfSymbolName` to the form icon selection;
- remembers the selected template as the source for task initialization;
- does not prevent subsequent manual color or icon changes in the form.

When the user creates a project with a selected template:

- the project title comes from the new-project form;
- the final icon and color come from the form's current values, including any
  user changes made after selecting the template;
- `hideCompleted` is initialized from the template;
- template milestones and subtasks are copied into new `Milestone` and
  `SubTask` entities in template order;
- copied milestones and subtasks start unfinished and without reminders;
- no project-level reminder, memo, archive state, or favorite state comes from
  the template.

The template and created project remain independent after creation. Editing or
deleting the template does not alter previously created projects.

## New Project Form

`NewProjectView` shows the template section only when creating a project
(`editingProject == nil`). Editing an existing project continues to show project
name, reminder, icon, and color controls without template selection or template
management controls.

In creation mode the template section contains:

- a searchable template picker that filters template options by typed name;
- a placeholder when no template is selected;
- a management button on the right using
  `square.3.layers.3d.middle.filled`.

Choosing a template immediately updates the existing icon and color selection
controls. The form remains the authority for final icon and color values at
creation time.

## Template Management

The management button opens a separate template-management sheet.

The sheet shows all templates as horizontal rows. Each row displays the
template icon, template name, theme-color cue, and a concise task count.
The top-right `plus.app` button opens template creation.

A context menu on each existing template supports:

- edit;
- delete.

Deleting a template always requires confirmation. The confirmation explains that
the template and its predefined tasks will be deleted, while projects previously
created from the template are unaffected.

## Template Editor

Template creation and editing use a dedicated editor sheet. It supports:

- template name;
- default color, using the same preset and custom-color controls as the
  new-project form;
- default icon, displayed as a selected icon button whose icon grid opens in a
  right-side popover;
- `hideCompleted`, defaulting to `true` at the persisted project-model level but
  presented as "展示已完成任务", defaulting to off for newly created templates;
- a two-level task editor for milestones and subtasks.

The display toggle is defined in user-facing terms:

- toggle off by default means `hideCompleted == true`;
- toggle on means `hideCompleted == false`.

The task editor supports adding, editing, deleting, and ordering milestones and
their subtasks. It does not expose completion controls, reminders, or memos.

## Favorite Interaction

The active project sidebar row context menu includes:

- `收藏` with a star icon when `project.isFavorite == false`;
- `取消收藏` when `project.isFavorite == true`.

The overview project card context menu exposes the same toggle so the state can
be controlled from either project surface.

Toggling favorite updates only `Project.isFavorite` and saves the project. It
does not affect active ordering, archived state, reminders, task contents, or
template behavior.

## Favorite Indicators

### Active Sidebar Row

For active projects, the right-side status content order is:

1. reminder alarm icon, when the existing reminder visibility rule is met;
2. yellow `star.fill`, when the project is favorited;
3. progress percentage.

The favorite star remains yellow regardless of progress fill coverage. The
existing reminder and percentage rendering behavior is otherwise preserved.

### Overview Card

For each favorited project, the colorful header of its overview card shows a
yellow `star.fill` at the far right. Non-favorited cards do not reserve a visible
star.

Archived-project rows do not display a favorite indicator or add a favorite
context-menu action in this change. An archived favorited project retains its
stored favorite state and displays the indicator again if restored.

## Service And View Boundaries

- Register `ProjectTemplate`, `TemplateMilestone`, and `TemplateSubTask` in the
  app SwiftData schema and any affected preview schemas.
- Extend `ProjectService` with a creation path that can initialize a project
  from a selected template and with a favorite toggle/save entry point.
- Keep template management CRUD separate from notification scheduling and
  archive lifecycle logic.
- Let `NewProjectView` own selected-template form state and presentation of
  template management.
- Implement template-list and template-editor UI in focused new SwiftUI view
  files rather than expanding the existing project form with unrelated editing
  concerns.
- Render favorite status in `ActiveProjectRow` and `OverviewProjectCard` using
  their current visual structures.

## Error And Empty States

- The new-project picker displays an empty state when no templates exist and
  keeps project creation available without a template.
- A blank template name cannot be saved.
- Blank task or subtask text is not persisted.
- Deleting a template is cancelled without data changes unless the confirmation
  action is accepted.
- If a selected template is deleted while the new-project form remains open,
  creation proceeds without copying template tasks unless that template is still
  resolvable at commit time; manually chosen form color and icon remain intact.

## Verification

Where logic can be isolated, tests should cover:

- copying a template creates a project with new milestone and subtask entities
  in the defined order;
- copied tasks are unfinished and have no reminders;
- modifying a created project does not mutate its source template;
- modifying or deleting a template does not mutate existing projects;
- a project defaults to not favorited and favorite toggling persists its state.

In accordance with the repository instruction, do not compile or run build/test
commands unless explicitly authorized. Perform static review and
`git diff --check` during implementation verification.
