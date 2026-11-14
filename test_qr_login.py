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


def fake_modules(status, *, raise_login=None, qr_writes=True):
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
        self.assertEqual((self.data / "qrcode.png").read_bytes(), b"valid fresh QR bytes")
        self.assertNotIn("SECRET_COOKIE", self.obs.path.read_text())
        self.assertIn("[QR_VERIFIED]", self.out.getvalue())

    def test_cas_rejection_retains_prior_credentials(self):
        self.assertEqual(self.login(AuthStatus.EXPIRED), 7)
        self.assertEqual((self.data / "cookies.json").read_text(), "OLD_ACCOUNT_COOKIE")
        self.assertEqual(json.loads(self.obs.path.read_text())["stage"], "rejected")

    def test_unavailable_saved_but_never_claimed_verified(self):
        self.assertEqual(self.login(AuthStatus.UNAVAILABLE), 4)
        self.assertEqual(json.loads(self.obs.path.read_text())["stage"], "unavailable")
        self.assertNotIn("[QR_VERIFIED]", self.out.getvalue())
        self.assertEqual(json.loads((self.data / "cookies.json").read_text())[0]["name"], "CASLOGC")

    def test_login_error_does_not_leak_sensitive_message_or_replace_cookie(self):
        self.assertEqual(self.login(AuthStatus.OK, raise_login="secret=QR_TOKEN_SHOULD_NOT_LEAK"), 5)
        self.assertEqual((self.data / "cookies.json").read_text(), "OLD_ACCOUNT_COOKIE")
        self.assertNotIn("QR_TOKEN_SHOULD_NOT_LEAK", self.out.getvalue())
        self.assertNotIn("QR_TOKEN_SHOULD_NOT_LEAK", self.obs.path.read_text())

    def test_old_qr_is_removed_even_if_new_image_unavailable(self):
        self.assertEqual(self.login(AuthStatus.EXPIRED, qr_writes=False), 7)
        self.assertFalse((self.data / "qrcode.png").is_file())
        self.assertEqual((self.data / "cookies.json").read_text(), "OLD_ACCOUNT_COOKIE")

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


if __name__ == "__main__":
    unittest.main()
