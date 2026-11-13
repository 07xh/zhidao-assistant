"""Offline diagnostics contract: no credentials in logs or return objects."""
from __future__ import annotations

import contextlib
import io
import unittest
from unittest.mock import patch

from test_cache_v527 import app
import zhidao_diagnostics as diagnostic_module


class HttpFailure(Exception):
    def __init__(self, status, raw):
        super().__init__(raw)
        self.response = type("Response", (), {"status_code": status})()


class ReadOnlyDiagnosticsTests(unittest.TestCase):
    def test_compatibility_exports_share_one_implementation(self):
        self.assertIs(app.ResponseShapeError, diagnostic_module.ResponseShapeError)
        self.assertIs(app.diagnose, diagnostic_module.diagnose)
        self.assertIs(app.diagnostic, diagnostic_module.diagnostic)
        self.assertIs(app.emit_failure, diagnostic_module.emit_failure)

    def test_safe_classifications(self):
        cases = (
            (HttpFailure(401, "credential=never-log"), "AUTH"),
            (HttpFailure(403, "secret"), "AUTH"),
            (HttpFailure(429, "secret"), "SERVICE"),
            (HttpFailure(503, "secret"), "SERVICE"),
            (TimeoutError("secret"), "TIMEOUT"),
            (ConnectionError("secret"), "NETWORK"),
            (app.ResponseShapeError("secret"), "API_SHAPE"),
            (HttpFailure(400, "secret"), "HTTP_ERROR"),
            (RuntimeError("secret"), "UNKNOWN"),
        )
        for error, expected in cases:
            with self.subTest(code=expected):
                self.assertEqual(app.diagnose(error)[0], expected)

    def test_emission_does_not_leak_raw_exception(self):
        secret = "fake-password-and-cookie-must-never-be-reported"
        error = HttpFailure(503, secret)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            result = app.emit_failure("AI", error)
        self.assertEqual(result["code"], "SERVICE")
        self.assertNotIn(secret, output.getvalue())
        self.assertNotIn(secret, str(result))
        self.assertIn("[SERVICE]", output.getvalue())

    def test_no_remote_or_platform_dependency_imports(self):
        # Pure diagnostics can be independently imported without SDK sessions.
        with patch.object(diagnostic_module.socket, "getaddrinfo", side_effect=AssertionError("network not allowed")):
            self.assertEqual(diagnostic_module.diagnose(TimeoutError())[0], "TIMEOUT")


if __name__ == "__main__":
    unittest.main()
