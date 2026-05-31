#!/usr/bin/env python3
import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"

ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)


def sparkle(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


def fail(message: str) -> None:
    raise ValueError(message)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Insert a signed Viabar release into a Sparkle appcast.")
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--minimum-system-version", required=True)
    parser.add_argument("--description", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True, type=int)
    parser.add_argument("--signature", required=True)
    return parser.parse_args()


def update_appcast(args: argparse.Namespace) -> None:
    try:
        tree = ET.parse(args.appcast)
    except ET.ParseError as error:
        fail(f"invalid appcast XML: {error}")
    except OSError as error:
        fail(f"cannot read appcast: {error}")

    channel = tree.getroot().find("channel")
    if channel is None:
        fail("invalid appcast XML: missing channel")

    items = channel.findall("item")
    existing_versions = {
        item.findtext(sparkle("shortVersionString"))
        for item in items
        if item.findtext(sparkle("shortVersionString"))
    }
    if args.version in existing_versions:
        fail(f"version {args.version} already exists")

    existing_builds = []
    for item in items:
        build_text = item.findtext(sparkle("version"))
        if build_text is None:
            continue
        try:
            existing_builds.append(int(build_text))
        except ValueError:
            fail(f"invalid existing build number: {build_text}")

    highest_build = max(existing_builds, default=0)
    if args.build <= highest_build:
        fail(f"build {args.build} must be greater than existing build {highest_build}")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    ET.SubElement(item, sparkle("version")).text = str(args.build)
    ET.SubElement(item, sparkle("shortVersionString")).text = args.version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = args.minimum_system_version
    ET.SubElement(item, "description").text = args.description
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": args.url,
            sparkle("version"): str(args.build),
            sparkle("shortVersionString"): args.version,
            "length": str(args.length),
            "type": "application/octet-stream",
            sparkle("edSignature"): args.signature,
        },
    )

    first_item_index = next(
        (index for index, child in enumerate(channel) if child.tag == "item"),
        len(channel),
    )
    channel.insert(first_item_index, item)
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)


def main() -> int:
    try:
        update_appcast(parse_args())
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
