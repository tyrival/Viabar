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
