#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/sparkle_tools.sh"

GENERATE_KEYS="$(find_sparkle_tool generate_keys)"

printf 'Initializing Sparkle EdDSA key in the macOS login Keychain...\n'
"$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT"

printf '\nPublic key only:\n'
"$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p
printf '\nAdd this value to the Viabar target build setting INFOPLIST_KEY_SUPublicEDKey.\n'
