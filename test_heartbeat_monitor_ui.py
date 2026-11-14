"""Offline UI integration contracts; no heartbeat traffic or platform login."""
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).parent
GUI = (ROOT / "payload/Zhidao-GUI.ps1").read_text("utf-8-sig")
VIEW = (ROOT / "payload/HeartbeatView.ps1").read_text("utf-8-sig")
STATE = (ROOT / "payload/HeartbeatMonitor.ps1").read_text("utf-8-sig")
PLAYER = (ROOT / "payload/Official-Player.ps1").read_text("utf-8-sig")
MANIFEST = (ROOT / "payload/install-files.json").read_text("utf-8")


class HeartbeatMonitorUIContracts(unittest.TestCase):
    def test_monitor_is_packaged_and_wired(self):
        self.assertIn('"HeartbeatMonitor.ps1"', MANIFEST)
        self.assertIn('"HeartbeatView.ps1"', MANIFEST)
        self.assertIn(". (Join-Path $script:root 'HeartbeatMonitor.ps1')", GUI)
        self.assertIn(". (Join-Path $script:root 'HeartbeatView.ps1')", GUI)
        self.assertIn("Initialize-HeartbeatMonitor", GUI)
        self.assertIn("Update-HeartbeatPanel", GUI)
        self.assertIn("Toggle-HeartbeatPanel", GUI)

    def test_xaml_names_and_scroll_ensure_monitor_is_accessible(self):
        tree = ET.parse(ROOT / "payload/Zhidao-UI.xaml")
        ns = "{http://schemas.microsoft.com/winfx/2006/xaml/presentation}"
        xname = "{http://schemas.microsoft.com/winfx/2006/xaml}Name"
        all_nodes = list(tree.iter())
        names = {node.attrib.get(xname) for node in all_nodes}
        expected = {
            "HeartbeatTaskLabel", "HeartbeatCommsLabel", "HeartbeatVerifyLabel",
            "HeartbeatServerProgressBar", "HeartbeatProgressLabel",
            "HeartbeatProgressHint", "HeartbeatLocalPlaybackText",
            "HeartbeatLocalProgressBar", "HeartbeatEventsPanel",
            "HeartbeatExpandedPanel", "BtnHeartbeatExpand", "VideoListPanel",
        }
        self.assertTrue(expected <= names, expected - names)
        detail = next(n for n in all_nodes if n.attrib.get(xname) == "PageDetail")
        self.assertTrue(any(node.tag == ns + "ScrollViewer" for node in detail.iter()))
        monitor = next(n for n in all_nodes if n.attrib.get(xname) == "HeartbeatExpandedPanel")
        self.assertEqual(monitor.attrib.get("Visibility"), "Collapsed")

    def test_events_are_course_scoped_and_allowlisted(self):
        self.assertIn("Get-HeartbeatCourseKey", STATE)
        self.assertIn("Sync-HeartbeatMonitorSession", STATE)
        self.assertIn("fingerprint -cne $current", STATE)
        self.assertIn("Select-Object -Last 48", STATE)
        self.assertIn("if (-not $messages.ContainsKey($code))", STATE)
        self.assertNotIn("Get-Content -LiteralPath $script:verifyErrorPath", VIEW)
        self.assertNotIn("send_heartbeat(", VIEW + STATE)

    def test_player_reports_only_observed_local_media_state(self):
        self.assertIn("Write-OfficialPlaybackObservation $event $position $duration", PLAYER)
        self.assertIn("if ($source.Scheme -ne 'https'", PLAYER)
        self.assertIn("Get-HeartbeatLocalSnapshot", VIEW)
        self.assertIn("ageSeconds -gt 18", STATE)
        self.assertIn("MonitorToken", PLAYER)
        self.assertIn("playerSessionFingerprint -ceq $fp", VIEW)
        self.assertIn("服务器已返回记录", VIEW)
        self.assertIn("不是官方课程总进度", VIEW)
        self.assertNotIn("heart_data", VIEW + STATE)

    def test_original_zhs_task_is_not_replaced(self):
        cmd = (ROOT / "payload/Zhidao-Task.cmd").read_text("utf-8")
        self.assertEqual(cmd.count('"\%ZHS\%" play -c "\%~2:\%~3" --type ai'.replace("\\", "")), 0)
        self.assertIn('"\%ZHS\%" play -c "\%~2:\%~3" --type ai'.replace("\\", ""), cmd)


if __name__ == "__main__":
    unittest.main()
