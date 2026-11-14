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
        self.assertIn("扫码和 CAS 登录认证成功。正在核对本人课程接口状态。", block)
        self.assertIn("认证服务器暂不可用", block)
        self.assertIn("旧登录凭证保留", block)
        helper = (Path(__file__).parent / "payload" / "ZHS-QRLogin.py").read_text("utf-8")
        self.assertIn("verify_session(session)", helper)
        self.assertIn("save_cookies_atomic(destination, session.cookies)", helper)
        self.assertIn("if status == SessionStatus.EXPIRED:", helper)
        self.assertNotIn("登录成功（退出码 0）", block)

    def test_home_login_label_is_no_longer_frozen(self):
        self.assertNotIn("存在本地凭证 · 未校验' } else", GUI)
        self.assertIn("    Update-LoginState\n", GUI)
        self.assertIn(". (Join-Path $script:root 'SessionState.ps1')", GUI)
        self.assertNotIn("function Get-CookieDigest {", GUI)
        self.assertNotIn("function Update-LoginState {", GUI)


    def test_direct_cookie_text_login_never_logs_or_echoes_secret(self):
        import_xml = (Path(__file__).parent / "payload" / "Zhidao-UI.xaml").read_text("utf-8-sig")
        cookie_module = (Path(__file__).parent / "payload" / "CookieImport.ps1").read_text("utf-8-sig")
        self.assertIn('x:Name="BtnInputCookies"', import_xml)
        self.assertIn("function Import-CookiesFromTextDialog {", GUI)
        self.assertIn("New-Object System.Windows.Controls.PasswordBox", GUI)
        self.assertIn("$secret.Clear()", GUI)
        self.assertIn("Convert-ZhidaoCookieText $secret.Password", GUI)
        self.assertIn("Submit-ZhidaoCookieImport $json", GUI)
        self.assertIn("function Convert-ZhidaoCookieText", cookie_module)
        self.assertIn("domain = '.zhihuishu.com'", cookie_module)
        self.assertIn("return Convert-ZhidaoCookieJson", cookie_module)
        self.assertIn("Start-Task 'doctor'", GUI)



if __name__ == "__main__":
    unittest.main()
