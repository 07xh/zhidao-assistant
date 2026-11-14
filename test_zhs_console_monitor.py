"""Offline read-only ZHS v0.1.5 stdout telemetry regression (no network)."""
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


FILE = Path(__file__).parent / "payload" / "ZHS-ConsoleMonitor.py"
SPEC = importlib.util.spec_from_file_location("zhs_console_monitor", FILE)
assert SPEC is not None and SPEC.loader is not None
observer_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(observer_module)


class ZhsConsoleMonitorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.token = "a" * 32
        self.sink = observer_module.NumericTelemetry(self.token, self.root)
        self.out = io.StringIO()
        self.tee = observer_module.StdoutObserver(self.out, self.sink)

    def test_carriage_return_playing_bar_and_resource_are_distinct(self):
        # The upstream console renders partial frames with CR, not a trailing LF.
        source = "\r    [######  ] 处理资源 2/5... "
        self.tee.write(source)
        self.tee.write("\rplaying [\x1b[36m################\x1b[0m     ] \x1b[37m48.5%\x1b[0m")
        self.tee.flush()
        state = json.loads(self.sink.path.read_text("utf-8"))
        self.assertEqual(state["videoSegmentPercent"], 48.5)
        self.assertEqual(state["resourceIndex"], 2)
        self.assertEqual(state["resourceTotal"], 5)
        self.assertEqual(self.out.getvalue(), source + "\rplaying [\x1b[36m################\x1b[0m     ] \x1b[37m48.5%\x1b[0m")
        self.assertEqual(set(state), {"v", "token", "videoSegmentPercent", "resourceIndex", "resourceTotal", "at"})

    def test_resource_change_resets_prior_segment_progress(self):
        self.tee.write("\rplaying [###  ] 72.0%")
        self.assertEqual(self.sink.percent, 72.0)
        self.tee.write("\r处理资源 3/5...")
        self.assertIsNone(self.sink.percent)
        self.assertIsNone(json.loads(self.sink.path.read_text())["videoSegmentPercent"])

    def test_rejects_out_of_range_and_never_leaks_raw_output(self):
        secret = "Cookie: secret=VERY_PRIVATE_VALUE"
        self.tee.write(secret + "\n")
        self.tee.write("playing [####] 142.2%\r")
        self.tee.write("处理资源 999999/1000000")
        self.assertFalse(self.sink.path.exists())
        self.tee.write("\rplaying [##  ] 17.5%")
        stored = self.sink.path.read_text()
        self.assertNotIn(secret, stored)
        self.assertNotIn("VERY_PRIVATE_VALUE", stored)
        self.assertNotIn("999999", stored)
        self.assertEqual(json.loads(stored)["videoSegmentPercent"], 17.5)

    def test_no_telemetry_file_when_token_invalid(self):
        for token in ("../danger", "a" * 31, "A" * 32):
            with self.assertRaises(ValueError):
                observer_module.NumericTelemetry(token, self.root)

    def test_unchanged_zhs_cli_invocation_and_cleanup(self):
        fake_out = io.StringIO()
        observed = []

        def intercept(module_name, *, run_name, alter_sys):
            observed.append((module_name, run_name, list(sys.argv)))
            sys.stdout.write("\rplaying [## ] 33.5%")
            path = self.root / "ZHSDesktop" / f"monitor-zhs-{self.token}.json"
            self.assertTrue(path.exists())
            self.assertEqual(json.loads(path.read_text())["videoSegmentPercent"], 33.5)

        with mock.patch.dict(os.environ, {"LOCALAPPDATA": str(self.root)}), \
                mock.patch.object(sys, "argv", [str(FILE), self.token, "123", "456"]), \
                mock.patch.object(sys, "stdout", fake_out), \
                mock.patch.object(observer_module.runpy, "run_module", side_effect=intercept):
            self.assertEqual(observer_module.main(), 0)
        self.assertEqual(observed, [("zhs.__main__", "__main__",
                                    ["zhs", "play", "-c", "123:456", "--type", "ai"])])
        self.assertFalse((self.root / "ZHSDesktop" / f"monitor-zhs-{self.token}.json").exists())

    def test_original_entrypoint_not_changed(self):
        script = (Path(__file__).parent / "payload" / "Zhidao-Task.cmd").read_text("utf-8")
        self.assertIn('"%ZHS%" play -c "%~2:%~3" --type ai', script)
        self.assertIn('"%PY%" "%ROOT%\\ZHS-ConsoleMonitor.py" "%~4" "%~2" "%~3"', script)
        self.assertIn('exit /b %ERRORLEVEL%', script)


if __name__ == "__main__":
    unittest.main()
