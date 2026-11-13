"""Static regression tests for the ZHS UI wrapper; no heartbeat is sent."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent

class HeartbeatEntryErrorTests(unittest.TestCase):
    def test_upstream_sender_call_is_unchanged(self):
        new = (ROOT/'payload/Zhidao-Task.cmd').read_text('utf-8')
        call = '"%ZHS%" play -c "%~2:%~3" --type ai'
        self.assertEqual(new.count(call), 1)
        self.assertNotIn('pause', new.lower())
        self.assertNotIn('curl ', new.lower())

    def test_missing_args_fail_before_execution(self):
        text = (ROOT/'payload/Zhidao-Task.cmd').read_text('utf-8')
        self.assertLess(text.index('if "%~2"=="" goto badplayargs'), text.index('"%ZHS%" play '))
        self.assertLess(text.index('if "%~3"=="" goto badplayargs'), text.index('"%ZHS%" play '))
        self.assertIn(':badplayargs',text)
        self.assertIn('exit /b 2',text)

    def test_original_mode_exit_status_is_reported(self):
        gui=(ROOT/'payload/Zhidao-GUI.ps1').read_text('utf-8-sig')
        original=gui[gui.index('function Launch-Original-ZHS'):gui.index('function Start-Selected-Mode')]
        self.assertIn("$script:activeTaskProcess = $proc",original)
        self.assertIn("$script:activeTaskAction = 'play-ai'",original)
        handler=gui[gui.index('function Check-TaskExit'):gui.index('function Get-SessionFingerprint')]
        self.assertIn("$action -eq 'play-ai'", handler)
        self.assertIn('不会自动重试或补发心跳',handler)
        self.assertIn('不代表服务器已经计入学习记录',handler)

if __name__ == '__main__': unittest.main()
