"""Guardrails for Windows login state display and diagnosis flow.

These checks inspect PowerShell source; actual WPF behavior still requires
Windows installation acceptance with a real account.
"""
import unittest
from pathlib import Path

GUI = (Path(__file__).parent / "payload" / "Zhidao-GUI.ps1").read_text("utf-8-sig")
SESSION = (Path(__file__).parent / "payload" / "SessionState.ps1").read_text("utf-8-sig")
ADAPTER = (Path(__file__).parent / "payload" / "zhidao_only.py").read_text("utf-8")


class LoginDisplayTests(unittest.TestCase):
    def test_cookie_bound_status_cannot_survive_session_rotation(self):
        block = SESSION.split("function Update-LoginState {", 1)[1]
        self.assertIn("Get-CookieDigest", block)
        self.assertIn("$script:loginProbeCookieDigest -ne $digest", block)
        self.assertIn("$script:loginProbeState = ''", block)
        self.assertIn("服务端登录已验证", block)

    def test_course_api_error_does_not_mean_login_expired(self):
        block = GUI.split("} elseif ($action -eq 'doctor') {", 1)[1]
        self.assertIn("6 { 'course-failed' }", block)
        self.assertIn("7 { 'partial' }", block)
        self.assertIn("8 { 'local-invalid' }", block)
        self.assertIn("服务端登录已验证，但两类课程接口都失败", block)
        self.assertIn("[SESSION_OK]", ADAPTER)

    def test_login_success_runs_real_diagnosis_not_success_by_exit_code(self):
        block = GUI.split("function Check-TaskExit {", 1)[1].split("function Get-SessionFingerprint", 1)[0]
        self.assertIn("$autoCheckAfterLogin = ($code -eq 0)", block)
        self.assertIn("if ($autoCheckAfterLogin) { Start-Task 'doctor' }", block)
        self.assertIn("正在自动检测服务端登录状态", block)
        self.assertNotIn("登录成功（退出码 0）", block)

    def test_home_login_label_is_no_longer_frozen(self):
        self.assertNotIn("存在本地凭证 · 未校验' } else", GUI)
        self.assertIn("    Update-LoginState\n", GUI)
        self.assertIn(". (Join-Path $script:root 'SessionState.ps1')", GUI)
        self.assertNotIn("function Get-CookieDigest {", GUI)
        self.assertNotIn("function Update-LoginState {", GUI)


if __name__ == "__main__":
    unittest.main()
