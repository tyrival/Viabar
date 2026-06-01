# Frozen Local Medium And Large Widget Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Medium desktop Widget that reuses the Large Widget behavior, and package a frozen-local DMG with explicit ad hoc limitations, artifact validation, and a safe Widget cache reset path.

**Architecture:** Keep one Widget Extension and expose two stable Widget kinds from the existing bundle. Parameterize the shared provider and shared view by row budget so Medium and Large differ only in task density. Add separate local-only packaging and cache-reset scripts without changing the existing Sparkle publishing workflow.

**Tech Stack:** SwiftUI, WidgetKit, App Intents, SwiftData, Bash, `codesign`, `hdiutil`, `pluginkit`, LaunchServices.

**Repository Constraint:** Do not run `xcodebuild`, Swift tests, archive workflows, DMG creation, app launch, or Widget installation workflows until the user explicitly authorizes compilation and packaging. Before that authorization, use source inspection, shell static tests, `bash -n`, `git diff --check`, and `plutil -lint`.

---

## File Structure

- Modify `Viabar/System/SharedModelContainer.swift`: define stable Medium and Large Widget kinds.
- Modify `Viabar/Models/WidgetContent.swift`: add the Medium row-budget constant.
- Modify `ViabarTests/ViabarTests.swift`: document Medium density with a focused unit test.
- Modify `ViabarWidget/ViabarLargeWidget.swift`: parameterize the provider and shared view, retain Large, and add Medium.
- Modify `ViabarWidget/ViabarWidgetBundle.swift`: expose Medium and Large configurations from one extension.
- Modify `ViabarWidget/en.lproj/Localizable.strings`: add distinct English gallery names for Medium and Large.
- Modify `ViabarWidget/zh-Hans.lproj/Localizable.strings`: add distinct Simplified Chinese gallery names for Medium and Large.
- Modify `Viabar/Services/ProjectService.swift`: refresh both Widget kinds after app-side saves.
- Modify `ViabarWidget/RefreshWidgetIntent.swift`: refresh both Widget kinds from the Widget refresh button.
- Modify `ViabarWidget/ToggleWidgetTaskIntent.swift`: refresh both Widget kinds after task completion.
- Create `scripts/reset_local_widget_cache.sh`: unregister known Viabar Widget extensions and remove only Chrono cache.
- Create `scripts/package_frozen_local.sh`: build and validate the frozen-local ad hoc DMG.
- Create `scripts/tests/test_widget_static.sh`: protect Medium/Large Widget structure and shared refresh wiring.
- Create `scripts/tests/test_reset_local_widget_cache.sh`: prove cache reset never touches the App Group database.
- Create `scripts/tests/test_frozen_local_package.sh`: protect frozen-local packaging invariants without archiving.
- Modify `docs/releasing.md`: document frozen-local packaging, installation, reset, and trust limitations.

### Task 1: Add Static Widget Structure Guardrails

**Files:**
- Create: `scripts/tests/test_widget_static.sh`

- [ ] **Step 1: Write the failing static test**

Create `scripts/tests/test_widget_static.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARED_CONTAINER="$ROOT_DIR/Viabar/System/SharedModelContainer.swift"
WIDGET_CONTENT="$ROOT_DIR/Viabar/Models/WidgetContent.swift"
WIDGET_VIEW="$ROOT_DIR/ViabarWidget/ViabarLargeWidget.swift"
WIDGET_BUNDLE="$ROOT_DIR/ViabarWidget/ViabarWidgetBundle.swift"
EN_STRINGS="$ROOT_DIR/ViabarWidget/en.lproj/Localizable.strings"
ZH_STRINGS="$ROOT_DIR/ViabarWidget/zh-Hans.lproj/Localizable.strings"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

rg -q 'static let mediumWidgetKind = "ViabarMediumWidget"' "$SHARED_CONTAINER" ||
    fail "SharedModelContainer must define the stable Medium Widget kind"
rg -q 'static let largeWidgetKind = "ViabarLargeWidget"' "$SHARED_CONTAINER" ||
    fail "SharedModelContainer must define the stable Large Widget kind"
rg -q 'static let widgetKinds = \\[mediumWidgetKind, largeWidgetKind\\]' "$SHARED_CONTAINER" ||
    fail "SharedModelContainer must enumerate both Widget kinds"
rg -q 'static let mediumWidgetRowBudget = 4' "$WIDGET_CONTENT" ||
    fail "Medium Widget row budget must stay at 4"
rg -q 'static let largeWidgetRowBudget = 10' "$WIDGET_CONTENT" ||
    fail "Large Widget row budget must stay at 10"
rg -q 'struct ViabarMediumWidget: Widget' "$WIDGET_VIEW" ||
    fail "Widget extension must define ViabarMediumWidget"
rg -q '\\.supportedFamilies\\(\\[\\.systemMedium\\]\\)' "$WIDGET_VIEW" ||
    fail "Medium Widget must only support systemMedium"
rg -q '\\.supportedFamilies\\(\\[\\.systemLarge\\]\\)' "$WIDGET_VIEW" ||
    fail "Large Widget must only support systemLarge"
rg -q 'ViabarMediumWidget\\(\\)' "$WIDGET_BUNDLE" ||
    fail "Widget bundle must expose Medium"
rg -q 'ViabarLargeWidget\\(\\)' "$WIDGET_BUNDLE" ||
    fail "Widget bundle must expose Large"
rg -q '"Viabar 中号项目" = "Viabar Medium Project";' "$EN_STRINGS" ||
    fail "English localization must distinguish the Medium Widget"
rg -q '"Viabar 大号项目" = "Viabar Large Project";' "$EN_STRINGS" ||
    fail "English localization must distinguish the Large Widget"
rg -q '"Viabar 中号项目" = "Viabar 中号项目";' "$ZH_STRINGS" ||
    fail "Chinese localization must distinguish the Medium Widget"
rg -q '"Viabar 大号项目" = "Viabar 大号项目";' "$ZH_STRINGS" ||
    fail "Chinese localization must distinguish the Large Widget"

printf 'PASS: Widget static checks\n'
```

- [ ] **Step 2: Run the static test to verify it fails**

Run:

```bash
bash scripts/tests/test_widget_static.sh
```

Expected: FAIL with `SharedModelContainer must define the stable Medium Widget kind`.

### Task 2: Parameterize Shared Widget Projection And Add Medium

**Files:**
- Modify: `Viabar/System/SharedModelContainer.swift`
- Modify: `Viabar/Models/WidgetContent.swift`
- Modify: `ViabarTests/ViabarTests.swift`
- Modify: `ViabarWidget/ViabarLargeWidget.swift`
- Modify: `ViabarWidget/ViabarWidgetBundle.swift`
- Modify: `ViabarWidget/en.lproj/Localizable.strings`
- Modify: `ViabarWidget/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add the focused Medium budget unit test**

Append this test inside `WidgetContentTests` in `ViabarTests/ViabarTests.swift`:

```swift
    @Test func mediumWidgetAllowsFourPlainTaskRows() {
        let project = Project(title: "Release")
        project.milestones = (0..<6).map { Milestone(title: "Task \($0)", orderIndex: $0) }

        let content = WidgetContentBuilder.content(
            for: project,
            rowBudget: WidgetContentBuilder.mediumWidgetRowBudget,
            now: Date(),
            calendar: calendar
        )

        #expect(content.visibleItems.count == 4)
        #expect(content.hiddenItemCount == 2)
    }
```

- [ ] **Step 2: Record the deferred Swift test command**

Do not run this command until the user authorizes compilation:

```bash
xcodebuild test \
  -project Viabar.xcodeproj \
  -scheme Viabar \
  -destination 'platform=macOS' \
  -only-testing:ViabarTests
```

Expected after authorization and implementation: PASS.

- [ ] **Step 3: Add stable Widget kind constants**

Replace the single `widgetKind` constant in `Viabar/System/SharedModelContainer.swift` with:

```swift
    static let mediumWidgetKind = "ViabarMediumWidget"
    static let largeWidgetKind = "ViabarLargeWidget"
    static let widgetKinds = [mediumWidgetKind, largeWidgetKind]
```

- [ ] **Step 4: Add the Medium row budget**

In `Viabar/Models/WidgetContent.swift`, keep the Large budget and add:

```swift
    static let mediumWidgetRowBudget = 4
    static let largeWidgetRowBudget = 10
```

- [ ] **Step 5: Parameterize the shared provider**

In `ViabarWidget/ViabarLargeWidget.swift`, give `ViabarWidgetProvider` an immutable budget:

```swift
struct ViabarWidgetProvider: AppIntentTimelineProvider {
    let rowBudget: Int

    init(rowBudget: Int) {
        self.rowBudget = rowBudget
    }
```

Inside `entry(for:)`, replace the hard-coded Large budget with:

```swift
                        rowBudget: rowBudget,
```

- [ ] **Step 6: Reuse one view for both sizes**

Rename `ViabarLargeWidgetView` to `ViabarWidgetView`, then define both Widget configurations in `ViabarWidget/ViabarLargeWidget.swift`:

```swift
struct ViabarMediumWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SharedModelContainer.mediumWidgetKind,
            intent: SelectWidgetProjectIntent.self,
            provider: ViabarWidgetProvider(
                rowBudget: WidgetContentBuilder.mediumWidgetRowBudget
            )
        ) { entry in
            ViabarWidgetView(entry: entry)
        }
        .configurationDisplayName("Viabar 中号项目")
        .description("在桌面查看并完成项目任务")
        .supportedFamilies([.systemMedium])
    }
}

struct ViabarLargeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SharedModelContainer.largeWidgetKind,
            intent: SelectWidgetProjectIntent.self,
            provider: ViabarWidgetProvider(
                rowBudget: WidgetContentBuilder.largeWidgetRowBudget
            )
        ) { entry in
            ViabarWidgetView(entry: entry)
        }
        .configurationDisplayName("Viabar 大号项目")
        .description("在桌面查看并完成项目任务")
        .supportedFamilies([.systemLarge])
    }
}

struct ViabarWidgetView: View {
```

Keep the existing shared view body, header, task rows, reminder colors, and deep-link helpers unchanged after the rename.

- [ ] **Step 7: Expose both configurations from one extension**

Update `ViabarWidget/ViabarWidgetBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct ViabarWidgetBundle: WidgetBundle {
    var body: some Widget {
        ViabarMediumWidget()
        ViabarLargeWidget()
    }
}
```

- [ ] **Step 8: Add bilingual gallery names**

Append to `ViabarWidget/en.lproj/Localizable.strings`:

```text
"Viabar 中号项目" = "Viabar Medium Project";
"Viabar 大号项目" = "Viabar Large Project";
```

Append to `ViabarWidget/zh-Hans.lproj/Localizable.strings`:

```text
"Viabar 中号项目" = "Viabar 中号项目";
"Viabar 大号项目" = "Viabar 大号项目";
```

- [ ] **Step 9: Run the static test and source hygiene**

Run:

```bash
bash scripts/tests/test_widget_static.sh
git diff --check
```

Expected:

```text
PASS: Widget static checks
```

`git diff --check` exits 0.

- [ ] **Step 10: Commit the Medium Widget**

```bash
git add -- \
  scripts/tests/test_widget_static.sh \
  Viabar/System/SharedModelContainer.swift \
  Viabar/Models/WidgetContent.swift \
  ViabarTests/ViabarTests.swift \
  ViabarWidget/ViabarLargeWidget.swift \
  ViabarWidget/ViabarWidgetBundle.swift \
  ViabarWidget/en.lproj/Localizable.strings \
  ViabarWidget/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add medium desktop widget"
```

### Task 3: Refresh Medium And Large Together

**Files:**
- Modify: `scripts/tests/test_widget_static.sh`
- Modify: `Viabar/Services/ProjectService.swift`
- Modify: `ViabarWidget/RefreshWidgetIntent.swift`
- Modify: `ViabarWidget/ToggleWidgetTaskIntent.swift`

- [ ] **Step 1: Add failing static checks for shared refresh wiring**

Before the final PASS line in `scripts/tests/test_widget_static.sh`, add:

```bash
PROJECT_SERVICE="$ROOT_DIR/Viabar/Services/ProjectService.swift"
REFRESH_INTENT="$ROOT_DIR/ViabarWidget/RefreshWidgetIntent.swift"
TOGGLE_INTENT="$ROOT_DIR/ViabarWidget/ToggleWidgetTaskIntent.swift"

for source in "$PROJECT_SERVICE" "$REFRESH_INTENT" "$TOGGLE_INTENT"; do
    rg -q 'SharedModelContainer\\.widgetKinds\\.forEach' "$source" ||
        fail "$source must refresh both Widget kinds"
done
```

- [ ] **Step 2: Run the static test to verify it fails**

Run:

```bash
bash scripts/tests/test_widget_static.sh
```

Expected: FAIL because `ProjectService.swift` still refreshes only the old Large kind.

- [ ] **Step 3: Replace app-side single-kind refresh**

In `Viabar/Services/ProjectService.swift`, replace:

```swift
            WidgetCenter.shared.reloadTimelines(ofKind: SharedModelContainer.widgetKind)
```

with:

```swift
            SharedModelContainer.widgetKinds.forEach {
                WidgetCenter.shared.reloadTimelines(ofKind: $0)
            }
```

- [ ] **Step 4: Replace Widget refresh-button single-kind refresh**

In `ViabarWidget/RefreshWidgetIntent.swift`, replace:

```swift
        WidgetCenter.shared.reloadTimelines(ofKind: SharedModelContainer.widgetKind)
```

with:

```swift
        SharedModelContainer.widgetKinds.forEach {
            WidgetCenter.shared.reloadTimelines(ofKind: $0)
        }
```

- [ ] **Step 5: Replace completion-intent single-kind refresh**

In `ViabarWidget/ToggleWidgetTaskIntent.swift`, replace:

```swift
        WidgetCenter.shared.reloadTimelines(ofKind: SharedModelContainer.widgetKind)
```

with:

```swift
        SharedModelContainer.widgetKinds.forEach {
            WidgetCenter.shared.reloadTimelines(ofKind: $0)
        }
```

- [ ] **Step 6: Run the Widget static checks**

Run:

```bash
bash scripts/tests/test_widget_static.sh
git diff --check
```

Expected:

```text
PASS: Widget static checks
```

- [ ] **Step 7: Commit shared refresh wiring**

```bash
git add -- \
  scripts/tests/test_widget_static.sh \
  Viabar/Services/ProjectService.swift \
  ViabarWidget/RefreshWidgetIntent.swift \
  ViabarWidget/ToggleWidgetTaskIntent.swift
git commit -m "fix: refresh both desktop widget sizes"
```

### Task 4: Add Safe Widget Cache Reset

**Files:**
- Create: `scripts/reset_local_widget_cache.sh`
- Create: `scripts/tests/test_reset_local_widget_cache.sh`

- [ ] **Step 1: Write the failing cache-reset test**

Create `scripts/tests/test_reset_local_widget_cache.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESET_SCRIPT="$ROOT_DIR/scripts/reset_local_widget_cache.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

FAKE_HOME="$TEMP_DIR/home"
CHRONO_DIR="$FAKE_HOME/Library/Containers/com.tyrival.Viabar.Widget/Data/SystemData/com.apple.chrono"
SHARED_DIR="$FAKE_HOME/Library/Group Containers/group.com.tyrival.Viabar/ViabarSharedStore"
INSTALLED_APP="$TEMP_DIR/Applications/Viabar.app"
FAKE_BIN="$TEMP_DIR/bin"
LOG_FILE="$TEMP_DIR/commands.log"

mkdir -p \
    "$CHRONO_DIR/timelines/ViabarMediumWidget" \
    "$SHARED_DIR" \
    "$INSTALLED_APP/Contents/PlugIns/ViabarWidgetExtension.appex" \
    "$FAKE_BIN"
printf 'widget-cache\n' > "$CHRONO_DIR/timelines/ViabarMediumWidget/cache"
printf 'business-data\n' > "$SHARED_DIR/default.store"

cat > "$FAKE_BIN/pluginkit" <<'EOF'
#!/usr/bin/env bash
printf 'pluginkit %s\n' "$*" >> "$VIABAR_RESET_TEST_LOG"
EOF
cat > "$FAKE_BIN/lsregister" <<'EOF'
#!/usr/bin/env bash
printf 'lsregister %s\n' "$*" >> "$VIABAR_RESET_TEST_LOG"
EOF
cat > "$FAKE_BIN/pkill" <<'EOF'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >> "$VIABAR_RESET_TEST_LOG"
EOF
chmod +x "$FAKE_BIN/pluginkit" "$FAKE_BIN/lsregister" "$FAKE_BIN/pkill"

HOME="$FAKE_HOME" \
PATH="$FAKE_BIN:/usr/bin:/bin" \
LSREGISTER="$FAKE_BIN/lsregister" \
VIABAR_INSTALLED_APP="$INSTALLED_APP" \
VIABAR_RESET_TEST_LOG="$LOG_FILE" \
"$RESET_SCRIPT"

[[ ! -e "$CHRONO_DIR" ]] || {
    printf 'FAIL: Chrono cache still exists\n' >&2
    exit 1
}
[[ -f "$SHARED_DIR/default.store" ]] || {
    printf 'FAIL: shared business database was removed\n' >&2
    exit 1
}
rg -q 'pluginkit -r' "$LOG_FILE" || {
    printf 'FAIL: Widget unregister command was not attempted\n' >&2
    exit 1
}

printf 'PASS: Widget cache reset checks\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash scripts/tests/test_reset_local_widget_cache.sh
```

Expected: FAIL because `scripts/reset_local_widget_cache.sh` does not exist.

- [ ] **Step 3: Add the cache-reset script**

Create `scripts/reset_local_widget_cache.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

LSREGISTER="${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
WIDGET_IDENTIFIER="com.tyrival.Viabar.Widget"
INSTALLED_APP="${VIABAR_INSTALLED_APP:-/Applications/Viabar.app}"
DEBUG_APP_GLOB="$HOME/Library/Developer/Xcode/DerivedData"/Viabar-*/Build/Products/Debug/Viabar.app
CHRONO_DIR="$HOME/Library/Containers/com.tyrival.Viabar.Widget/Data/SystemData/com.apple.chrono"
SHARED_DIR="$HOME/Library/Group Containers/group.com.tyrival.Viabar"

unregister_app() {
    local app="$1"
    local widget="$app/Contents/PlugIns/ViabarWidgetExtension.appex"
    [[ -d "$widget" ]] && pluginkit -r "$widget" >/dev/null 2>&1 || true
    [[ -d "$app" ]] && "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
}

printf 'Resetting Viabar Widget cache only.\n'
printf 'Preserving business data: %s\n' "$SHARED_DIR"
printf 'Removing Widget cache: %s\n' "$CHRONO_DIR"

unregister_app "$INSTALLED_APP"
for debug_app in $DEBUG_APP_GLOB; do
    [[ -d "$debug_app" ]] && unregister_app "$debug_app"
done

pkill -f 'ViabarWidgetExtension' >/dev/null 2>&1 || true
rm -rf "$CHRONO_DIR"

printf 'Viabar Widget cache reset complete.\n'
printf 'Launch Viabar once, then reopen the macOS Widget gallery.\n'
```

- [ ] **Step 4: Run reset-script checks**

Run:

```bash
chmod +x scripts/reset_local_widget_cache.sh scripts/tests/test_reset_local_widget_cache.sh
bash -n scripts/reset_local_widget_cache.sh scripts/tests/test_reset_local_widget_cache.sh
bash scripts/tests/test_reset_local_widget_cache.sh
```

Expected:

```text
PASS: Widget cache reset checks
```

- [ ] **Step 5: Commit safe reset support**

```bash
git add -- scripts/reset_local_widget_cache.sh scripts/tests/test_reset_local_widget_cache.sh
git commit -m "feat: add safe local widget cache reset"
```

### Task 5: Add Frozen-Local DMG Packaging

**Files:**
- Create: `scripts/package_frozen_local.sh`
- Create: `scripts/tests/test_frozen_local_package.sh`

- [ ] **Step 1: Write the failing packaging invariant test**

Create `scripts/tests/test_frozen_local_package.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_frozen_local.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -f "$PACKAGE_SCRIPT" ]] || fail "frozen-local package script is missing"
rg -q 'CODE_SIGN_IDENTITY="-"' "$PACKAGE_SCRIPT" ||
    fail "frozen-local package must explicitly use ad hoc signing"
rg -q 'group\\.com\\.tyrival\\.Viabar' "$PACKAGE_SCRIPT" ||
    fail "frozen-local package must verify the App Group entitlement"
rg -q 'codesign --verify --deep --strict' "$PACKAGE_SCRIPT" ||
    fail "frozen-local package must verify nested signatures"
rg -q 'ViabarMediumWidget' "$PACKAGE_SCRIPT" ||
    fail "frozen-local package must verify the Medium Widget kind"
rg -q 'ViabarLargeWidget' "$PACKAGE_SCRIPT" ||
    fail "frozen-local package must verify the Large Widget kind"
rg -q 'hdiutil verify' "$PACKAGE_SCRIPT" ||
    fail "frozen-local package must verify the DMG"
rg -q 'hdiutil attach -readonly -nobrowse' "$PACKAGE_SCRIPT" ||
    fail "frozen-local package must mount the DMG read-only"
rg -q 'Applications' "$PACKAGE_SCRIPT" ||
    fail "frozen-local package must include the Applications shortcut"

printf 'PASS: frozen-local package static checks\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash scripts/tests/test_frozen_local_package.sh
```

Expected: FAIL with `frozen-local package script is missing`.

- [ ] **Step 3: Add the local-only package script**

Create `scripts/package_frozen_local.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

log_step() {
    printf '\n==> %s\n' "$1"
}

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "version must use X.Y.Z format, for example: ./scripts/package_frozen_local.sh 1.0.0"
fi

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/Viabar-frozen-local-build.XXXXXX")"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/Viabar-frozen-local-mount.XXXXXX")"
ARCHIVE_PATH="$BUILD_DIR/Viabar.xcarchive"
DMG_STAGE_DIR="$BUILD_DIR/DMGStage"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/Viabar-$VERSION-frozen-local.dmg"
APP_PATH="$DMG_STAGE_DIR/Viabar.app"
WIDGET_PATH="$APP_PATH/Contents/PlugIns/ViabarWidgetExtension.appex"
WIDGET_EXECUTABLE="$WIDGET_PATH/Contents/MacOS/ViabarWidgetExtension"

cleanup() {
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    rm -rf "$BUILD_DIR" "$MOUNT_DIR"
}
trap cleanup EXIT

assert_app_group() {
    local bundle="$1"
    codesign -d --entitlements - "$bundle" 2>/dev/null |
        rg -q 'group\\.com\\.tyrival\\.Viabar' ||
        fail "missing App Group entitlement: $bundle"
}

mkdir -p "$DIST_DIR" "$DMG_STAGE_DIR"
rm -f "$DMG_PATH"

log_step "Archiving frozen-local Viabar $VERSION"
xcodebuild archive \
    -project "$ROOT_DIR/Viabar.xcodeproj" \
    -scheme Viabar \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY="-" \
    COMPILER_INDEX_STORE_ENABLE=NO

cp -R "$ARCHIVE_PATH/Products/Applications/Viabar.app" "$APP_PATH"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

log_step "Validating embedded Widget Extension"
[[ "$(find "$APP_PATH/Contents/PlugIns" -maxdepth 1 -name '*.appex' | wc -l | tr -d ' ')" == "1" ]] ||
    fail "Viabar.app must embed exactly one Widget Extension"
[[ -x "$WIDGET_EXECUTABLE" ]] || fail "Widget executable was not found"
assert_app_group "$APP_PATH"
assert_app_group "$WIDGET_PATH"
strings "$WIDGET_EXECUTABLE" | rg -q 'ViabarMediumWidget' ||
    fail "Widget executable does not expose ViabarMediumWidget"
strings "$WIDGET_EXECUTABLE" | rg -q 'ViabarLargeWidget' ||
    fail "Widget executable does not expose ViabarLargeWidget"
codesign --verify --deep --strict "$APP_PATH"

log_step "Creating frozen-local DMG"
hdiutil create \
    -volname "Viabar $VERSION Frozen Local" \
    -srcfolder "$DMG_STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

log_step "Verifying frozen-local DMG"
hdiutil verify "$DMG_PATH"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH"
[[ -d "$MOUNT_DIR/Viabar.app" ]] || fail "mounted DMG is missing Viabar.app"
[[ -L "$MOUNT_DIR/Applications" ]] || fail "mounted DMG is missing Applications shortcut"

printf '\nFrozen-local DMG ready: %s\n' "$DMG_PATH"
printf 'This package is ad hoc signed and not notarized.\n'
printf 'On a new Mac: drag Viabar.app into /Applications, right-click Open once, launch Viabar, then add a Viabar Widget from the macOS Widget gallery.\n'
```

- [ ] **Step 4: Run packaging static checks**

Run:

```bash
chmod +x scripts/package_frozen_local.sh scripts/tests/test_frozen_local_package.sh
bash -n scripts/package_frozen_local.sh scripts/tests/test_frozen_local_package.sh
bash scripts/tests/test_frozen_local_package.sh
```

Expected:

```text
PASS: frozen-local package static checks
```

- [ ] **Step 5: Commit frozen-local packaging**

```bash
git add -- scripts/package_frozen_local.sh scripts/tests/test_frozen_local_package.sh
git commit -m "feat: add frozen local dmg packaging"
```

### Task 6: Document Frozen-Local Installation And Recovery

**Files:**
- Modify: `docs/releasing.md`

- [ ] **Step 1: Add the frozen-local documentation**

Append this section to `docs/releasing.md`:

````markdown
## Frozen-local DMG

当 Apple Developer Program 未续费、没有 Developer ID Application 证书时，使用独立的本地冻结版打包脚本：

```bash
./scripts/package_frozen_local.sh 1.0.0
```

产物：

```text
dist/Viabar-1.0.0-frozen-local.dmg
```

该包使用 ad hoc 签名，不包含 Apple Developer ID 信任链，也未经过 notarization。它适合在自己的 Mac 或新 Mac 上手动安装，不应被描述为正式公开分发包。

安装步骤：

1. 将 `Viabar.app` 拖入 `/Applications`。
2. 首次安装时，右键 `/Applications/Viabar.app` 并选择“打开”。
3. 启动 Viabar 一次。
4. 打开 macOS Widget 面板。
5. 将 Viabar Medium 或 Large 拖到桌面。
6. 右键 Widget，选择“编辑小组件”，再选择项目。

如果 Widget 面板仍显示旧版本或没有出现 Viabar，退出 Viabar 后执行：

```bash
./scripts/reset_local_widget_cache.sh
```

这个脚本只清理 Widget Chrono 缓存，不会删除 App Group 中的业务数据库。清理后重新启动 Viabar；如果系统索引仍未刷新，再重新登录或重启 macOS。
````

- [ ] **Step 2: Run static verification**

Run:

```bash
bash scripts/tests/test_widget_static.sh
bash scripts/tests/test_reset_local_widget_cache.sh
bash scripts/tests/test_frozen_local_package.sh
bash scripts/tests/test_release_preflight.sh
bash scripts/tests/test_sparkle_config.sh
bash -n \
  scripts/package_frozen_local.sh \
  scripts/reset_local_widget_cache.sh \
  scripts/refresh_widget_debug.sh \
  scripts/release.sh \
  scripts/tests/test_widget_static.sh \
  scripts/tests/test_reset_local_widget_cache.sh \
  scripts/tests/test_frozen_local_package.sh
git diff --check
plutil -lint \
  Viabar.xcodeproj/project.pbxproj \
  Viabar/Info.plist \
  ViabarWidget/Info.plist \
  Viabar/Viabar.entitlements \
  ViabarWidget/ViabarWidget.entitlements \
  ViabarWidget/en.lproj/Localizable.strings \
  ViabarWidget/zh-Hans.lproj/Localizable.strings
```

Expected: every script prints PASS or exits 0; every plist prints `OK`; `git diff --check` exits 0.

- [ ] **Step 3: Commit documentation**

```bash
git add -- docs/releasing.md
git commit -m "docs: document frozen local widget install"
```

### Task 7: Authorized Build, Package, And Manual Widget Acceptance

**Files:**
- Verify only: `dist/Viabar-<version>-frozen-local.dmg`
- Verify only: `/Applications/Viabar.app`
- Verify only: `~/Library/Containers/com.tyrival.Viabar.Widget/Data/SystemData/com.apple.chrono`
- Preserve: `~/Library/Group Containers/group.com.tyrival.Viabar`

- [ ] **Step 1: Ask for explicit authorization**

Before running compilation or packaging, ask the user to authorize:

```text
May I archive Viabar, create the frozen-local DMG, reset only the Widget Chrono cache, and guide the local installation check? The App Group business database will be preserved.
```

- [ ] **Step 2: Run Swift tests after authorization**

Run:

```bash
xcodebuild test \
  -project Viabar.xcodeproj \
  -scheme Viabar \
  -destination 'platform=macOS' \
  -only-testing:ViabarTests
```

Expected: PASS.

- [ ] **Step 3: Build the frozen-local DMG**

Choose the requested frozen release version and run:

```bash
./scripts/package_frozen_local.sh <version>
```

Expected:

```text
Frozen-local DMG ready: .../dist/Viabar-<version>-frozen-local.dmg
```

- [ ] **Step 4: Reset only Widget cache before reinstalling**

Run:

```bash
./scripts/reset_local_widget_cache.sh
```

Expected: the script prints the preserved App Group directory and removed Chrono cache path.

- [ ] **Step 5: Verify the preserved shared database**

Run:

```bash
sqlite3 -readonly \
  "$HOME/Library/Group Containers/group.com.tyrival.Viabar/ViabarSharedStore/default.store" \
  "PRAGMA integrity_check;"
```

Expected:

```text
ok
```

- [ ] **Step 6: Install and launch manually**

Mount the DMG, drag `Viabar.app` to `/Applications`, right-click Open once if macOS prompts, then launch Viabar one time. Do not delete the App Group directory.

- [ ] **Step 7: Verify gallery discovery**

Open the macOS Widget gallery and confirm that Viabar exposes:

```text
Viabar Medium
Viabar Large
```

- [ ] **Step 8: Verify the configuration blocker is resolved**

Drag both sizes to the desktop. For each size:

1. Right-click the Widget.
2. Choose Edit Widget.
3. Select an active project.
4. Close the editor.
5. Confirm that the desktop instance updates from `请选择项目` to the selected project content.

This step is mandatory. A preview timeline containing the selected UUID is not sufficient.

- [ ] **Step 9: Verify shared interactions**

For Medium and Large:

1. Complete one visible task with the checkbox.
2. Confirm both Widget sizes refresh.
3. Click a task title and confirm Viabar opens the matching task.
4. Confirm Medium shows fewer visible task rows than Large.

- [ ] **Step 10: Inspect final repository state**

Run:

```bash
git status --short
git log --oneline -8
```

Expected: only intended commits and any explicitly retained DMG artifacts are present.
