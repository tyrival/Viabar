#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_frozen_local.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -f "$PACKAGE_SCRIPT" ]] || fail "frozen-local package script is missing"
if rg -q 'CODE_SIGN_IDENTITY="-"' "$PACKAGE_SCRIPT"; then
    fail "frozen-local Widget package must not use ad hoc signing"
fi
rg -q -- '-allowProvisioningUpdates' "$PACKAGE_SCRIPT" ||
    fail "frozen-local Widget package must allow Xcode to refresh development profiles"
rg -q 'embedded\.provisionprofile' "$PACKAGE_SCRIPT" ||
    fail "frozen-local Widget package must verify embedded provisioning profiles"
rg -q 'TeamIdentifier' "$PACKAGE_SCRIPT" ||
    fail "frozen-local Widget package must verify a signing team"
rg -Fq 'group\.com\.tyrival\.Viabar' "$PACKAGE_SCRIPT" ||
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
