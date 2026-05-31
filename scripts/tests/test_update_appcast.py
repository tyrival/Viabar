import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "update_appcast.py"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def sparkle(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


class UpdateAppcastTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.appcast = Path(self.temp_dir.name) / "appcast.xml"
        self.appcast.write_text(
            """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Viabar</title>
    <item>
      <title>Version 1.0.5</title>
      <sparkle:version>6</sparkle:version>
      <sparkle:shortVersionString>1.0.5</sparkle:shortVersionString>
      <enclosure url="https://example.com/Viabar-1.0.5.dmg"
                 sparkle:version="6"
                 sparkle:shortVersionString="1.0.5"
                 length="42"
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
""",
            encoding="utf-8",
        )

    def run_update(
        self,
        *,
        version: str = "1.0.6",
        build: str = "7",
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--appcast",
                str(self.appcast),
                "--version",
                version,
                "--build",
                build,
                "--minimum-system-version",
                "14.0",
                "--description",
                "Widget refresh",
                "--url",
                f"https://example.com/Viabar-{version}.dmg",
                "--length",
                "84",
                "--signature",
                "signed-value",
            ],
            check=check,
            capture_output=True,
            text=True,
        )

    def test_inserts_signed_item_before_existing_versions(self) -> None:
        self.run_update()

        channel = ET.parse(self.appcast).getroot().find("channel")
        self.assertIsNotNone(channel)
        items = channel.findall("item")
        self.assertEqual(["Version 1.0.6", "Version 1.0.5"], [item.findtext("title") for item in items])

        enclosure = items[0].find("enclosure")
        self.assertEqual("signed-value", enclosure.attrib[sparkle("edSignature")])
        self.assertEqual("84", enclosure.attrib["length"])
        self.assertEqual("14.0", items[0].findtext(sparkle("minimumSystemVersion")))

    def test_rejects_duplicate_marketing_version(self) -> None:
        result = self.run_update(version="1.0.5", build="7", check=False)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("already exists", result.stderr)

    def test_rejects_non_increasing_build_number(self) -> None:
        result = self.run_update(version="1.0.6", build="6", check=False)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("must be greater than existing build", result.stderr)

    def test_rejects_malformed_xml(self) -> None:
        self.appcast.write_text("<rss>", encoding="utf-8")

        result = self.run_update(check=False)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("invalid appcast XML", result.stderr)


if __name__ == "__main__":
    unittest.main()
