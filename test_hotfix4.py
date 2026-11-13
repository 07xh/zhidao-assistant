"""Hotfix4 source-only contracts; platform heartbeat endpoints must remain untouched."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent

class Hotfix4Checks(unittest.TestCase):
    def test_passive_heartbeat_is_observation_not_platform_upload(self):
        js = (ROOT/'payload/Official-MediaController.js').read_text()
        self.assertIn('const MONITOR_INTERVAL_MS = 12000', js)
        self.assertIn('monitorNow(force = false)', js)
        self.assertIn("kind: 'playback-health'", js)
        self.assertNotIn('fetch(', js)
        self.assertNotIn('XMLHttpRequest', js)
        self.assertNotIn('video-log/heartbeat', js)
        self.assertNotIn('playbackRate = 16', js)

    def test_player_reports_only_local_status_and_never_server_confirmation(self):
        player = (ROOT/'payload/Official-Player.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('查看本地播放状态', player)
        self.assertIn("'playback-health'", player)
        self.assertIn('服务器学习进度需单独核验', player)
        self.assertIn('c.monitorNow(true)', player)

    def test_connection_diagnosis_does_not_claim_server_login(self):
        adapter = (ROOT/'payload/zhidao_only.py').read_text()
        gui = (ROOT/'payload/Zhidao-GUI.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('[READY_LOCAL]', adapter)
        self.assertIn('未验证服务器是否认可登录', adapter)
        self.assertIn('服务器只读检测通过', gui)
        self.assertIn('[SERVER_OK]', adapter)
        self.assertIn('doctor-server', (ROOT/'payload/Zhidao-Task.cmd').read_text())

if __name__ == '__main__':
    unittest.main(verbosity=2)
