#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_REPO="${RELEASE_REPO:-tyrival/Viabar-Releases}"
RELEASE_REPO_DIR="${RELEASE_REPO_DIR:-$ROOT_DIR/../Viabar-Releases}"
APPCAST_PATH="$RELEASE_REPO_DIR/appcast.xml"
VERSION="${1:-}"
RELEASE_NOTES="${2:-常规更新与性能优化。}"
TAG="v$VERSION"

source "$ROOT_DIR/scripts/sparkle_tools.sh"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "version must use X.Y.Z format, for example: ./scripts/release.sh 1.0.7 \"更新说明\""
fi

command -v gh >/dev/null 2>&1 || fail "GitHub CLI 'gh' is required. Install it with: brew install gh"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not logged in. Run: gh auth login"

if [[ ! -d "$RELEASE_REPO_DIR/.git" ]]; then
    if [[ -e "$RELEASE_REPO_DIR" ]]; then
        fail "public release repository path exists but is not a Git repository: $RELEASE_REPO_DIR"
    fi
    git clone "https://github.com/$RELEASE_REPO.git" "$RELEASE_REPO_DIR"
fi

if [[ -n "$(git -C "$RELEASE_REPO_DIR" status --porcelain)" ]]; then
    fail "public release repository has uncommitted changes: $RELEASE_REPO_DIR"
fi

git -C "$RELEASE_REPO_DIR" pull --ff-only
[[ -f "$APPCAST_PATH" ]] || fail "appcast.xml was not found in $RELEASE_REPO_DIR"

if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    fail "GitHub Release $TAG already exists in $RELEASE_REPO"
fi

SIGN_UPDATE="$(find_sparkle_tool sign_update)"
GENERATE_KEYS="$(find_sparkle_tool generate_keys)"
"$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p >/dev/null 2>&1 ||
    fail "Sparkle key is missing. Run: ./scripts/bootstrap-sparkle.sh"

NEXT_BUILD_NUMBER="$(
    python3 - "$APPCAST_PATH" "$VERSION" <<'PY'
import sys
import xml.etree.ElementTree as ET

sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
root = ET.parse(sys.argv[1]).getroot()
items = root.findall("./channel/item")
versions = {
    item.findtext(f"{{{sparkle_ns}}}shortVersionString")
    for item in items
}
if sys.argv[2] in versions:
    raise SystemExit(f"error: version {sys.argv[2]} already exists in appcast.xml")
builds = []
for item in items:
    value = item.findtext(f"{{{sparkle_ns}}}version")
    if value:
        builds.append(int(value))
print(max(builds, default=0) + 1)
PY
)"
BUILD_NUMBER="${RELEASE_BUILD_NUMBER:-$NEXT_BUILD_NUMBER}"
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || (( BUILD_NUMBER < NEXT_BUILD_NUMBER )); then
    fail "RELEASE_BUILD_NUMBER must be an integer greater than or equal to $NEXT_BUILD_NUMBER"
fi

MINIMUM_SYSTEM_VERSION="$(
    xcodebuild -showBuildSettings \
        -project "$ROOT_DIR/Viabar.xcodeproj" \
        -scheme Viabar \
        -configuration Release |
        awk '/^[[:space:]]*MACOSX_DEPLOYMENT_TARGET = / { print $3; exit }'
)"
[[ -n "$MINIMUM_SYSTEM_VERSION" ]] ||
    fail "MACOSX_DEPLOYMENT_TARGET was not found in the Viabar Release build settings"

BUILD_DIR="$ROOT_DIR/build/LocalRelease"
ARCHIVE_PATH="$BUILD_DIR/Viabar.xcarchive"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/Viabar-$VERSION.dmg"
DOWNLOAD_URL="https://github.com/$RELEASE_REPO/releases/download/$TAG/Viabar-$VERSION.dmg"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

printf 'Archiving Viabar %s (%s)...\n' "$VERSION" "$BUILD_NUMBER"
xcodebuild archive \
    -project "$ROOT_DIR/Viabar.xcodeproj" \
    -scheme Viabar \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    COMPILER_INDEX_STORE_ENABLE=NO

cp -R "$ARCHIVE_PATH/Products/Applications/Viabar.app" "$DIST_DIR/Viabar.app"

printf 'Creating DMG...\n'
hdiutil create \
    -volname "Viabar $VERSION" \
    -srcfolder "$DIST_DIR/Viabar.app" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

printf 'Signing Sparkle update...\n'
SIGNATURE="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" -p "$DMG_PATH")"
LENGTH="$(stat -f '%z' "$DMG_PATH")"

printf 'Uploading %s...\n' "$TAG"
gh release create "$TAG" "$DMG_PATH" \
    --repo "$RELEASE_REPO" \
    --title "$TAG" \
    --notes "$RELEASE_NOTES"

python3 "$ROOT_DIR/scripts/update_appcast.py" \
    --appcast "$APPCAST_PATH" \
    --version "$VERSION" \
    --build "$BUILD_NUMBER" \
    --minimum-system-version "$MINIMUM_SYSTEM_VERSION" \
    --description "$RELEASE_NOTES" \
    --url "$DOWNLOAD_URL" \
    --length "$LENGTH" \
    --signature "$SIGNATURE"

git -C "$RELEASE_REPO_DIR" add -- appcast.xml
git -C "$RELEASE_REPO_DIR" commit -m "release: Viabar $VERSION"
git -C "$RELEASE_REPO_DIR" push origin main

printf '\nPublished Viabar %s (%s)\n' "$VERSION" "$BUILD_NUMBER"
printf 'DMG: %s\n' "$DOWNLOAD_URL"
printf 'Appcast: https://raw.githubusercontent.com/%s/main/appcast.xml\n' "$RELEASE_REPO"
