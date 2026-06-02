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
    Persistence/IOSPersistentArchiveView.swift; do
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
rg -q '\.environment\(serviceContainer\)' "$IOS_APP" ||
    fail "iOS app must inject ServiceContainer"
rg -q 'IOSPersistentRootView' "$IOS_CONTENT" ||
    fail "ContentView must present the persistent root"
rg -q '@Query\(sort: \\Project\.orderIndex\)' "$IOS_DIR/Persistence/IOSPersistentRootView.swift" ||
    fail "persistent root must query real projects"
rg -q 'GlobalSearchIndex\.results' "$IOS_DIR/Persistence/IOSPersistentOverviewView.swift" ||
    fail "iOS search must reuse GlobalSearchIndex"
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
