# iOS Archive, Project Editor, and Reminder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add archive-folder selection and relocation, full-row search navigation, compact shared project create/edit forms, and explicit-save reminder editing for iOS projects, milestones, and subtasks.

**Architecture:** Keep shared persistence and reminder scheduling unchanged. Add focused iOS SwiftUI sheets under `ViabariOS/Persistence`, pass selected models through explicit bindings or closures, and continue using `ProjectService` as the only write boundary so Widget reloads and `NotificationScheduleService` timeline synchronization remain centralized.

**Tech Stack:** SwiftUI, SwiftData queries, existing `ProjectService`, existing `Reminder` model, existing App Group store, shell static checks.

---

## File Structure

- Create `ViabariOS/Persistence/IOSPersistentArchiveFolderPicker.swift`: reusable multi-level archive-folder picker sheet.
- Create `ViabariOS/Persistence/IOSPersistentReminderEditor.swift`: iOS reminder draft editor with explicit Save and Delete actions.
- Modify `ViabariOS/Persistence/IOSPersistentOverviewView.swift`: sheet routing for project create/edit and archive picker; search-row hit testing.
- Modify `ViabariOS/Persistence/IOSPersistentArchiveView.swift`: archived-project `移动至...` action and picker routing.
- Modify `ViabariOS/Persistence/IOSPersistentProjectCreationView.swift`: turn create-only form into compact create/edit form and add project-reminder draft.
- Modify `ViabariOS/Persistence/IOSPersistentProjectDetailView.swift`: milestone/subtask reminder buttons and active-only editing.
- Modify `ViabariOS/en.lproj/Localizable.strings`: English translations.
- Modify `ViabariOS/zh-Hans.lproj/Localizable.strings`: Simplified Chinese keys.
- Modify `scripts/tests/test_ios_persistence_static.sh`: source-level regression guards without compilation.

## Task 1: Add Static Guards for the New iOS Surface

**Files:**
- Modify: `scripts/tests/test_ios_persistence_static.sh`

- [ ] **Step 1: Add failing source-level checks**

Append checks that require the new files and the intended service calls:

```bash
for file in \
    Persistence/IOSPersistentArchiveFolderPicker.swift \
    Persistence/IOSPersistentReminderEditor.swift; do
    [[ -f "$IOS_DIR/$file" ]] || fail "missing ViabariOS/$file"
done

rg -q 'moveProjectToFolder' "$IOS_DIR/Persistence/IOSPersistentArchiveView.swift" ||
    fail "archive view must support moving archived projects"
rg -q 'contentShape\\(Rectangle\\(\\)\\)' "$IOS_DIR/Persistence/IOSPersistentOverviewView.swift" ||
    fail "search result rows must define a full-row hit target"
rg -q 'editingProject: Project\\?' "$IOS_DIR/Persistence/IOSPersistentProjectCreationView.swift" ||
    fail "project form must support create and edit modes"
rg -q 'updateReminder\\(.*for: milestone\\)' "$IOS_DIR/Persistence/IOSPersistentProjectDetailView.swift" ||
    fail "milestone reminder editing must reuse ProjectService"
rg -q 'updateReminder\\(.*for: subtask\\)' "$IOS_DIR/Persistence/IOSPersistentProjectDetailView.swift" ||
    fail "subtask reminder editing must reuse ProjectService"
```

- [ ] **Step 2: Run the static script and verify it fails**

Run:

```bash
bash scripts/tests/test_ios_persistence_static.sh
```

Expected: FAIL because `IOSPersistentArchiveFolderPicker.swift` does not exist yet.

- [ ] **Step 3: Commit the guard when working in a clean isolated branch**

Do not commit automatically in the current dirty workspace. When the user requests a commit:

```bash
git add scripts/tests/test_ios_persistence_static.sh
git commit -m "test: guard ios archive and reminder surfaces"
```

## Task 2: Add the Reusable Archive Folder Picker

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistentArchiveFolderPicker.swift`
- Modify: `ViabariOS/en.lproj/Localizable.strings`
- Modify: `ViabariOS/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Create the picker sheet**

Add:

```swift
import SwiftUI

struct IOSPersistentArchiveFolderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let folders: [ArchiveFolder]
    let currentFolderID: UUID?
    let actionTitle: LocalizedStringKey
    let onConfirm: (ArchiveFolder) -> Void

    @State private var selectedFolderID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if rootFolders.isEmpty {
                    ContentUnavailableView(
                        "暂无归档文件夹",
                        systemImage: "folder",
                        description: Text("请先在归档页面新建文件夹")
                    )
                } else {
                    List {
                        ForEach(rootFolders, id: \.folderId) { folder in
                            IOSPersistentArchiveFolderPickerNode(
                                folder: folder,
                                level: 0,
                                selectedFolderID: $selectedFolderID
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("选择归档文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) { confirmSelection() }
                        .disabled(selectedFolderID == nil || selectedFolderID == currentFolderID)
                }
            }
        }
    }

    private var rootFolders: [ArchiveFolder] {
        folders.filter { $0.parent == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

}

private struct IOSPersistentArchiveFolderPickerNode: View {
    let folder: ArchiveFolder
    let level: Int
    @Binding var selectedFolderID: UUID?

    var body: some View {
        Button {
            selectedFolderID = folder.folderId
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedFolderID == folder.folderId ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedFolderID == folder.folderId ? Color.accentColor : .secondary)
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder.name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.leading, CGFloat(level) * 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        ForEach(folder.children.sorted { $0.orderIndex < $1.orderIndex }, id: \.folderId) { child in
            IOSPersistentArchiveFolderPickerNode(
                folder: child,
                level: level + 1,
                selectedFolderID: $selectedFolderID
            )
        }
    }
}
```

Keep `confirmSelection()` inside `IOSPersistentArchiveFolderPicker`:

```swift
private func confirmSelection() {
    guard let selectedFolderID,
          selectedFolderID != currentFolderID,
          let folder = folders.first(where: { $0.folderId == selectedFolderID })
    else { return }
    onConfirm(folder)
    dismiss()
}
```

- [ ] **Step 2: Add localized picker strings**

Append to both iOS localization files:

```text
"选择归档文件夹"
"请先在归档页面新建文件夹"
"移动至..."
```

Translate the English values as:

```text
"Choose Archive Folder"
"Create a folder from the Archive page first."
"Move To..."
```

- [ ] **Step 3: Run plist lint**

Run:

```bash
plutil -lint ViabariOS/en.lproj/Localizable.strings ViabariOS/zh-Hans.lproj/Localizable.strings
```

Expected: both files report `OK`.

## Task 3: Route Active Archive, Archived Relocation, and Full-Row Search Taps

**Files:**
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentArchiveView.swift`

- [ ] **Step 1: Replace overview inline archive behavior with picker state**

In `IOSPersistentOverviewView`, replace the title composer editing states with:

```swift
@State private var editingProject: Project?
@State private var archivePickerProject: Project?
```

Present:

```swift
.sheet(item: $editingProject) { project in
    IOSPersistentProjectCreationView(editingProject: project)
}
.sheet(item: $archivePickerProject) { project in
    IOSPersistentArchiveFolderPicker(
        folders: archiveFolders,
        currentFolderID: nil,
        actionTitle: "归档"
    ) { folder in
        services.projectService?.archiveProject(project, to: folder)
    }
}
```

Make overview-card callbacks assign these states:

```swift
onEdit: { editingProject = project },
onArchive: { archivePickerProject = project },
```

Remove `editingProjectID`, `composerText`, `beginEditing`, `saveProjectTitle`, and the editing footer branch.

- [ ] **Step 2: Route detail active-project archive through the same picker**

In `IOSPersistentProjectDetailView`, import SwiftData and add:

```swift
import SwiftData

@Query(sort: \ArchiveFolder.orderIndex) private var archiveFolders: [ArchiveFolder]
@State private var isArchiveFolderPickerPresented = false
```

For active projects, make the menu archive action set the state. For archived projects, keep direct unarchive. Present:

```swift
.sheet(isPresented: $isArchiveFolderPickerPresented) {
    IOSPersistentArchiveFolderPicker(
        folders: archiveFolders,
        currentFolderID: nil,
        actionTitle: "归档"
    ) { folder in
        services.projectService?.archiveProject(project, to: folder)
    }
}
```

- [ ] **Step 3: Add archived-project relocation**

Keep picker presentation state in the parent `IOSPersistentArchiveView`, pass an `onMoveProject` closure into recursive archive nodes, and add:

```swift
@State private var movingProject: Project?
```

Present the picker with:

```swift
IOSPersistentArchiveFolderPicker(
    folders: archiveFolders,
    currentFolderID: project.archiveFolder?.folderId,
    actionTitle: "移动"
) { folder in
    services.projectService?.moveProjectToFolder(project, folder: folder)
}
```

Add the archived-project context-menu item:

```swift
Button("移动至...", systemImage: "folder") {
    onMoveProject(project)
}
```

- [ ] **Step 4: Make search-result rows fill their button hit region**

In `IOSPersistentSearchView`, add to the result label container:

```swift
.frame(maxWidth: .infinity, alignment: .leading)
.contentShape(Rectangle())
```

Add to the button:

```swift
.frame(maxWidth: .infinity, alignment: .leading)
```

- [ ] **Step 5: Run the static script**

Run:

```bash
bash scripts/tests/test_ios_persistence_static.sh
```

Expected: remaining FAIL points refer only to the not-yet-implemented shared project form or reminder editor.

## Task 4: Add the Explicit-Save iOS Reminder Editor

**Files:**
- Create: `ViabariOS/Persistence/IOSPersistentReminderEditor.swift`
- Modify: `ViabariOS/en.lproj/Localizable.strings`
- Modify: `ViabariOS/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Create the draft editor**

Add an iOS sheet with this interface:

```swift
struct IOSPersistentReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let reminder: Reminder?
    let onSubmit: (Reminder?) -> Void

    @State private var selectedDate: Date
    @State private var selectedTime: Date
    @State private var repeatOption: IOSReminderRepeatOption

    init(reminder: Reminder?, onSubmit: @escaping (Reminder?) -> Void) {
        self.reminder = reminder
        self.onSubmit = onSubmit
        let timestamp = reminder?.fireTimestamp ?? Date()
        _selectedDate = State(initialValue: timestamp)
        _selectedTime = State(initialValue: timestamp)
        _repeatOption = State(initialValue: IOSReminderRepeatOption(reminder: reminder))
    }
}
```

Use a compact `Form` with Date, Time, and Repeat rows. Add navigation toolbar actions:

```swift
ToolbarItem(placement: .cancellationAction) {
    Button("删除", role: .destructive) {
        onSubmit(nil)
        dismiss()
    }
    .disabled(reminder == nil)
}

ToolbarItem(placement: .confirmationAction) {
    Button("保存") {
        onSubmit(buildReminder())
        dismiss()
    }
}
```

Port the existing macOS repeat cases exactly:

```swift
never, hourly, daily, every2Days, every3Days, weekdays,
weekly, biweekly, monthly, every3Months, every6Months, yearly
```

Build `Reminder` with the same values as macOS:

```swift
Reminder(
    type: repeatOption == .never ? "single" : "repeating",
    fireTime: repeatOption == .never ? nil : selectedTime.fireTimeString,
    fireTimestamp: selectedDate.combined(withTimeFrom: selectedTime),
    repeatIntervalDays: repeatOption.repeatIntervalDays
)
```

Do not add `.onDisappear` persistence.

- [ ] **Step 2: Add any missing reminder-editor localization keys**

Ensure both iOS localization files contain:

```text
"通知提醒"
"日期"
"时间"
"重复"
"删除"
"保存"
"永不"
"每小时"
"每天"
"每2天"
"每3天"
"工作日"
"每周"
"每两周"
"每月"
"每3个月"
"每6个月"
"每年"
```

- [ ] **Step 3: Lint localization**

Run:

```bash
plutil -lint ViabariOS/en.lproj/Localizable.strings ViabariOS/zh-Hans.lproj/Localizable.strings
```

Expected: both files report `OK`.

## Task 5: Convert the iOS Project Form to Compact Create and Edit Modes

**Files:**
- Modify: `ViabariOS/Persistence/IOSPersistentProjectCreationView.swift`
- Modify: `ViabariOS/Persistence/IOSPersistentOverviewView.swift`

- [ ] **Step 1: Add edit-mode state initialization**

Change the form signature to:

```swift
struct IOSPersistentProjectCreationView: View {
    let editingProject: Project?

    @State private var title: String
    @State private var selectedTemplateID: UUID?
    @State private var accentColor: String
    @State private var symbolName: String
    @State private var projectReminder: Reminder?
    @State private var isReminderEditorPresented = false

    init(editingProject: Project? = nil) {
        self.editingProject = editingProject
        _title = State(initialValue: editingProject?.title ?? "")
        _selectedTemplateID = State(initialValue: nil)
        _accentColor = State(initialValue: editingProject?.accentColor ?? ViabarColor.palette[0].hex)
        _symbolName = State(initialValue: editingProject?.sfSymbolName ?? commonSymbols[0])
        _projectReminder = State(initialValue: Self.copyReminder(editingProject?.reminder))
    }
}
```

- [ ] **Step 2: Make the form compact and mode-aware**

Use a name row with alarm button:

```swift
HStack {
    TextField("项目名称", text: $title)
    Button {
        isReminderEditorPresented = true
    } label: {
        Image(systemName: projectReminder == nil ? "alarm" : "alarm.fill")
            .foregroundStyle(projectReminder == nil ? Color.secondary : .orange)
    }
}
```

Wrap the template picker in:

```swift
if editingProject == nil {
    Picker("模板", selection: $selectedTemplateID) {
        Text("不使用模板").tag(UUID?.none)
        ForEach(templates) { template in
            Label(template.name, systemImage: template.sfSymbolName)
                .tag(Optional(template.templateId))
        }
    }
}
```

Present:

```swift
.sheet(isPresented: $isReminderEditorPresented) {
    IOSPersistentReminderEditor(reminder: projectReminder) {
        projectReminder = $0
    }
}
```

Use compact sheet sizing:

```swift
.presentationDetents([.medium])
```

- [ ] **Step 3: Submit create or edit with copied reminder state**

Replace `createProject()` with:

```swift
private func commitProject() {
    guard !trimmedTitle.isEmpty, let projectService = services.projectService else { return }
    let template = editingProject == nil
        ? templates.first { $0.templateId == selectedTemplateID }
        : nil
    let project = editingProject ?? projectService.createProject(title: trimmedTitle, template: template)
    project.title = trimmedTitle
    project.accentColor = accentColor
    project.sfSymbolName = symbolName
    project.reminder = Self.copyReminder(projectReminder)
    projectService.updateProject(project)
    dismiss()
}
```

Add `copyReminder(_:)` using the macOS field copy:

```swift
Reminder(
    type: reminder.type,
    fireTime: reminder.fireTime,
    fireTimestamp: reminder.fireTimestamp,
    repeatIntervalDays: reminder.repeatIntervalDays
)
```

Switch navigation title and submit label by mode:

```swift
editingProject == nil ? "新建项目" : "编辑项目"
editingProject == nil ? "创建" : "保存"
```

- [ ] **Step 4: Confirm overview edit action routes to the form**

Ensure:

```swift
.sheet(item: $editingProject) { project in
    IOSPersistentProjectCreationView(editingProject: project)
}
```

and no bottom title composer remains in `IOSPersistentOverviewView`.

## Task 6: Wire Milestone and Subtask Reminder Buttons

**Files:**
- Modify: `ViabariOS/Persistence/IOSPersistentProjectDetailView.swift`

- [ ] **Step 1: Add a typed reminder-editor target**

Add:

```swift
private enum IOSPersistentReminderEditorTarget: Identifiable {
    case milestone(Milestone)
    case subtask(SubTask)

    var id: UUID {
        switch self {
        case .milestone(let milestone): milestone.milestoneId
        case .subtask(let subtask): subtask.taskId
        }
    }

    var reminder: Reminder? {
        switch self {
        case .milestone(let milestone): milestone.reminder
        case .subtask(let subtask): subtask.reminder
        }
    }
}
```

Add state:

```swift
@State private var reminderEditorTarget: IOSPersistentReminderEditorTarget?
```

- [ ] **Step 2: Present the reminder sheet and submit through ProjectService**

Add:

```swift
.sheet(item: $reminderEditorTarget) { target in
    IOSPersistentReminderEditor(reminder: target.reminder) { reminder in
        switch target {
        case .milestone(let milestone):
            services.projectService?.updateReminder(reminder, for: milestone)
        case .subtask(let subtask):
            services.projectService?.updateReminder(reminder, for: subtask)
        }
    }
}
```

- [ ] **Step 3: Make alarm icons editable only for active projects**

Replace the display-only reminder helper with:

```swift
@ViewBuilder
private func reminderControl(
    _ reminder: Reminder?,
    onEdit: @escaping () -> Void
) -> some View {
    let icon = reminder == nil ? "alarm" : "alarm.fill"
    let color = reminder?.displayFireDate.map(IOSPrototypeReminderStyle.color) ?? .tertiary
    if project.isArchived {
        Image(systemName: icon)
            .foregroundStyle(color)
    } else {
        Button(action: onEdit) {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}
```

Call it from milestone and subtask rows:

```swift
reminderControl(milestone.reminder) {
    reminderEditorTarget = .milestone(milestone)
}

reminderControl(subtask.reminder) {
    reminderEditorTarget = .subtask(subtask)
}
```

This preserves archive read-only behavior.

## Task 7: Finish Localization and Static Verification

**Files:**
- Modify: `ViabariOS/en.lproj/Localizable.strings`
- Modify: `ViabariOS/zh-Hans.lproj/Localizable.strings`
- Modify: `scripts/tests/test_ios_persistence_static.sh`

- [ ] **Step 1: Add any remaining visible strings**

Ensure both localization files include keys added by the implementation, including:

```text
"移动"
"移动至..."
"选择归档文件夹"
"请先在归档页面新建文件夹"
"编辑项目"
```

- [ ] **Step 2: Run the required static script**

Run:

```bash
bash scripts/tests/test_ios_persistence_static.sh
```

Expected:

```text
PASS: iOS persistence static checks
```

- [ ] **Step 3: Run repository static verification**

Run:

```bash
git diff --check
plutil -lint ViabariOS/Info.plist Viabar.xcodeproj/project.pbxproj
plutil -lint ViabariOS/en.lproj/Localizable.strings ViabariOS/zh-Hans.lproj/Localizable.strings
rg -n "@Model|Schema\\(|ModelContainer|ModelConfiguration" Viabar ViabarWidget ViabarTests --glob '*.swift'
rg -n "legacyStoreURL|applicationSupportDirectory|default\\.store|trash\\.store|ViabarSharedStore|cloudKitDatabase" Viabar ViabarWidget ViabarTests --glob '*.swift'
rg -n "BackupSnapshot|BackupSettingsSnapshot|decodeIfPresent|init\\(from decoder" Viabar ViabarTests --glob '*.swift'
```

Expected:

- `git diff --check` has no output.
- All plist/string lint commands report `OK`.
- Schema searches show the existing shared App Group architecture only; no iOS-local `@Model` or parallel store is introduced.

- [ ] **Step 4: Hand off manual verification**

Ask the user to build in Xcode and verify:

1. Archive an active project into a nested existing folder.
2. Move an archived project to another nested folder.
3. Tap the empty trailing portion of a global-search result.
4. Create a project with template, symbol, color, and reminder.
5. Edit a project without seeing template controls.
6. Confirm the form is compact and has minimal bottom whitespace.
7. Save and delete milestone and subtask reminders.
8. Dismiss reminder editing without Save and confirm no change.
9. Confirm archived detail remains read-only.
