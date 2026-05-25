# Native Settings Sidebar And Shortcut Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the existing Settings scene as a compact macOS 26-style inset fixed-sidebar window, replace shortcut text editing with keyboard recording, rename the data category, and persist an enabled-by-default automatic-update preference.

**Architecture:** Keep `AppSettings` as the single SwiftData source of truth and extend it with one update-preference field plus a pure `ShortcutKeyCombination` formatter/parser. Build the fixed rounded sidebar and detail cards in SwiftUI, while a focused `NSViewRepresentable` bridge captures keyboard events and sends only canonical shortcut strings or cancellation back to the view. This plan builds on the existing uncommitted settings/date-format implementation already present in the worktree.

**Tech Stack:** SwiftUI, SwiftData, AppKit `NSViewRepresentable` / `NSEvent`, Swift Testing.

**Repository Constraint:** Do not run `xcodebuild`, tests, previews, or any command that compiles code unless the user explicitly authorizes it. Red/green test commands below are required for strict TDD but must remain paused until that authorization is given; without it, only source-level validation can be reported.

---

## File Map

- Modify `Viabar/Models/AppSettings.swift`: add automatic-update persistence and pure shortcut canonicalization/display helpers.
- Modify `ViabarTests/ViabarTests.swift`: specify model defaults and shortcut conversion behavior before production implementation.
- Create `Viabar/Views/Settings/ShortcutRecorderField.swift`: own the smallest AppKit first-responder bridge needed to capture shortcut key events.
- Modify `Viabar/ViabarApp.swift`: let Settings content extend into its hidden titlebar so native traffic lights sit over the inset sidebar header area.
- Modify `Viabar/Views/Settings/SettingsView.swift`: replace collapsible split layout and text fields with the confirmed inset sidebar, compact detail cards, recorder fields, data rename, and About toggle.

### Task 1: Persist Update Preference And Specify Shortcut Conversion

**Files:**
- Modify: `ViabarTests/ViabarTests.swift`
- Modify: `Viabar/Models/AppSettings.swift`

- [x] **Step 1: Add failing behavioral expectations**

Extend `AppSettingsTests.initializesDocumentedDefaults()` with:

```swift
#expect(settings.automaticallyChecksForUpdates == true)
```

Add these tests in `AppSettingsTests`:

```swift
@Test func rendersStoredShortcutValuesWithMacSymbols() {
    #expect(ShortcutKeyCombination.displayString(for: "Option+V") == "⌥ V")
    #expect(ShortcutKeyCombination.displayString(for: "Command+F") == "⌘ F")
    #expect(
        ShortcutKeyCombination.displayString(for: "Control+Option+Shift+Command+Left")
            == "⌃ ⌥ ⇧ ⌘ ←"
    )
}

@Test func createsCanonicalStoredShortcutValues() {
    #expect(
        ShortcutKeyCombination(
            modifiers: [.command, .shift],
            key: .character("f")
        ).storedValue == "Shift+Command+F"
    )
    #expect(
        ShortcutKeyCombination(
            modifiers: [.option],
            key: .space
        ).storedValue == "Option+Space"
    )
}

@Test func rejectsShortcutWithoutModifiersOrWithEscape() {
    #expect(ShortcutKeyCombination(modifiers: [], key: .character("V")) == nil)
    #expect(ShortcutKeyCombination(modifiers: [.command], key: .escape) == nil)
}
```

- [ ] **Step 2: Run the red test only after compile authorization**

After explicit user permission to compile/tests, run:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/AppSettingsTests
```

Expected: failure because `automaticallyChecksForUpdates` and
`ShortcutKeyCombination` do not exist yet.

Until authorization exists, do not run this command and record the red phase
as intentionally blocked by repository policy.

- [x] **Step 3: Add model defaults and pure shortcut representation**

In `AppSettings`, add a stored default so an existing local settings store can
adopt the new non-optional preference safely:

```swift
var automaticallyChecksForUpdates: Bool = true
```

Add an initializer parameter and assignment:

```swift
automaticallyChecksForUpdates: Bool = true
// ...
self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
```

In the same model/support file, add a pure helper used by both the view and
tests:

```swift
struct ShortcutKeyCombination: Equatable {
    enum Modifier: String, CaseIterable {
        case control = "Control"
        case option = "Option"
        case shift = "Shift"
        case command = "Command"

        var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    enum Key: Equatable {
        case character(String)
        case space
        case `return`
        case tab
        case delete
        case up
        case down
        case left
        case right
        case escape

        var storedValue: String {
            switch self {
            case .character(let value): value.uppercased()
            case .space: "Space"
            case .return: "Return"
            case .tab: "Tab"
            case .delete: "Delete"
            case .up: "Up"
            case .down: "Down"
            case .left: "Left"
            case .right: "Right"
            case .escape: "Escape"
            }
        }

        var displayValue: String {
            switch self {
            case .character(let value): value.uppercased()
            case .space: "Space"
            case .return: "Return"
            case .tab: "Tab"
            case .delete: "⌫"
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            case .escape: "Esc"
            }
        }
    }

    let modifiers: [Modifier]
    let key: Key

    init?(modifiers: [Modifier], key: Key) {
        let ordered = Modifier.allCases.filter { modifiers.contains($0) }
        guard !ordered.isEmpty, key != .escape else { return nil }
        self.modifiers = ordered
        self.key = key
    }

    var storedValue: String {
        (modifiers.map(\.rawValue) + [key.storedValue]).joined(separator: "+")
    }

    var displayValue: String {
        (modifiers.map(\.symbol) + [key.displayValue]).joined(separator: " ")
    }

    static func displayString(for storedValue: String) -> String {
        let components = storedValue.split(separator: "+").map(String.init)
        guard let last = components.last,
              let key = key(from: last) else {
            return storedValue
        }
        let modifiers = components.dropLast().compactMap(Modifier.init(rawValue:))
        guard modifiers.count == components.count - 1,
              let shortcut = ShortcutKeyCombination(modifiers: modifiers, key: key) else {
            return storedValue
        }
        return shortcut.displayValue
    }

    private static func key(from storedValue: String) -> Key? {
        switch storedValue {
        case "Space": .space
        case "Return": .return
        case "Tab": .tab
        case "Delete": .delete
        case "Up": .up
        case "Down": .down
        case "Left": .left
        case "Right": .right
        case "Escape": .escape
        default:
            storedValue.count == 1 ? .character(storedValue) : nil
        }
    }
}
```

- [ ] **Step 4: Run the green test only after compile authorization**

After explicit permission, rerun the scoped `xcodebuild test` command from
Step 2.

Expected: `AppSettingsTests` pass.

### Task 2: Capture Keyboard Shortcuts Through A Small AppKit Bridge

**Files:**
- Create: `Viabar/Views/Settings/ShortcutRecorderField.swift`

- [x] **Step 1: Add an AppKit recorder view with narrow callbacks**

Create `ShortcutRecorderField.swift` with a SwiftUI surface and a first
responder capture view:

```swift
import AppKit
import SwiftUI

struct ShortcutRecorderField: View {
    let value: String
    @Binding var isRecording: Bool
    let onRecord: (String) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isRecording ? 1.5 : 1
                )

            Text(isRecording ? "请按键..." : ShortcutKeyCombination.displayString(for: value))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
        }
        .frame(minWidth: 94, minHeight: 28)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .background {
            ShortcutRecorderBridge(isRecording: $isRecording, onRecord: onRecord)
        }
        .onTapGesture { isRecording = true }
        .accessibilityLabel("设置快捷键")
        .accessibilityValue(isRecording ? "正在录制" : ShortcutKeyCombination.displayString(for: value))
    }
}

private struct ShortcutRecorderBridge: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (String) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onCancel = { isRecording = false }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onRecord = { storedValue in
            onRecord(storedValue)
            isRecording = false
        }
        view.onCancel = { isRecording = false }
        if isRecording, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        }
    }

    final class RecorderView: NSView {
        var onRecord: ((String) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onCancel?()
                return
            }
            guard let combination = event.shortcutCombination else { return }
            onRecord?(combination.storedValue)
        }
    }
}
```

- [x] **Step 2: Translate AppKit key events at the bridge boundary**

Add the `NSEvent` conversion in the same file so AppKit details remain outside
the settings view:

```swift
private extension NSEvent {
    var shortcutCombination: ShortcutKeyCombination? {
        let modifiers: [ShortcutKeyCombination.Modifier] = [
            modifierFlags.contains(.control) ? .control : nil,
            modifierFlags.contains(.option) ? .option : nil,
            modifierFlags.contains(.shift) ? .shift : nil,
            modifierFlags.contains(.command) ? .command : nil,
        ].compactMap { $0 }

        let key: ShortcutKeyCombination.Key?
        switch keyCode {
        case 36, 76: key = .return
        case 48: key = .tab
        case 49: key = .space
        case 51, 117: key = .delete
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 53: key = .escape
        default:
            key = charactersIgnoringModifiers.flatMap {
                $0.count == 1 ? .character($0) : nil
            }
        }

        guard let key else { return nil }
        return ShortcutKeyCombination(modifiers: modifiers, key: key)
    }
}
```

When implementing, ensure clicking a second field switches the `isRecording`
state held by the parent view; only one bridge may be recording at a time.

### Task 3: Replace The Collapsible Settings Layout With The Confirmed Surface

**Files:**
- Modify: `Viabar/ViabarApp.swift`
- Modify: `Viabar/Views/Settings/SettingsView.swift`

- [x] **Step 1: Extend Settings content beneath the native traffic lights**

Apply the same hidden-titlebar presentation already used by the application's
primary window:

```swift
Settings {
    SettingsView()
        .modelContainer(sharedModelContainer)
}
.windowStyle(.hiddenTitleBar)
```

The custom sidebar reserves top padding for the native traffic lights; it must
not draw imitation red/yellow/green circles or provide a custom close action.

- [x] **Step 2: Use explicit selection and a fixed inset sidebar**

Rename the category and replace `NavigationSplitView` with a custom `HStack`
that cannot collapse:

```swift
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用"
    case display = "显示"
    case shortcuts = "快捷键"
    case data = "数据"
    case about = "关于"
    // keep the existing icon switch with `.data` replacing `.syncAndBackup`
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var selection: SettingsCategory = .general

    var body: some View {
        HStack(spacing: 18) {
            SettingsSidebar(selection: $selection)
                .frame(width: 204)

            if let settings = settingsRecords.first {
                SettingsDetailView(category: selection, settings: settings)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { AppSettingsStore.ensureDefaultSettings(in: modelContext) }
            }
        }
        .padding(12)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 500, idealHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
```

Implement `SettingsSidebar` with top content padding that leaves room for the
native titlebar buttons, followed by a compact vertical list of plain buttons
inside:

```swift
.glassEffect(
    .regular,
    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
)
.overlay {
    RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
}
```

Each sidebar button uses `.font(.system(size: 14, weight: .medium))`,
approximately `38` points of row height, and a rounded selected fill based on
`Color(nsColor: .selectedContentBackgroundColor)`. Do not create a toolbar or
split-view sidebar-toggle command.

- [x] **Step 3: Render compact grouped settings cards**

Refactor `SettingsDetailView` to use a scroll view with compact typography:

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 22) {
        Text(category.rawValue)
            .font(.system(size: 20, weight: .semibold))

        panelContent
    }
    .frame(maxWidth: 560, alignment: .leading)
    .padding(.top, 13)
    .padding(.horizontal, 18)
    .padding(.bottom, 20)
}
```

Replace large grouped `Form` presentation with focused reusable group and row
views:

```swift
private struct SettingsGroup<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    // title uses 15 point semibold; rows sit in a rounded controlBackground card
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    let control: Control

    init(
        _ title: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }
    // primary label uses 13 point; optional detail uses 11 point secondary text
}
```

Keep all existing persisted controls, using native `Toggle` and `Picker`
controls as each row's trailing control. The renamed `.data` category still
contains the `数据同步` and `数据备份` groups.

- [x] **Step 4: Wire recorder rows and the About update toggle**

Add view-local recording selection:

```swift
private enum ShortcutAction {
    case toggleMainPanel
    case openSearch
}

@State private var recordingShortcut: ShortcutAction?
```

Use the recorder controls:

```swift
ShortcutRecorderField(
    value: settings.toggleMainPanelShortcut,
    isRecording: recordingBinding(for: .toggleMainPanel)
) {
    settings.toggleMainPanelShortcut = $0
}

ShortcutRecorderField(
    value: settings.openSearchShortcut,
    isRecording: recordingBinding(for: .openSearch)
) {
    settings.openSearchShortcut = $0
}
```

The binding sets `recordingShortcut` to the clicked row or clears it on
cancel/completion. Remove the old editable text-field shortcut bindings.

In `aboutPanel`, place this row immediately after the version row:

```swift
SettingsRow("自动更新") {
    Toggle("", isOn: $settings.automaticallyChecksForUpdates)
        .labelsHidden()
        .toggleStyle(.switch)
}
```

- [x] **Step 5: Verify UI source requirements without compiling**

Run:

```bash
rg -n "NavigationSplitView|数据同步与备份|TextField\\(\"全局显示|TextField\\(\"打开搜索|ShortcutRecorderField|automaticallyChecksForUpdates|case data = \"数据\"" Viabar/Views/Settings Viabar/Models/AppSettings.swift ViabarTests/ViabarTests.swift
git diff --check
```

Expected: the removed strings and `NavigationSplitView` do not appear in the
new settings view; recorder/data/update symbols do appear; `git diff --check`
reports no whitespace errors. This does not prove compilation.

### Task 4: Optional Authorized Runtime Verification

**Files:**
- Verify: `Viabar/Models/AppSettings.swift`
- Verify: `Viabar/Views/Settings/SettingsView.swift`
- Verify: `Viabar/Views/Settings/ShortcutRecorderField.swift`
- Verify: `ViabarTests/ViabarTests.swift`

- [ ] **Step 1: Ask for explicit authorization before any compile**

Because the repository instruction forbids compiling unless requested, obtain
explicit permission before executing any command in this task.

- [ ] **Step 2: Run scoped automated verification if authorized**

Run:

```bash
xcodebuild test -project Viabar.xcodeproj -scheme Viabar -destination 'platform=macOS' -only-testing:ViabarTests/AppSettingsTests
```

Expected: all `AppSettingsTests` pass.

- [ ] **Step 3: Run UI validation if authorized**

Launch the app only if the user specifically requests a visual runtime check.
Inspect:

- the sidebar is an inset rounded panel with no collapse control;
- all five category buttons select their content;
- `数据` is shown as the sidebar label;
- clicking each shortcut field enters recording, valid modified input persists,
  and Escape leaves the old value intact;
- About displays `自动更新` enabled for a newly created default settings row.

- [ ] **Step 4: Commit implementation only after requested verification scope**

Stage only the settings implementation, related settings tests, and any
previously uncommitted base settings files that are deliberately part of this
same feature. Do not stage `.superpowers/brainstorm/` visual scratch data.

```bash
git add -- Viabar/Models/AppSettings.swift Viabar/ViabarApp.swift Viabar/Views/Settings/SettingsView.swift Viabar/Views/Settings/ShortcutRecorderField.swift ViabarTests/ViabarTests.swift
git commit -m "feat: refine settings window and record shortcuts"
```
