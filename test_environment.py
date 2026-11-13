"""Offline runtime preflight: never treat Python assertions as version checks."""
from __future__ import annotations

import importlib.util
from importlib.metadata import PackageNotFoundError
from pathlib import Path
import unittest
from unittest.mock import patch

PATH = Path(__file__).parent / "payload" / "Verify-Environment.py"
spec = importlib.util.spec_from_file_location("zhidao_environment_check", PATH)
environment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(environment)


class EnvironmentCheckTests(unittest.TestCase):
    def test_expected_version_passes(self):
        with patch.object(environment, "version", return_value="0.1.5"):
            self.assertTrue(environment.dependency_ready())
            self.assertEqual(environment.main(), 0)

    def test_wrong_version_fails_closed(self):
        for value in ("0.1.4", "0.1.6", "2.0.0"):
            with self.subTest(version=value), patch.object(environment, "version", return_value=value):
                self.assertFalse(environment.dependency_ready())
                self.assertEqual(environment.main(), 1)

    def test_missing_distribution_fails_closed(self):
        with patch.object(environment, "version", side_effect=PackageNotFoundError("zhs")):
            self.assertFalse(environment.dependency_ready())
            self.assertEqual(environment.main(), 1)

    def test_preflight_does_not_depend_on_assertions(self):
        self.assertNotIn("assert ", PATH.read_text("utf-8"))


if __name__ == "__main__":
    unittest.main()
