"""Regression tests for strictly read-only Zhidao server diagnostics."""
from __future__ import annotations

import tempfile
import unittest
import json
import contextlib
import io
from pathlib import Path
from unittest.mock import patch

from test_cache_v527 import app


class HttpFailure(Exception):
    def __init__(self, code):
        self.response = type('Response', (), {'status_code': code})()


class FakeSession:
    def __init__(self):
        self.closed = False
    def close(self):
        self.closed = True


class ReadReliabilityTests(unittest.TestCase):
    def test_transient_timeout_retried_once(self):
        calls, naps = [], []
        def operation():
            calls.append(1)
            if len(calls) == 1:
                raise TimeoutError('test only')
            return ['ok']
        self.assertEqual(app.read_with_retry(operation, sleep=naps.append), ['ok'])
        self.assertEqual(len(calls), 2)
        self.assertEqual(naps, [0.3])

    def test_transient_503_once_not_infinite(self):
        count = 0
        def operation():
            nonlocal count
            count += 1
            raise HttpFailure(503)
        with self.assertRaises(HttpFailure):
            app.read_with_retry(operation, sleep=lambda _: None)
        self.assertEqual(count, 2)

    def test_auth_and_rate_limit_not_retried(self):
        for status in (401, 403, 429, 400):
            calls = []
            def operation():
                calls.append(1)
                raise HttpFailure(status)
            with self.subTest(status=status), self.assertRaises(HttpFailure):
                app.read_with_retry(operation, sleep=lambda _: None)
            self.assertEqual(len(calls), 1)

    def test_bad_api_shape_not_retried(self):
        calls = []
        def operation():
            calls.append(1)
            raise app.ResponseShapeError('shape')
        with self.assertRaises(app.ResponseShapeError):
            app.read_with_retry(operation, sleep=lambda _: None)
        self.assertEqual(len(calls), 1)

    def run_doctor(self, *, shared=None, ai=None, exceptions=(None, None)):
        session = FakeSession()
        with tempfile.TemporaryDirectory() as d:
            data = Path(d)
            (data / 'cookies.json').write_text(json.dumps([{'name': 'session', 'value': 'FAKE ONLY'}]))
            def shared_reader(_):
                if exceptions[0] is not None:
                    raise exceptions[0]
                return (shared if shared is not None else [], {})
            def ai_reader(_):
                if exceptions[1] is not None:
                    raise exceptions[1]
                return ai if ai is not None else []
            with patch.object(app, 'DATA', data), \
                 patch.object(app.os, 'chdir'), \
                 patch.object(app, 'load_config_and_session', return_value=(object(),session)), \
                 patch.object(app, 'ZhidaoCourseManager', return_value=object()), \
                 patch.object(app, 'shared_course_list', side_effect=shared_reader), \
                 patch.object(app, 'ai_course_list', side_effect=ai_reader), \
                 patch.object(app.time, 'sleep', return_value=None):
                result = app.doctor_server()
            self.assertTrue(session.closed)
            self.assertEqual(sorted(p.name for p in data.iterdir()), ['cookies.json'])
            return result

    def test_missing_credentials_do_not_reach_server(self):
        with tempfile.TemporaryDirectory() as d, \
             patch.object(app, 'DATA', Path(d)), \
             patch.object(app, 'load_config_and_session') as loader:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(app.doctor_server(), 3)
            loader.assert_not_called()
            self.assertIn('[AUTH]', output.getvalue())

    def test_corrupt_cookie_file_is_not_server_login(self):
        for content in ('', '{broken', '{}', '[]', '[{"name":"x"}]'):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as d, \
                 patch.object(app, 'DATA', Path(d)), \
                 patch.object(app, 'load_config_and_session') as loader:
                (Path(d) / 'cookies.json').write_text(content)
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(app.doctor_server(), 4)
                loader.assert_not_called()
                self.assertIn('[AUTH_LOCAL_INVALID]', output.getvalue())

    def test_local_bootstrap_unavailable_is_not_labeled_expired(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'cookies.json').write_text('[{"name":"x","value":"placeholder"}]')
            with patch.object(app, 'DATA', Path(d)), \
                 patch.object(app.os, 'chdir'), \
                 patch.object(app, 'load_config_and_session', return_value=None):
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(app.doctor_server(), 4)
            self.assertIn('[AUTH_OR_NETWORK]', output.getvalue())
            self.assertNotIn('已过期', output.getvalue())

    def test_all_course_endpoints_fail_does_not_revoke_verified_login(self):
        session = FakeSession()
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / 'cookies.json').write_text('[{"name":"x","value":"placeholder"}]')
            with patch.object(app, 'DATA', Path(d)), \
                 patch.object(app.os, 'chdir'), \
                 patch.object(app, 'load_config_and_session', return_value=(object(),session)), \
                 patch.object(app, 'ZhidaoCourseManager', return_value=object()), \
                 patch.object(app, 'shared_course_list', side_effect=HttpFailure(503)), \
                 patch.object(app, 'ai_course_list', side_effect=HttpFailure(503)), \
                 patch.object(app.time, 'sleep', return_value=None):
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(app.doctor_server(), 6)
        self.assertIn('[SESSION_OK]', output.getvalue())
        self.assertIn('[SERVER_UNCONFIRMED]', output.getvalue())
        self.assertTrue(session.closed)

    def test_server_probe_both_success_even_if_empty(self):
        self.assertEqual(self.run_doctor(), 0)

    def test_server_probe_partial(self):
        self.assertEqual(self.run_doctor(exceptions=(HttpFailure(403), None)), 7)

    def test_server_probe_both_fail(self):
        self.assertEqual(self.run_doctor(exceptions=(HttpFailure(401), app.ResponseShapeError('unknown'))), 6)

    def test_doctor_does_not_require_cookie_content_in_log(self):
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()) as capture:
            self.run_doctor()
        self.assertNotIn('FAKE ONLY',capture.getvalue())
        self.assertIn('SERVER_OK',capture.getvalue())
        self.assertIn('SESSION_OK',capture.getvalue())

    def test_gui_doctor_is_real_read_only_probe(self):
        root = Path(__file__).parent
        cmd = (root/'payload/Zhidao-Task.cmd').read_text('utf-8')
        gui = (root/'payload/Zhidao-GUI.ps1').read_text('utf-8-sig')
        self.assertIn('"%PY%" "%HELPER%" doctor-server', cmd)
        self.assertIn('服务器只读检测通过',gui)
        self.assertIn('6 {',gui)
        self.assertIn('7 {',gui)


if __name__ == '__main__':
    unittest.main(verbosity=2)
