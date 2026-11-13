"""Installer allowlist, reproducibility and no-leak packaging regressions.

All tests are offline: a fake launcher is used and no executable is started.
"""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import tempfile
import unittest
import zipfile

from build import PAYLOAD, INSTALLER_SCRIPT, MANIFEST, bundle_payload, load_install_files


class InstallerPackagingTests(unittest.TestCase):
    def prepare_fixture(self, root: Path) -> list[str]:
        names = load_install_files(PAYLOAD)
        for name in names:
            if name != "ZhidaoAssistant.exe":
                shutil.copyfile(PAYLOAD / name, root / name)
        shutil.copyfile(PAYLOAD / INSTALLER_SCRIPT, root / INSTALLER_SCRIPT)
        return names

    def test_real_manifest_is_whitelisted_and_matches_installer(self):
        names = load_install_files(PAYLOAD)
        self.assertEqual(len(names), len(set(x.casefold() for x in names)))
        self.assertIn(MANIFEST, names)
        self.assertIn("ZhidaoAssistant.exe", names)
        self.assertIn("Patch-ZHS-0.1.5.py", names)
        install_script = (PAYLOAD / INSTALLER_SCRIPT).read_text("utf-8-sig")
        self.assertIn("Get-Content -LiteralPath $manifestFile", install_script)
        self.assertIn("ConvertFrom-Json", install_script)
        self.assertNotIn("$files = @('ZhidaoAssistant.exe'", install_script)

    def test_unlisted_payload_is_rejected_not_silently_published(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare_fixture(root)
            (root / "accidental-secret.txt").write_text("not-for-release", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Unlisted payload files"):
                load_install_files(root)

    def test_unsafe_manifest_names_are_rejected(self):
        for bad in ("../secrets", "subdir/other.py", r"subdir\\other.py",
                    "file:stream", ".", ".."):
            with self.subTest(name=bad), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / MANIFEST).write_text(json.dumps(["ZhidaoAssistant.exe", MANIFEST, bad]))
                with self.assertRaises(ValueError):
                    load_install_files(root)

    def test_case_insensitive_duplicates_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / MANIFEST).write_text(json.dumps(["ZhidaoAssistant.exe", MANIFEST, "README", "readme"]))
            with self.assertRaises(ValueError):
                load_install_files(root)

    def test_archive_contains_exact_allowlist_and_is_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / "payload"
            payload.mkdir()
            declared = self.prepare_fixture(payload)
            launcher = root / "ZhidaoAssistant.exe"
            launcher.write_bytes(bytes([77, 90, 0]) + b"offline fake launcher")
            first, second = root / "first.zip", root / "second.zip"
            names = bundle_payload(payload, launcher, first)
            self.assertEqual(names, sorted(set(declared) | {INSTALLER_SCRIPT}))
            self.assertEqual(names, bundle_payload(payload, launcher, second))
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(sorted(archive.namelist()), names)
                self.assertEqual(archive.read("ZhidaoAssistant.exe"), launcher.read_bytes())
                self.assertEqual(archive.read(MANIFEST), (payload / MANIFEST).read_bytes())


if __name__ == "__main__":
    unittest.main()
