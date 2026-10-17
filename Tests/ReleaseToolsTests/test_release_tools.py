import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile


MODULE_PATH = Path(__file__).resolve().parents[2] / "scripts/release_tools.py"
spec = importlib.util.spec_from_file_location("release_tools", MODULE_PATH)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="EncoBar source test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in release.REQUIRED_FILES:
            self.write(name, "fixture\n")
        with (self.root / "Resources/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleShortVersionString": "0.3.1"}, stream)
        self.write("docs/releases/0.3.1.md", "Release notes\n")
        self.write("dist/packages/EncoBar-0.3.1.pkg", "package fixture")

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_archive_is_deterministic_and_excludes_local_artifacts(self):
        for name in (".local/private.md", ".build/cache", "dist/old.pkg",
                     "docs/debug.log", "scripts/__pycache__/cache.pyc", "docs/.DS_Store"):
            self.write(name, "private")
        first = self.root / "one.zip"
        second = self.root / "two.zip"
        release.make_source_zip(self.root, first, "0.3.1")
        release.make_source_zip(self.root, second, "0.3.1")
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with zipfile.ZipFile(first) as archive:
            names = archive.namelist()
            self.assertIn("EncoBar-0.3.1/LICENSE", names)
            self.assertFalse(any("private" in n or "cache" in n or n.endswith(".log") for n in names))
            self.assertTrue(all(n.startswith("EncoBar-0.3.1/") for n in names))

    def test_rejects_symlinks_in_public_source(self):
        (self.root / "Sources/link.swift").symlink_to(self.root / "LICENSE")
        with self.assertRaisesRegex(ValueError, "symlink"):
            release.source_files(self.root)

    def test_rejects_private_data_and_key_files(self):
        bad = self.root / "docs/private.md"
        for content in ("/Users/" + "private-person/project", ":".join(["AA", "BB", "CC", "DD", "EE", "FF"]),
                        "caseBatteryHistory." + "a" * 64,
                        "-----BEGIN " + "PRIVATE KEY-----"):
            bad.write_text(content)
            with self.assertRaisesRegex(ValueError, "private"):
                release.source_files(self.root)
        bad.unlink()
        self.write("Resources/secret.p12", "key")
        with self.assertRaisesRegex(ValueError, "secret"):
            release.source_files(self.root)

    def test_allows_anonymous_fixture_home(self):
        self.write("Tests/path.swift", "/Users/Example User/Library")
        self.assertIn(Path("Tests/path.swift"), release.source_files(self.root))

    def test_auditor_source_can_be_distributed(self):
        release.audit_text(MODULE_PATH.read_text(), MODULE_PATH.name)

    def test_release_manifest_detects_tampering_and_unlisted_files(self):
        output = release.prepare(self.root)
        release.verify(self.root)
        package = output / "EncoBar-0.3.1-macos-arm64.pkg"
        original = package.read_bytes()
        package.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum"):
            release.verify(self.root)
        package.write_bytes(original)
        (output / "unexpected.log").write_text("oops")
        with self.assertRaisesRegex(ValueError, "file set"):
            release.verify(self.root)

    def test_rejects_invalid_version(self):
        with (self.root / "Resources/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleShortVersionString": "../unsafe"}, stream)
        with self.assertRaisesRegex(ValueError, "version"):
            release.version_for(self.root)


if __name__ == "__main__":
    unittest.main()
