"""Hotfix5 regression checks: passive diagnostics only."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent

class ResearchGuardrails(unittest.TestCase):
    def test_monotonic_time_and_timer_throttle(self):
        js = (ROOT/'payload/Official-MediaController.js').read_text()
        self.assertIn('function monotonicNow()', js)
        self.assertIn("state = 'sampling-gap'", js)
        self.assertIn("state = 'visibility-changed'", js)
        self.assertIn('elapsed * expectedRate * 1.5 + 2', js)

    def test_official_controller_does_not_send_api_heartbeat(self):
        js = (ROOT/'payload/Official-MediaController.js').read_text()
        for forbidden in ('fetch(', 'XMLHttpRequest', '/video-log/heartbeat/', '/saveVideoProgress'):
            self.assertNotIn(forbidden, js)

    def test_gui_understands_new_diagnostic_states(self):
        ps = (ROOT/'payload/Official-Player.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("'sampling-gap'", ps)
        self.assertIn("'visibility-changed'", ps)
        self.assertIn('服务器学习进度需单独核验', ps)

if __name__ == '__main__':
    unittest.main(verbosity=2)
