#!/usr/bin/env bash
set -euo pipefail

LSREGISTER="${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
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
