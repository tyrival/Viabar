#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Viabar.xcodeproj/project.pbxproj"
INFO_PLIST="$ROOT_DIR/Viabar/Info.plist"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

if [[ "$(rg -c 'INFOPLIST_FILE = Viabar/Info.plist;' "$PROJECT_FILE")" != "2" ]]; then
    fail "Viabar Debug and Release configurations must use Viabar/Info.plist"
fi

if rg -q 'INFOPLIST_KEY_SU' "$PROJECT_FILE"; then
    fail "Sparkle settings must live in Viabar/Info.plist instead of generated Info.plist build settings"
fi

if ! plutil -extract SUFeedURL raw "$INFO_PLIST" >/dev/null 2>&1; then
    fail "Viabar Info.plist must define SUFeedURL"
fi

if ! plutil -extract SUPublicEDKey raw "$INFO_PLIST" >/dev/null 2>&1; then
    fail "Viabar Info.plist must define SUPublicEDKey"
fi

if ! plutil -extract SUEnableInstallerLauncherService raw "$INFO_PLIST" >/dev/null 2>&1; then
    fail "Viabar Info.plist must enable the Sparkle installer launcher service"
fi

if [[ "$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST" 2>/dev/null)" != '$(PRODUCT_BUNDLE_IDENTIFIER)' ]]; then
    fail "Viabar Info.plist must derive its bundle identifier from Xcode build settings"
fi

if [[ "$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST" 2>/dev/null)" != '$(MARKETING_VERSION)' ]]; then
    fail "Viabar Info.plist must derive its marketing version from Xcode build settings"
fi

if [[ "$(plutil -extract CFBundleVersion raw "$INFO_PLIST" 2>/dev/null)" != '$(CURRENT_PROJECT_VERSION)' ]]; then
    fail "Viabar Info.plist must derive its build number from Xcode build settings"
fi

printf 'PASS: Sparkle configuration checks\n'
