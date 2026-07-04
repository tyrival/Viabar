#!/usr/bin/env bash
# 查询 Viabar 已发布的最新版本
# 发布渠道: tyrival/Viabar-Releases 仓库的 appcast.xml
#
# 用法: ./scripts/version.sh         查询最新发布版本
#       ./scripts/version.sh --all   列出所有历史版本

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST_URL="https://raw.githubusercontent.com/tyrival/Viabar-Releases/main/appcast.xml"
LOCAL_APPCAST="$ROOT_DIR/../Viabar-Releases/appcast.xml"
SHOW_ALL=false

if [[ "${1:-}" == "--all" ]]; then
    SHOW_ALL=true
fi

if [[ -f "$LOCAL_APPCAST" ]]; then
    XML_FILE="$LOCAL_APPCAST"
else
    XML_FILE="$APPCAST_URL"
fi

python3 - "$XML_FILE" "$SHOW_ALL" <<'PYEOF'
import sys
import xml.etree.ElementTree as ET
from urllib.request import urlopen

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

def sparkle(name):
    return f"{{{SPARKLE_NS}}}{name}"

xml_source = sys.argv[1]
show_all = sys.argv[2] == "true"

try:
    if xml_source.startswith("http"):
        tree = ET.parse(urlopen(xml_source))
    else:
        tree = ET.parse(xml_source)
except Exception as e:
    print(f"错误: 无法读取 appcast — {e}", file=sys.stderr)
    sys.exit(1)

items = tree.getroot().findall("./channel/item")
releases = []
for item in items:
    version = item.findtext(sparkle("shortVersionString"))
    build = item.findtext(sparkle("version"))
    title = item.findtext("title")
    min_sys = item.findtext(sparkle("minimumSystemVersion"))
    if version:
        releases.append({
            "version": version,
            "build": build or "-",
            "title": title or f"Version {version}",
            "min_system": min_sys or "-",
        })

if not releases:
    print("未找到任何发布版本。")
    sys.exit(0)

if show_all:
    print("=== Viabar 所有已发布版本 ===\n")
    for i, r in enumerate(releases):
        marker = "← 最新" if i == 0 else ""
        print(f"  {r['title']}")
        print(f"    版本: {r['version']}  |  构建号: {r['build']}  |  最低系统: {r['min_system']}  {marker}")
        print()
else:
    latest = releases[0]
    print(f"最新发布版本: {latest['version']} (build {latest['build']})")
    print(f"最低系统要求: macOS {latest['min_system']}")

PYEOF
