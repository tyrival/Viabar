#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_FILE="$ROOT_DIR/Viabar.xcodeproj/project.pbxproj"
SHARED_CONTAINER="$ROOT_DIR/Viabar/System/SharedModelContainer.swift"
IOS_APP="$ROOT_DIR/ViabariOS/ViabariOSApp.swift"
IOS_ENTITLEMENTS="$ROOT_DIR/ViabariOS/ViabariOS.entitlements"
IOS_WIDGET_DIR="$ROOT_DIR/ViabariOSWidget"
IOS_WIDGET_ENTITLEMENTS="$IOS_WIDGET_DIR/ViabariOSWidget.entitlements"
IOS_WIDGET_PLIST="$IOS_WIDGET_DIR/Info.plist"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -d "$IOS_WIDGET_DIR" ]] ||
    fail "iOS Widget resources must live in ViabariOSWidget/"
[[ ! -e "$ROOT_DIR/ViabariOSWidgetExtension" ]] ||
    fail "old ViabariOSWidgetExtension/ folder must be removed"

if rg -q 'ViabariOSWidgetExtensionExtension' "$PROJECT_FILE"; then
    fail "duplicated Extension suffix must not return"
fi

rg -q 'IPHONEOS_DEPLOYMENT_TARGET = 17\.6;' "$PROJECT_FILE" ||
    fail "iOS deployment target must stay at 17.6"
rg -q 'MACOSX_DEPLOYMENT_TARGET = 15\.6;' "$PROJECT_FILE" ||
    fail "macOS deployment target must stay at 15.6"
rg -q 'PRODUCT_BUNDLE_IDENTIFIER = com\.tyrival\.ViabariOS\.Widget;' "$PROJECT_FILE" ||
    fail "iOS Widget bundle identifier must use com.tyrival.ViabariOS.Widget"
rg -q 'CODE_SIGN_ENTITLEMENTS = ViabariOS/ViabariOS\.entitlements;' "$PROJECT_FILE" ||
    fail "iOS app must use its App Group entitlements"
rg -q 'CODE_SIGN_ENTITLEMENTS = ViabariOSWidget/ViabariOSWidget\.entitlements;' "$PROJECT_FILE" ||
    fail "iOS Widget must use its App Group entitlements"
widget_manual_plist_count="$(
    rg -c 'INFOPLIST_FILE = ViabariOSWidget/Info\.plist;' "$PROJECT_FILE"
)"
widget_manual_plist_only_count="$(
    perl -0ne '
        while (/GENERATE_INFOPLIST_FILE = NO;\n\s+INFOPLIST_FILE = ViabariOSWidget\/Info\.plist;/g) {
            $count += 1;
        }
        print $count // 0;
    ' "$PROJECT_FILE"
)"
[[ "$widget_manual_plist_count" -eq 2 ]] ||
    fail "iOS Widget Debug and Release must both use the checked-in Info.plist"
[[ "$widget_manual_plist_only_count" -eq 2 ]] ||
    fail "iOS Widget must disable generated Info.plist in Debug and Release"
for required_widget_plist_key in \
    CFBundleExecutable \
    CFBundleIdentifier \
    CFBundleInfoDictionaryVersion \
    CFBundleName \
    CFBundlePackageType \
    CFBundleShortVersionString \
    CFBundleVersion \
    NSExtension; do
    plutil -extract "$required_widget_plist_key" raw "$IOS_WIDGET_PLIST" >/dev/null ||
        fail "iOS Widget Info.plist must declare $required_widget_plist_key"
done

for entitlements in "$IOS_ENTITLEMENTS" "$IOS_WIDGET_ENTITLEMENTS"; do
    rg -q 'group\.com\.tyrival\.Viabar' "$entitlements" ||
        fail "$entitlements must declare the shared Viabar App Group"
done

if rg -q 'group\.com\.tyrival\.ViabariOS' \
    "$SHARED_CONTAINER" "$IOS_ENTITLEMENTS" "$IOS_WIDGET_ENTITLEMENTS"; then
    fail "temporary iOS-only App Group must not remain active"
fi

if rg -q '#if os\(iOS\)' "$SHARED_CONTAINER"; then
    fail "SharedModelContainer must not branch the App Group by platform"
fi
rg -q 'static func makeIOSAppContainer' "$SHARED_CONTAINER" ||
    fail "SharedModelContainer must expose an iOS first-store entry point"
rg -q 'SharedModelContainer\.makeIOSAppContainer\(\)' "$IOS_APP" ||
    fail "iOS app must open the iOS App Group container"
rg -q 'D10000612FDD000100000001 /\* ViabarWidget \*/,' "$PROJECT_FILE" ||
    fail "iOS Widget target must reuse the ViabarWidget synchronized group"
rg -q 'Exceptions for "ViabarWidget" folder in "ViabariOSWidgetExtension" target' "$PROJECT_FILE" ||
    fail "iOS Widget must exclude the macOS Widget plist from shared resources"
shared_widget_ios_exclusions="$(
    perl -0ne '
        if (/membershipExceptions = \(\s*Info\.plist,\s*\);\s*target = C3AE2DFF2FCE642F00528C34/s) {
            print "yes";
        }
    ' "$PROJECT_FILE"
)"
[[ "$shared_widget_ios_exclusions" == "yes" ]] ||
    fail "shared Widget iOS exclusions must include the macOS plist"

if rg -q 'Favorite Emoji|SimpleEntry|ConfigurationAppIntent' "$IOS_WIDGET_DIR" --glob '*.swift'; then
    fail "Xcode template Widget implementation must be removed"
fi
if rg -q 'IntentModes|supportedModes' "$ROOT_DIR/ViabarWidget" --glob '*.swift'; then
    fail "shared Widget intents must not require macOS 26 or iOS 26 IntentModes"
fi

printf 'PASS: iOS foundation static checks\n'
