"""Read-only UI contract tests for the existing Windows WPF front end.

These checks do not launch Windows, do not log in, and do not contact Zhidao.
WPF XamlReader.Parse and live progress rendering are also covered by
test_heartbeat_monitor_wpf.ps1 in the Windows CI job.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent
XAML_FILE = ROOT / "payload" / "Zhidao-UI.xaml"
GUI_SCRIPT = ROOT / "payload" / "Zhidao-GUI.ps1"
XAML_NS = "{http://schemas.microsoft.com/winfx/2006/xaml}"
WPF_NS = "{http://schemas.microsoft.com/winfx/2006/xaml/presentation}"

class WpfVisualContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.xml_text = XAML_FILE.read_text(encoding="utf-8-sig")
        cls.gui_text = GUI_SCRIPT.read_text(encoding="utf-8-sig")
        cls.root = ET.fromstring(cls.xml_text)
        cls.named = {
            e.attrib[XAML_NS + "Name"]: e
            for e in cls.root.iter()
            if XAML_NS + "Name" in e.attrib
        }

    def test_xaml_well_formed_and_still_a_window(self):
        self.assertEqual(self.root.tag, WPF_NS + "Window")
        self.assertGreaterEqual(int(self.root.attrib["MinWidth"]), 640)

    def test_event_handlers_only_reference_existing_controls(self):
        names = set(re.findall(r"Control\s*'([^']+)'", self.gui_text))
        self.assertGreater(len(names), 25)
        missing = names - self.named.keys()
        self.assertFalse(missing, f"GUI handler refers to missing XAML ids: {missing}")

    def test_critical_existing_action_controls_remain(self):
        required = {
            "NavHome", "NavDetail", "NavSettings",
            "PageHome", "PageDetail", "PageSettings",
            "BtnSyncCourses", "BtnSyncProgress", "BtnInputCookies",
            "BtnLogin", "BtnImportCookies", "BtnQR", "BtnSignOut",
            "BtnClearData", "BtnClearWebLogin", "BtnMonitorToggle",
            "BtnOpenLearning", "BtnVerifyOne", "PlaybackModeSelector",
            "HeartbeatTaskLabel", "HeartbeatCommsLabel",
            "HeartbeatVerifyLabel", "HeartbeatServerProgressBar",
            "HeartbeatLocalProgressBar", "HeartbeatZhsProgressBar",
            "HeartbeatEventsPanel",
        }
        self.assertFalse(required - self.named.keys())

    def test_local_and_server_progress_stay_separate(self):
        self.assertIsNot(self.named["HeartbeatServerProgressBar"],
                         self.named["HeartbeatLocalProgressBar"])
        self.assertIn("仅来自原版控制台", self.xml_text)
        self.assertIn("服务器", self.xml_text)

    def test_adaptive_course_cards_and_login_controls(self):
        self.assertEqual(self.named["HomeCourseCards"].tag, WPF_NS + "WrapPanel")
        for name in ("LoginStateDot", "LoginGuideText", "BtnLoginShortcut",
                     "BtnThemeToggle", "ThemeModeText", "SidebarBrandText"):
            self.assertIn(name, self.named)
        for filename in ("UiAppearance.ps1", "UiCourseCards.ps1"):
            self.assertTrue((ROOT / "payload" / filename).is_file())
        self.assertIn("Update-UiLayout", self.gui_text)
        self.assertIn("Update-LoginPresentation", self.gui_text)

    def test_all_dynamic_appearance_resources_resolve(self):
        declared = {
            e.attrib[XAML_NS + "Key"]
            for e in self.root.iter()
            if XAML_NS + "Key" in e.attrib
        }
        used = set(re.findall(r"\{DynamicResource (Ui[A-Za-z]+_[A-Fa-f0-9]{6})\}", self.xml_text))
        self.assertGreater(len(used), 40)
        self.assertFalse(used - declared)

    def test_buttons_and_cards_have_shared_styles(self):
        resources = {
            e.attrib.get(XAML_NS + "Key")
            for e in self.root.iter()
            if XAML_NS + "Key" in e.attrib
        }
        for name in ("NavButton", "PrimaryButton", "SecondaryButton",
                     "DangerButton", "CardStyle", "SectionTitle"):
            self.assertIn(name, resources)
        self.assertIn('<Setter Property="CornerRadius" Value="18"/>', self.xml_text)
        self.assertIn('Content="扫码登录"', self.xml_text)

if __name__ == "__main__":
    unittest.main()
