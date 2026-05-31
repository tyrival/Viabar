#!/usr/bin/env bash

SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.tyrival.Viabar}"

find_sparkle_tool() {
    local tool_name="$1"
    local candidate

    candidate="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool_name" \
        -type f \
        -print \
        -quit 2>/dev/null)"

    if [[ -z "$candidate" ]]; then
        printf "error: Sparkle tool '%s' was not found. Resolve the Sparkle Swift package in Xcode first.\\n" "$tool_name" >&2
        return 1
    fi

    printf '%s\n' "$candidate"
}
