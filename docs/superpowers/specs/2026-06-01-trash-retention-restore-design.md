# Trash Retention And Restore Design

## Goal

Add a recoverable trash flow for deleted tasks, subtasks, and memos. Trash is
accessible from the bottom of the sidebar, searchable like global search, and
governed by a configurable retention period. Project deletion remains
permanent and requires two confirmations.

Source work and static verification proceed without compiling unless the user
explicitly authorizes a build or test run.

## Scope

### Included

- Deleted `Milestone`, `SubTask`, and `Memo` content.
- A sidebar trash entry and a wide trash browser panel.
- Search, restore, and copy-content actions.
- Configurable retention in `设置 > 数据`.
- Expired-trash cleanup once per application launch.
- Trash content in complete backup snapshots and full restore.
- Shared sidebar hover feedback for overview, active projects, archived
  projects, and the new trash entry.
- Two-step confirmation for permanent project deletion.

### Excluded

- Restoring deleted projects.
- Moving deleted project contents into trash when a project is deleted.
- A manual permanent-delete action for individual trash entries.
- Restoring a subtask to a different task.
- Restoring content into a newly created replacement project.

## Confirmed Product Decisions

- Trash uses an independent SwiftData snapshot model rather than soft-delete
  flags on active entities.
- Deleting a task that contains subtasks creates one task trash item. Its
  subtasks remain nested in the task snapshot and do not appear as separate
  trash rows.
- Deleting a subtask directly creates one subtask trash item.
- Project deletion is permanent. Existing trash items that reference the
  deleted project remain visible and copyable, but can no longer be restored.
- A deleted subtask can only return to its original parent task.
- Trash search uses localized, case-insensitive contains matching. Either the
  original project name or deleted content can match.
- Trash rows default to descending deletion time.
- The trash context menu contains only `恢复` and `复制内容`.
- Expired content is deleted automatically at application startup. There is no
  manual permanent-delete action.
- Trash retention choices are `30天`, `60天`, `90天`, and `永久`, with `90天`
  as the default.
- Complete backups include trash content, and full restore restores it.

## Sidebar Design

Add a fixed trash row at the bottom of the sidebar:

```text
[trash] 回收站
```

The trash row has no divider above it. Its normal background is transparent.
On pointer hover it displays a gray capsule background using the same shape as
the overview row.

Apply the same gray capsule hover feedback to all clickable sidebar rows:

- overview;
- active projects;
- archived projects;
- trash.

Existing selected-state presentation remains authoritative. Hover should not
replace or visually conflict with selected project styling.

## Trash Browser Panel

Clicking the sidebar trash row opens a wide browser-style panel. It should
provide enough width for deleted content, hierarchy paths, and deletion
timestamps without forcing aggressive truncation.

The panel contains:

1. A title: `回收站`.
2. A search field at the top.
3. A descending deletion-time list.
4. An empty state when there are no matching items.

Each row follows the information hierarchy of the existing global-search
result row:

- left: the original project's SF Symbol and accent color;
- first line: deleted content summary;
- second line: original hierarchy path;
- right: gray deletion-time text.

Path formats:

```text
项目名 / 任务
项目名 / 父任务内容最多10个字 / 子任务
项目名 / 备忘录
```

The panel can use the same compact-parent-title behavior as global search for
subtask paths.

## Search Behavior

The search field filters trash rows using localized,
case-insensitive-contains matching. A row is included when the term matches
either:

- original project name;
- task title;
- subtask title;
- memo content;
- nested subtask titles inside a deleted task snapshot.

Trimming leading and trailing whitespace from the search query follows the
existing global-search behavior. With an empty query, show all trash rows in
descending deletion-time order.

## Context Menu

Right-clicking a trash row presents:

```text
恢复
复制内容
```

`复制内容` is always enabled:

- task without subtasks: copy the task title;
- task with subtasks: copy the task title followed by its nested subtask
  titles as a readable hierarchy;
- subtask: copy the subtask title;
- memo: copy memo content.

`恢复` is conditionally enabled:

- task: enabled only while the original project exists;
- memo: enabled only while the original project exists;
- subtask: enabled only while the original project and original parent task
  both exist.

When restore is unavailable, keep the item visible and explain the disabled
state in the menu:

```text
原项目已不存在
原任务已不存在
```

## Trash Snapshot Model

Add a unified SwiftData model named `TrashItem`.

Each trash item stores:

- stable trash-item identifier;
- item kind: task, subtask, or memo;
- deletion timestamp;
- original project identifier;
- original project title;
- original project accent color;
- original project SF Symbol;
- original parent-task identifier for a directly deleted subtask;
- original order index;
- serialized content snapshot.

The content snapshot stores the recoverable entity-specific payload:

- task: title, completion state, completion timestamp, reminder snapshot, and
  all nested subtask snapshots;
- subtask: title, completion state, completion timestamp, and reminder
  snapshot;
- memo: content and original creation timestamp;
- nested subtask: title, completion state, completion timestamp, order index,
  and reminder snapshot.

Reminder snapshots store user intent, not derived
`NotificationScheduleEntry` records.

Use a versioned `Codable` payload so future snapshot evolution can be handled
explicitly without spreading optional columns across the active domain model.

## Delete Behavior

Route task, subtask, and memo deletion through `ProjectService`.

### Task

When deleting a `Milestone`:

1. Create one `TrashItem` with the task and all nested subtasks.
2. Remove notification timeline entries for the task and nested subtasks.
3. Delete the active task.
4. Save and resynchronize project-level reminder state.

### Subtask

When deleting a `SubTask` directly:

1. Create one `TrashItem` containing the subtask and its original parent-task
   identifier.
2. Remove its notification timeline entry.
3. Delete the active subtask.
4. Recompute parent completion and project-level reminder state.

### Memo

When deleting a `Memo`:

1. Create one `TrashItem`.
2. Delete the active memo.
3. Save.

## Restore Behavior

Restore reconstructs an active model object from its trash snapshot, then
removes the consumed trash item.

### Task

- Require the original project to exist.
- Recreate the task inside the original project.
- Recreate all nested subtasks.
- Insert at the original order index when possible.
- Normalize sibling order indexes after insertion.
- Rebuild applicable reminder timeline entries.

### Subtask

- Require the original project and original parent task to exist.
- Recreate the subtask under the original parent task.
- Insert at the original order index when possible.
- Normalize sibling order indexes.
- Recompute parent completion state.
- Rebuild applicable reminder timeline entries.

### Memo

- Require the original project to exist.
- Recreate the memo inside the original project.
- Insert at the original order index when possible.
- Normalize sibling order indexes.

## Permanent Project Deletion

Deleting a project never creates trash items. The project and all of its
current contents are permanently removed.

Replace the current single confirmation with two confirmations.

### First Confirmation

Show:

- project name;
- task count;
- memo count;
- a clear statement that deletion is permanent and cannot be restored.

The task count refers to top-level tasks (`Milestone`). Nested subtasks remain
represented by their parent tasks and are not added as separate task rows.

### Second Confirmation

After the user confirms the first prompt, present a final destructive warning
asking whether to permanently delete the project. Only the second confirmation
executes `ProjectService.deleteProject`.

Deleting the project does not remove previously created `TrashItem` snapshots.
Those snapshots remain searchable and copyable while their restore action
becomes unavailable.

## Settings Design

In `设置 > 数据`, insert a new group between `数据同步` and `数据备份`.

```text
回收站
保留期限                    [90天 v]
过期的将从本地和云端永久抹除
```

The retention picker contains:

- `30天`;
- `60天`;
- `90天`;
- `永久`.

Store the selected value in the singleton `AppSettings` record. The default is
`90天`. The explanatory text uses secondary styling.

## Startup Cleanup

Run trash-retention cleanup once during application startup after default
settings are available.

Cleanup behavior:

1. Resolve the retention policy from `AppSettings`.
2. For `永久`, skip deletion.
3. For 30, 60, or 90 days, calculate the cutoff relative to startup time.
4. Delete `TrashItem` records whose deletion timestamp is older than the
   cutoff.
5. Save the SwiftData context.

`TrashItem` joins the shared SwiftData schema. This keeps local persistence in
the shared store and preserves a single source of truth for future cloud-sync
activation.

## Backup And Full Restore

Extend the existing complete `BackupSnapshot` format to include trash
snapshots.

Backup must serialize:

- every `TrashItem`;
- its identifier, item kind, deletion timestamp, original location metadata,
  and versioned content payload.

Full restore must:

1. Remove current trash items together with the other recoverable database
   state.
2. Recreate trash items from the selected backup.
3. Rebuild active reminder timeline records from restored active reminder
   configuration only.
4. Run trash-retention cleanup against the restored `AppSettings` policy so
   expired restored items are permanently removed immediately.

Trash reminder snapshots stay dormant until their item is restored. They must
not generate notification timeline records merely because a backup was
restored.

## Localization

Add Simplified Chinese and English localization for:

- trash sidebar entry and panel title;
- search placeholder and empty state;
- restore and copy-content menu actions;
- unavailable-restore explanations;
- retention group, picker values, and explanatory copy;
- both project-deletion confirmations.

## Verification Strategy

Do not compile unless explicitly authorized.

Add source-level unit coverage for:

- task snapshot creation with nested subtasks;
- directly deleted subtask snapshots;
- memo snapshots;
- restore into original project;
- disabled restore after project deletion;
- disabled subtask restore after parent-task deletion;
- copied hierarchy text for tasks with subtasks;
- descending deletion-time ordering;
- project-name and content search;
- nested-subtask search inside deleted task snapshots;
- 30-day, 60-day, 90-day, and permanent retention policies;
- backup snapshot encoding of trash content;
- full restore recreation and immediate retention cleanup;
- restored trash reminder snapshots remaining dormant.

Perform static source checks:

- search task, subtask, and memo delete call sites to ensure they route through
  `ProjectService`;
- check the shared SwiftData schema includes `TrashItem`;
- check backup snapshot capture and restore both include trash items;
- run `git diff --check`.
