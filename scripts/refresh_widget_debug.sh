#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
WIDGET_IDENTIFIER="com.tyrival.Viabar.Widget"

if [[ -z "${BUILT_PRODUCTS_DIR:-}" ]]; then
    BUILT_PRODUCTS_DIR="$(
        xcodebuild -showBuildSettings \
            -project "$ROOT_DIR/Viabar.xcodeproj" \
            -scheme Viabar \
            -configuration Debug |
            awk '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print substr($0, index($0, "=") + 2); exit }'
    )"
fi

DEBUG_APP="$BUILT_PRODUCTS_DIR/Viabar.app"
DEBUG_WIDGET="$DEBUG_APP/Contents/PlugIns/ViabarWidgetExtension.appex"
DEBUG_WIDGET_EXECUTABLE="$DEBUG_WIDGET/Contents/MacOS/ViabarWidgetExtension"

if [[ ! -d "$DEBUG_WIDGET" ]]; then
    printf 'error: Debug Widget was not found: %s\n' "$DEBUG_WIDGET" >&2
    printf 'Run the Viabar scheme in Xcode first, then retry.\n' >&2
    exit 1
fi

"$LSREGISTER" -f "$DEBUG_APP"
pluginkit -a "$DEBUG_WIDGET"
pkill -f "$DEBUG_WIDGET_EXECUTABLE" >/dev/null 2>&1 || true

printf 'Refreshed Debug Widget registration:\n'
pluginkit -m -A -D -v -i "$WIDGET_IDENTIFIER"
