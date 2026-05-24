# Settings Native Sidebar And Shortcut Recorder Design

## Goal

Refine the existing Settings window into a macOS 26 / Xcode-inspired
preferences surface and make shortcut values editable through keyboard
recording instead of free-form text entry. This design extends the existing
settings persistence and date-format design; it does not alter reminder
scheduling or the already documented timestamp behavior.

## Confirmed Visual Direction

The Settings window uses a single unified window background with an inset,
rounded sidebar panel on the left:

- the sidebar is a rounded rectangle placed inside the window with visible
  padding around its outer edges;
- the native window traffic-light buttons appear at the upper-left area of
  this inset sidebar presentation;
- the sidebar is always visible and cannot be collapsed by a button, menu
  command, or layout interaction;
- the sidebar remains the navigation surface for `通用`, `显示`, `快捷键`,
  `数据`, and `关于`;
- the selected sidebar item uses a rounded native-style selection surface;
- the detail pane has no forward/back buttons and no sidebar toggle button;
- the detail header contains only the selected category title before its
  grouped configuration rows.

The typography and spacing are compact rather than oversized:

- sidebar labels are visually equivalent to approximately 14 point system
  text with compact row height;
- detail titles are visually equivalent to approximately 20 point semibold
  system text;
- settings rows use approximately 13 point primary text and 11 point
  supporting text where descriptions are useful;
- row heights, section gaps, controls, and corner radii are reduced together
  so the screen has native settings density rather than a scaled-down copy of
  a loose layout.

The implementation should prefer macOS semantic materials, colors, and native
controls. Custom layout is justified for the inset fixed sidebar shape, but it
must not create a bespoke visual theme that fights the platform appearance.

## Categories And Copy Changes

The existing sidebar-detail category model remains in place with one rename:

- rename `数据同步与备份` to `数据`;
- leave its contained sections as `数据同步` and `数据备份`, since those labels
  describe the individual groups within the broader category.

The selected category remains window-local state and defaults to `通用`.

## Shortcut Recording Interaction

The `快捷键` category replaces editable text fields with shortcut recorder
controls for the existing items:

- `显示 / 隐藏主面板`, backed by `toggleMainPanelShortcut`;
- `打开搜索框`, backed by `openSearchShortcut`.

Each row shows its currently stored shortcut as a button-like key field. The
field behavior is:

1. Clicking a key field starts recording for that one setting and visually
   highlights the field with text such as `请按键...`.
2. The next valid keyboard combination containing at least one modifier key
   and one non-modifier key is converted into a display string and saved to
   the corresponding persisted setting.
3. Supported modifiers are Command, Option, Control, and Shift; combinations
   are displayed using macOS symbols in the stable order `⌃`, `⌥`, `⇧`, `⌘`,
   followed by the primary key.
4. Pressing `Esc` while recording cancels recording and retains the prior
   stored shortcut.
5. Pressing only modifier keys does not save a shortcut and leaves the
   recorder waiting for a primary key.
6. Clicking another shortcut row moves recording focus to that row without
   altering the prior row.

This change records and persists shortcut choices in Settings only. It does
not register new global keyboard shortcuts or change which app actions
actually respond to shortcuts.

## Settings Persistence

Extend the existing singleton `AppSettings` model with:

- `automaticallyChecksForUpdates: Bool = true`

The two existing shortcut string properties continue to hold saved recorder
values. Existing default shortcut values remain:

- `toggleMainPanelShortcut = "Option+V"`
- `openSearchShortcut = "Command+F"`

The canonical persisted format follows those current values: modifier names
are joined with `+` in the order `Control`, `Option`, `Shift`, `Command`, then
the primary key, for example `Control+Option+K` or `Command+Shift+F`.
Letter keys are saved uppercase; digit keys retain the digit. Standard
non-character keys that may be used as a shortcut primary key are saved with
stable names such as `Space`, `Return`, `Tab`, `Delete`, `Up`, `Down`, `Left`,
and `Right`. `Escape` remains the recorder cancel action and is not saved as a
shortcut during this change.

The recorder must display canonical strings using symbols and render existing
default strings correctly on reopening Settings. Since shortcut execution
remains out of scope, no migration beyond interpreting the current default
strings is required in this change.

## About Panel

The `关于` panel adds one settings row immediately below the version row:

- label: `自动更新`;
- control: native macOS toggle;
- persisted binding: `automaticallyChecksForUpdates`;
- default state: enabled.

This setting records the user's preference only. It does not implement an
update checker, schedule network activity, or download/install updates.

## View And Code Boundaries

- `Viabar/Views/Settings/SettingsView.swift` owns the inset fixed-sidebar
  layout, compact grouped detail panels, renamed Data navigation label, About
  toggle row, and shortcut recorder presentation.
- A focused recorder helper in the settings view area bridges key-down events
  needed for keyboard capture; low-level responder handling should be limited
  to this control rather than spread through the settings screen.
- `Viabar/Models/AppSettings.swift` owns the new persisted update-preference
  field and remains the source of defaults.
- `ViabarTests/ViabarTests.swift` covers the new default and any isolated
  shortcut formatting/parsing logic extracted into testable helpers.

## Error Handling And Accessibility

- If the saved shortcut text cannot be interpreted for symbolic display, show
  the saved string unchanged rather than discarding it.
- The shortcut recorder must expose an understandable accessibility label and
  indicate when it is recording.
- Cancelling a recording or receiving an invalid key event must not mutate
  saved settings.
- If version metadata is unavailable, the existing `--` fallback remains.

## Verification

Use test-first implementation for isolated model and shortcut-formatting
behavior:

- `AppSettings()` defaults automatic updates to enabled;
- known saved default strings render as `⌥ V` and `⌘ F`;
- valid recorded combinations produce stable stored/displayed values;
- cancel or modifier-only input does not produce a persisted replacement where
  this logic can be isolated from view event routing.

Do not compile or run build/test commands unless explicitly requested, in
accordance with the repository instruction. Use source inspection and
`git diff --check` as non-compiling validation for the implementation unless
the user later requests a build or test run.
