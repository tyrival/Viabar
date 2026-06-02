#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROTOTYPE_DIR="$ROOT_DIR/ViabariOS/Prototype"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

for file in \
    IOSPrototypeModels.swift \
    IOSPrototypeStore.swift \
    IOSPrototypeComponents.swift \
    IOSPrototypeOverviewView.swift \
    IOSPrototypeProjectDetailView.swift \
    IOSPrototypeArchiveView.swift; do
    [[ -f "$PROTOTYPE_DIR/$file" ]] || fail "missing ViabariOS/Prototype/$file"
done

if rg -q '@Model|ModelContext|ModelContainer|SwiftData' "$PROTOTYPE_DIR" --glob '*.swift'; then
    fail "iOS static prototype must not depend on SwiftData"
fi

rg -q 'final class IOSPrototypeStore' "$PROTOTYPE_DIR/IOSPrototypeStore.swift" ||
    fail "prototype store is missing"
if rg -q '= Self\.demoProjects\(\)' "$PROTOTYPE_DIR/IOSPrototypeStore.swift"; then
    fail "prototype store initializer must not reference covariant Self"
fi
rg -q '\.contextMenu' "$PROTOTYPE_DIR" --glob '*.swift' ||
    fail "prototype context menus are missing"
rg -q 'star\.fill' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "favorite project cards must show star.fill"
rg -q 'ViabarColor\.warning' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "favorite project star must reuse the macOS warning color"
rg -q 'mappin\.and\.ellipse' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "overview milestone icon must match macOS"
rg -q 'list\.bullet\.indent' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "overview subtask icon must match macOS"
rg -q '#00BBE1' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "progress ring must reuse the macOS cyan color"
rg -q '#00F9D0' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "progress ring must reuse the macOS mint color"
rg -q 'AngularGradient' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "progress ring must reuse the macOS angular gradient"
rg -q 'struct IOSPrototypeDetailComposer' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "detail composer is missing"
if rg -q 'IOSMultilineEditor|onFocusLost|saveTrigger' "$PROTOTYPE_DIR" --glob '*.swift'; then
    fail "prototype must use the bottom composer without inline or focus-loss editing"
fi
rg -q 'paperplane\.fill' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "detail footer must switch to a paper plane while saving"
rg -q 'paperplane\.fill' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "overview project editing must switch to a paper plane"
rg -q '新增子任务' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "milestone menu must support adding a subtask"
rg -q 'func addSubtask' "$PROTOTYPE_DIR/IOSPrototypeStore.swift" ||
    fail "prototype store must support temporary subtask creation"
rg -q 'composerText\.trimmingCharacters' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "blank task edits must be handled explicitly"
rg -q 'editMilestone|editSubtask|editMemo' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "detail bottom composer must retain edit targets"
rg -q 'copyIOSPrototypeText' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "prototype copy helper is missing"
rg -Fq 'Button("复制"' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "task and memo context menus must expose copy actions"
rg -Fq '.contentShape(Rectangle())' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "completed task rows must keep a full-width long-press hit area"
rg -q 'editingProjectID' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "overview project editing must use a bottom composer session"
rg -q 'foregroundStyle\(accentColor\(project\)\)' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "detail toolbar symbol must use the project accent color"
rg -q '\.lineLimit\(1\)' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "overview progress percent must stay on one line"
rg -q 'IOSPrototypeBottomBarMetrics' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "bottom controls must use compact shared metrics"
rg -q 'struct IOSPrototypeArchiveFolder' "$PROTOTYPE_DIR/IOSPrototypeModels.swift" ||
    fail "archive folder prototype model is missing"
rg -q 'milestoneID|subtaskID|memoID' "$PROTOTYPE_DIR/IOSPrototypeModels.swift" ||
    fail "search destinations must retain entity IDs"
rg -q 'for project in projects \{' "$PROTOTYPE_DIR/IOSPrototypeStore.swift" ||
    fail "global search must include active and archived projects"
rg -q '归档 / ' "$PROTOTYPE_DIR/IOSPrototypeStore.swift" ||
    fail "archived search results must expose an archive-prefixed path"
rg -q 'revealArchiveAncestors' "$PROTOTYPE_DIR/IOSPrototypeStore.swift" ||
    fail "archived search navigation must reveal ancestor folders"
rg -q 'LazyVStack' "$PROTOTYPE_DIR/IOSPrototypeArchiveView.swift" ||
    fail "archive tree must use lazy stacks"
rg -q 'IOSPrototypeArchiveFolderNodeView' "$PROTOTYPE_DIR/IOSPrototypeArchiveView.swift" ||
    fail "archive tree must recursively render expanded folders"
rg -q 'folder\.badge\.plus' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "archive root-folder action must share the home footer row"
rg -q 'rootFolderCreationTrigger' "$PROTOTYPE_DIR/IOSPrototypeArchiveView.swift" ||
    fail "archive view must receive root-folder creation from the home footer"
rg -q '新建子文件夹' "$PROTOTYPE_DIR/IOSPrototypeArchiveView.swift" ||
    fail "archive child-folder action is missing"
rg -q '重命名' "$PROTOTYPE_DIR/IOSPrototypeArchiveView.swift" ||
    fail "archive folder rename action is missing"
rg -q 'confirmationDialog|alert' "$PROTOTYPE_DIR/IOSPrototypeArchiveView.swift" ||
    fail "archive folder deletion confirmation is missing"
rg -q 'size: 20, lineWidth: 4' "$PROTOTYPE_DIR/IOSPrototypeArchiveView.swift" ||
    fail "archived project rows must use a smaller progress ring"
rg -q '\.contentShape\(Capsule\(\)\)' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "bottom tabs must expose their full capsule hit areas"
rg -q 'struct IOSPrototypeCircularIconButton' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "overview top actions must share the circular icon style"
rg -q '\.shadow\(color: \.black\.opacity\(0\.12\)' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "global search result panel must expose a visible shadow"
rg -q 'Divider\(\)' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "global search results must expose separators"
rg -q '\.frame\(maxHeight: 280\)' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "global search result panel must retain a scrolling height cap"
rg -q 'project\.symbol' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "global search results must reuse each project symbol"
rg -q 'Color\(prototypeHex: project\.accentHex\)' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "global search result symbols must reuse each project color"
rg -q '\.background\(\.white\.opacity\(0\.94\), in: RoundedRectangle\(cornerRadius: 14\)\)' "$PROTOTYPE_DIR/IOSPrototypeArchiveView.swift" ||
    fail "archive tree must use a compact grouped-list container"
rg -q 'projectPendingDeletion' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "overview project deletion confirmation is missing"
if rg -q 'store\.deleteProject\(project\.id\)' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift"; then
    fail "detail toolbar must not delete projects"
fi
rg -q 'project\.isFavorite' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "detail toolbar favorite star is missing"
rg -q 'currentProject\.isFavorite' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "overview favorite star must read the current store value"
rg -q 'consumedNavigationHighlightRequestIDs' "$PROTOTYPE_DIR/IOSPrototypeStore.swift" ||
    fail "search navigation highlights must retain consumed request IDs"
rg -q 'consumeNavigationHighlight' "$PROTOTYPE_DIR/IOSPrototypeStore.swift" ||
    fail "search navigation highlights must be consumed once"
rg -q 'IOSPrototypeReminderStyle\.color' "$PROTOTYPE_DIR/IOSPrototypeOverviewView.swift" ||
    fail "overview reminders must use the shared date color policy"
rg -q 'IOSPrototypeReminderStyle\.color' "$PROTOTYPE_DIR/IOSPrototypeProjectDetailView.swift" ||
    fail "detail reminders must use the shared date color policy"
rg -q 'if date < now' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "reminder style must render overdue reminders in red"
rg -q 'calendar\.isDateInToday\(date\)' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "reminder style must distinguish pending reminders today"
rg -q 'item\(\.overview, symbol: \"square\.grid\.2x2\"' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "overview tab must use the grid symbol"
rg -q 'item\(\.reports, symbol: \"checkmark\.seal\.fill\"' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "reports tab must use a text-summary symbol"
rg -q 'item\(\.tasks, symbol: \"checkmark\.circle\.fill\"' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "tasks tab must use the checklist symbol"
rg -q 'item\(\.memos, symbol: \"scribble\.variable\"' "$PROTOTYPE_DIR/IOSPrototypeComponents.swift" ||
    fail "memos tab must use the note symbol"
if rg -q 'Button\(\"完成\"' "$PROTOTYPE_DIR" --glob '*.swift'; then
    fail "prototype editors must not expose an extra done button"
fi
rg -q 'IOSPersistentRootView' "$ROOT_DIR/ViabariOS/ContentView.swift" ||
    fail "ContentView must present the persistent root after prototype validation"

printf 'PASS: iOS static prototype checks\n'
