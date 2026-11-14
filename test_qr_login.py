"""Offline QR login contract tests with an isolated fake ZHS API (no network)."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch


HERE = Path(__file__).parent
SPEC = importlib.util.spec_from_file_location("qr_login", HERE / "payload" / "ZHS-QRLogin.py")
assert SPEC is not None and SPEC.loader is not None
qr = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(qr)


class AuthStatus:
    OK = "ok"
    EXPIRED = "expired"
    UNAVAILABLE = "unavailable"


class FakeSession:
    def __init__(self):
        self.cookies = [{"name": "CASLOGC", "value": "SECRET_COOKIE", "domain": ".zhihuishu.com", "path": "/"}]


class FakeLoginResult:
    success = True
    cookies = True


def fake_modules(status, *, raise_login=None, qr_writes=True, refresh_after_scan=False):
    auth = types.ModuleType("zhs.api.session_auth")
    auth.SessionStatus = AuthStatus
    auth.verify_session = lambda session: status
    login = types.ModuleType("zhs.login")
    cookie = types.ModuleType("zhs.utils.cookie")

    class Manager:
        def __init__(self, session, config):
            pass

        def login_with_qr(self, qr_callback, on_scanned, image_path):
            if raise_login is not None:
                raise ValueError(raise_login)
            if qr_writes:
                Path(image_path).write_bytes(b"valid fresh QR bytes")
            qr_callback(b"valid fresh QR bytes")
            on_scanned()
            # The original login poller does not need the image after scan.
            # Enforce immediate deletion here, before CAS verification begins.
            if Path(image_path).exists():
                raise AssertionError("QR PNG remained on disk after on_scanned")
            if refresh_after_scan:
                # Expired QR may be replaced with another image during the
                # same upstream login attempt; must remain displayable.
                Path(image_path).write_bytes(b"new refreshed QR")
                qr_callback(b"new refreshed QR")
            return FakeLoginResult()

    login.LoginManager = Manager
    cookie.cookies_to_list = lambda cookies: cookies
    return {"zhs.api.session_auth": auth, "zhs.login": login, "zhs.utils.cookie": cookie}


class QrLoginTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = self.root / ".zhs"
        self.data.mkdir()
        self.obs = qr.LoginObservation("e" * 32, self.root / "app")
        self.session = FakeSession()
        (self.data / "cookies.json").write_text("OLD_ACCOUNT_COOKIE", encoding="utf-8")
        (self.data / "qrcode.png").write_bytes(b"EXPIRED_OLD_QR")
        self.out = io.StringIO()

    def login(self, status, **kwargs):
        with patch.dict(sys.modules, fake_modules(status, **kwargs)), contextlib.redirect_stdout(self.out):
            return qr.login_with_qr(None, self.session, self.obs, self.data)

    def test_verified_qr_requires_real_server_ok(self):
        self.assertEqual(self.login(AuthStatus.OK), 0)
        self.assertEqual(json.loads((self.data / "cookies.json").read_text())[0]["value"], "SECRET_COOKIE")
        self.assertEqual(json.loads(self.obs.path.read_text())["stage"], "verified")
        self.assertFalse((self.data / "qrcode.png").exists(), "One-use QR image must be deleted after success")
        self.assertNotIn("SECRET_COOKIE", self.obs.path.read_text())
        self.assertIn("[QR_VERIFIED]", self.out.getvalue())

    def test_cas_rejection_retains_prior_credentials(self):
        self.assertEqual(self.login(AuthStatus.EXPIRED), 7)
        self.assertEqual((self.data / "cookies.json").read_text(), "OLD_ACCOUNT_COOKIE")
        self.assertEqual(json.loads(self.obs.path.read_text())["stage"], "rejected")
        self.assertFalse((self.data / "qrcode.png").exists(), "Failed CAS must also erase QR")

    def test_unavailable_saved_but_never_claimed_verified(self):
        self.assertEqual(self.login(AuthStatus.UNAVAILABLE), 4)
        self.assertEqual(json.loads(self.obs.path.read_text())["stage"], "unavailable")
        self.assertFalse((self.data / "qrcode.png").exists(), "Unavailable CAS must erase QR")
        self.assertNotIn("[QR_VERIFIED]", self.out.getvalue())
        self.assertEqual(json.loads((self.data / "cookies.json").read_text())[0]["name"], "CASLOGC")

    def test_login_error_does_not_leak_sensitive_message_or_replace_cookie(self):
        self.assertEqual(self.login(AuthStatus.OK, raise_login="secret=QR_TOKEN_SHOULD_NOT_LEAK"), 5)
        self.assertEqual((self.data / "cookies.json").read_text(), "OLD_ACCOUNT_COOKIE")
        self.assertFalse((self.data / "qrcode.png").exists(), "QR must be erased on error")
        self.assertNotIn("QR_TOKEN_SHOULD_NOT_LEAK", self.out.getvalue())
        self.assertNotIn("QR_TOKEN_SHOULD_NOT_LEAK", self.obs.path.read_text())

    def test_old_qr_is_removed_even_if_new_image_unavailable(self):
        self.assertEqual(self.login(AuthStatus.EXPIRED, qr_writes=False), 7)
        self.assertFalse((self.data / "qrcode.png").is_file())
        self.assertEqual((self.data / "cookies.json").read_text(), "OLD_ACCOUNT_COOKIE")

    def test_qr_deleted_on_cancellation_without_erasing_other_login_files(self):
        (self.data / "config.toml").write_text("preserve=true", encoding="utf-8")
        self.assertEqual(self.login(AuthStatus.OK, raise_login="用户取消登录"), 9)
        self.assertFalse((self.data / "qrcode.png").exists())
        self.assertEqual((self.data / "cookies.json").read_text(), "OLD_ACCOUNT_COOKIE")
        self.assertEqual((self.data / "config.toml").read_text(), "preserve=true")

    def test_cleanup_retries_are_only_exact_qr_filename(self):
        self.assertEqual(self.login(AuthStatus.OK), 0)
        self.assertEqual(self.login(AuthStatus.EXPIRED), 7)
        self.assertFalse((self.data / "qrcode.png").exists())
        self.assertTrue((self.data / "cookies.json").exists())

    def test_qr_is_recreated_if_original_poller_refreshes_after_scan(self):
        self.assertEqual(self.login(AuthStatus.OK, refresh_after_scan=True), 0)
        self.assertEqual(json.loads(self.obs.path.read_text())["stage"], "verified")
        self.assertFalse((self.data / "qrcode.png").exists())
        self.assertIn("[QR_READY]", self.out.getvalue())
        self.assertIn("[QR_SCANNED]", self.out.getvalue())

    def test_gui_exit_during_active_qr_login_requires_process_state(self):
        gui = (HERE / "payload" / "Zhidao-GUI.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("if ($script:activeTaskAction -eq 'login' -and $null -ne $script:activeTaskProcess)", gui)
        self.assertIn("$script:activeTaskProcess.HasExited", gui)
        self.assertIn("if (-not (Clear-ZhidaoQrImage $script:qrPath))", gui)

    def test_unsafe_telemetry_path_rejected(self):
        for token in ("../outside", "Z" * 32, "e" * 33):
            with self.assertRaises(ValueError):
                qr.LoginObservation(token, self.root)
        with self.assertRaises(ValueError):
            self.obs.publish("SERVER_AUTH_OK_EVEN_IF_FAILED")

    def test_cmd_and_gui_bind_same_fresh_qr_token(self):
        task = (HERE / "payload" / "Zhidao-Task.cmd").read_text(encoding="utf-8")
        gui = (HERE / "payload" / "Zhidao-GUI.ps1").read_text(encoding="utf-8-sig")
        ui = (HERE / "payload" / "Zhidao-UI.xaml").read_text(encoding="utf-8-sig")
        self.assertIn('"%PY%" "%ROOT%\\ZHS-QRLogin.py" "%~2"', task)
        self.assertIn("$launchArgs = @('login', $script:activeQrToken)", gui)
        self.assertIn("Get-ZhidaoQrObservation $script:activeQrToken", gui)
        self.assertIn("Show-ZhidaoQrDialog", gui)
        self.assertIn('x:Name="QrLoginStateText"', ui)
        self.assertNotIn("Start-Process -FilePath $script:qrPath", gui)
        self.assertIn("Clear-ZhidaoQrImage $script:qrPath", gui)
        self.assertIn("if ($script:activeTaskAction -eq 'login')", gui)


if __name__ == "__main__":
    unittest.main()
