#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_SCRIPT="$ROOT_DIR/scripts/release.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_fails_with() {
    local expected="$1"
    shift
    local output
    if output="$("$@" 2>&1)"; then
        fail "command unexpectedly succeeded: $*"
    fi
    if [[ "$output" != *"$expected"* ]]; then
        fail "expected '$expected' in output, got: $output"
    fi
}

EMPTY_BIN="$TEMP_DIR/empty-bin"
mkdir -p "$EMPTY_BIN"

assert_fails_with \
    "version must use X.Y.Z format" \
    env PATH="$EMPTY_BIN:/usr/bin:/bin" RELEASE_REPO_DIR="$TEMP_DIR/releases" \
    "$RELEASE_SCRIPT" "v1.2.3" "notes"

assert_fails_with \
    "GitHub CLI 'gh' is required" \
    env PATH="$EMPTY_BIN:/usr/bin:/bin" RELEASE_REPO_DIR="$TEMP_DIR/releases" \
    "$RELEASE_SCRIPT" "1.2.3" "notes"

DIRTY_REPO="$TEMP_DIR/dirty-releases"
mkdir -p "$DIRTY_REPO"
git -C "$DIRTY_REPO" init -q
git -C "$DIRTY_REPO" config user.email "test@example.com"
git -C "$DIRTY_REPO" config user.name "Test"
printf '<rss><channel/></rss>\n' > "$DIRTY_REPO/appcast.xml"
git -C "$DIRTY_REPO" add appcast.xml
git -C "$DIRTY_REPO" commit -qm "fixture"
printf 'dirty\n' >> "$DIRTY_REPO/appcast.xml"

FAKE_BIN="$TEMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN/gh"

assert_fails_with \
    "public release repository has uncommitted changes" \
    env PATH="$FAKE_BIN:/usr/bin:/bin" RELEASE_REPO_DIR="$DIRTY_REPO" \
    "$RELEASE_SCRIPT" "1.2.3" "notes"

if rg -q 'MACOSX_DEPLOYMENT_TARGET=14\.0|--minimum-system-version "14\.0"' "$RELEASE_SCRIPT"; then
    fail "release script must not override the Xcode deployment target with 14.0"
fi

if ! rg -q 'xcodebuild -showBuildSettings' "$RELEASE_SCRIPT"; then
    fail "release script must read the deployment target from Xcode build settings"
fi

if ! rg -q 'RELEASE_BUILD_NUMBER' "$RELEASE_SCRIPT"; then
    fail "release script must support a one-time build number override for migration"
fi

if rg -q 'gh auth status' "$RELEASE_SCRIPT"; then
    fail "release script must not use network-dependent gh auth status for local credential preflight"
fi

if ! rg -q 'gh auth token' "$RELEASE_SCRIPT"; then
    fail "release script must use gh auth token for local credential preflight"
fi

printf 'PASS: release preflight checks\n'
