#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ViabariOS"
SHARED_CONTAINER="$ROOT_DIR/Viabar/System/SharedModelContainer.swift"
IOS_APP="$IOS_DIR/ViabariOSApp.swift"
IOS_CONTENT="$IOS_DIR/ContentView.swift"
PROJECT_FILE="$ROOT_DIR/Viabar.xcodeproj/project.pbxproj"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

for file in \
    Persistence/IOSPersistenceCoordinator.swift \
    Persistence/IOSPersistentRootView.swift \
    Persistence/IOSPersistentOverviewView.swift \
    Persistence/IOSPersistentProjectDetailView.swift \
    Persistence/IOSPersistentArchiveView.swift \
    Persistence/IOSPersistentArchiveFolderPicker.swift \
    Persistence/IOSPersistentReminderEditor.swift; do
    [[ -f "$IOS_DIR/$file" ]] || fail "missing ViabariOS/$file"
done

rg -q 'static let appGroupIdentifier = "group\.com\.tyrival\.Viabar"' "$SHARED_CONTAINER" ||
    fail "shared App Group identifier must be unified"
rg -q 'SharedModelContainer\.makeTrashContainer\(\)' "$IOS_APP" ||
    fail "iOS app must open trash.store"
rg -q 'registerProjectService' "$IOS_APP" ||
    fail "iOS app must register ProjectService"
rg -q 'registerNotificationScheduleService' "$IOS_APP" ||
    fail "iOS app must register NotificationScheduleService"
rg -q 'registerTrashService' "$IOS_APP" ||
    fail "iOS app must register TrashService"
rg -q 'cleanupExpired\(policy: TrashRetentionSettingsStore\.policy\(\)\)' "$IOS_APP" ||
    fail "iOS app must clean expired trash items at launch"
rg -q '\.environment\(serviceContainer\)' "$IOS_APP" ||
    fail "iOS app must inject ServiceContainer"
rg -q 'IOSPersistentRootView' "$IOS_CONTENT" ||
    fail "ContentView must present the persistent root"
rg -q '@Query\(sort: \\Project\.orderIndex\)' "$IOS_DIR/Persistence/IOSPersistentRootView.swift" ||
    fail "persistent root must query real projects"
rg -q 'GlobalSearchIndex\.results' "$IOS_DIR/Persistence/IOSPersistentOverviewView.swift" ||
    fail "iOS search must reuse GlobalSearchIndex"
rg -q 'moveProjectToFolder' "$IOS_DIR/Persistence/IOSPersistentArchiveView.swift" ||
    fail "archive view must support moving archived projects"
rg -q 'contentShape\(Rectangle\(\)\)' "$IOS_DIR/Persistence/IOSPersistentOverviewView.swift" ||
    fail "search result rows must define a full-row hit target"
rg -q 'editingProject: Project\?' "$IOS_DIR/Persistence/IOSPersistentProjectCreationView.swift" ||
    fail "project form must support create and edit modes"
rg -q 'updateReminder\(.*for: milestone\)' "$IOS_DIR/Persistence/IOSPersistentProjectDetailView.swift" ||
    fail "milestone reminder editing must reuse ProjectService"
rg -q 'updateReminder\(.*for: subtask\)' "$IOS_DIR/Persistence/IOSPersistentProjectDetailView.swift" ||
    fail "subtask reminder editing must reuse ProjectService"
rg -q 'displaySummary\(' "$IOS_DIR/Persistence/IOSPersistentProjectDetailView.swift" &&
    rg -q 'dateFormatPattern: savedDateFormat' "$IOS_DIR/Persistence/IOSPersistentProjectDetailView.swift" ||
    fail "project detail reminder summaries must honor the saved date format"
rg -q 'expandedFolderIDs' "$IOS_DIR/Persistence/IOSPersistentArchiveFolderPicker.swift" ||
    fail "archive picker must own its collapsed-by-default expansion state"
rg -q 'SharedModelContainer\.makeWidgetContainer' "$ROOT_DIR/ViabarWidget" --glob '*.swift' ||
    fail "Widget must continue to open the shared main store"

if rg -q '@Model|Schema\(' "$IOS_DIR/Persistence" --glob '*.swift'; then
    fail "iOS persistence UI must not define a parallel schema"
fi

for source in \
    Viabar/Models/TrashItem.swift \
    Viabar/Models/BackupSnapshot.swift \
    Viabar/Models/GlobalSearch.swift \
    Viabar/System/TrashModelContainer.swift \
    Viabar/Services/SyncService.swift \
    Viabar/Services/NotificationScheduleService.swift \
    Viabar/Services/TrashService.swift \
    Viabar/Services/ProjectService.swift; do
    rg -q "$source in Sources" "$PROJECT_FILE" ||
        fail "iOS app target must include $source"
done

printf 'PASS: iOS persistence static checks\n'
