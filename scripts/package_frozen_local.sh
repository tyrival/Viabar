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
        rg -q 'group\.com\.tyrival\.Viabar' ||
        fail "missing App Group entitlement: $bundle"
}

assert_development_signing() {
    local bundle="$1"
    local profile="$bundle/Contents/embedded.provisionprofile"
    local signing_info
    local expiration

    signing_info="$(codesign -dvv "$bundle" 2>&1)"
    rg -q 'TeamIdentifier=[A-Z0-9]+' <<< "$signing_info" ||
        fail "missing signing TeamIdentifier: $bundle"
    [[ -f "$profile" ]] || fail "missing embedded provisioning profile: $bundle"

    expiration="$(
        security cms -D -i "$profile" 2>/dev/null |
            plutil -extract ExpirationDate raw -o - -
    )"
    [[ -n "$expiration" ]] || fail "could not read provisioning profile expiration: $bundle"
    printf 'Provisioning profile expires: %s\n' "$expiration"
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
    -allowProvisioningUpdates \
    MARKETING_VERSION="$VERSION" \
    COMPILER_INDEX_STORE_ENABLE=NO

cp -R "$ARCHIVE_PATH/Products/Applications/Viabar.app" "$APP_PATH"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

log_step "Validating embedded Widget Extension"
[[ "$(find "$APP_PATH/Contents/PlugIns" -maxdepth 1 -name '*.appex' | wc -l | tr -d ' ')" == "1" ]] ||
    fail "Viabar.app must embed exactly one Widget Extension"
[[ -x "$WIDGET_EXECUTABLE" ]] || fail "Widget executable was not found"
assert_app_group "$APP_PATH"
assert_app_group "$WIDGET_PATH"
assert_development_signing "$APP_PATH"
assert_development_signing "$WIDGET_PATH"
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
printf 'This package uses a local development profile and is not notarized.\n'
printf 'Install it on another Mac before the embedded provisioning profiles expire.\n'
printf 'On a new Mac: drag Viabar.app into /Applications, right-click Open once, launch Viabar, then add a Viabar Widget from the macOS Widget gallery.\n'
