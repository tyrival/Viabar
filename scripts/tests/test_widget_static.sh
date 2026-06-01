#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARED_CONTAINER="$ROOT_DIR/Viabar/System/SharedModelContainer.swift"
WIDGET_CONTENT="$ROOT_DIR/Viabar/Models/WidgetContent.swift"
WIDGET_VIEW="$ROOT_DIR/ViabarWidget/ViabarLargeWidget.swift"
WIDGET_BUNDLE="$ROOT_DIR/ViabarWidget/ViabarWidgetBundle.swift"
EN_STRINGS="$ROOT_DIR/ViabarWidget/en.lproj/Localizable.strings"
ZH_STRINGS="$ROOT_DIR/ViabarWidget/zh-Hans.lproj/Localizable.strings"
PROJECT_SERVICE="$ROOT_DIR/Viabar/Services/ProjectService.swift"
REFRESH_INTENT="$ROOT_DIR/ViabarWidget/RefreshWidgetIntent.swift"
TOGGLE_INTENT="$ROOT_DIR/ViabarWidget/ToggleWidgetTaskIntent.swift"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

rg -q 'static let mediumWidgetKind = "ViabarMediumWidget"' "$SHARED_CONTAINER" ||
    fail "SharedModelContainer must define the stable Medium Widget kind"
rg -q 'static let largeWidgetKind = "ViabarLargeWidget"' "$SHARED_CONTAINER" ||
    fail "SharedModelContainer must define the stable Large Widget kind"
rg -q 'static let widgetKinds = \[mediumWidgetKind, largeWidgetKind\]' "$SHARED_CONTAINER" ||
    fail "SharedModelContainer must enumerate both Widget kinds"
rg -q 'static let mediumWidgetRowBudget = 3' "$WIDGET_CONTENT" ||
    fail "Medium Widget row budget must stay at 3"
rg -q 'static let largeWidgetRowBudget = 10' "$WIDGET_CONTENT" ||
    fail "Large Widget row budget must stay at 10"
rg -q 'struct ViabarMediumWidget: Widget' "$WIDGET_VIEW" ||
    fail "Widget extension must define ViabarMediumWidget"
rg -q '\.supportedFamilies\(\[\.systemMedium\]\)' "$WIDGET_VIEW" ||
    fail "Medium Widget must only support systemMedium"
rg -q '\.supportedFamilies\(\[\.systemLarge\]\)' "$WIDGET_VIEW" ||
    fail "Large Widget must only support systemLarge"
rg -q 'ViabarMediumWidget\(\)' "$WIDGET_BUNDLE" ||
    fail "Widget bundle must expose Medium"
rg -q 'ViabarLargeWidget\(\)' "$WIDGET_BUNDLE" ||
    fail "Widget bundle must expose Large"
rg -q '"Viabar 中号项目" = "Viabar Medium Project";' "$EN_STRINGS" ||
    fail "English localization must distinguish the Medium Widget"
rg -q '"Viabar 大号项目" = "Viabar Large Project";' "$EN_STRINGS" ||
    fail "English localization must distinguish the Large Widget"
rg -q '"Viabar 中号项目" = "Viabar 中号项目";' "$ZH_STRINGS" ||
    fail "Chinese localization must distinguish the Medium Widget"
rg -q '"Viabar 大号项目" = "Viabar 大号项目";' "$ZH_STRINGS" ||
    fail "Chinese localization must distinguish the Large Widget"
rg -q '"还有 %lld 项未完成" = "%lld unfinished remaining";' "$EN_STRINGS" ||
    fail "English localization must describe the hidden unfinished count"
rg -q '"还有 %lld 项未完成" = "还有 %lld 项未完成";' "$ZH_STRINGS" ||
    fail "Chinese localization must describe the hidden unfinished count"

for source in "$PROJECT_SERVICE" "$REFRESH_INTENT" "$TOGGLE_INTENT"; do
    rg -q 'SharedModelContainer\.widgetKinds\.forEach' "$source" ||
        fail "$source must refresh both Widget kinds"
done

printf 'PASS: Widget static checks\n'
