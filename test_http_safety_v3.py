"""Offline tests for conservative HTTP reliability patch, no network access."""
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import unquote
import httpx

from apply_http_safety_v3 import FILE, FIXES, SourceMismatch, run, transform

# Minimal syntactically valid module containing exact v0.1.5 method anchors.
# Do not mistake this for the complete upstream repository.
SOURCE = '''import json
from urllib.parse import unquote
import httpx

def list_to_cookies(value):
    cookies = httpx.Cookies()
    for entry in value:
        cookies.set(entry["name"], entry["value"])
    return cookies

class HttpClient:
    def __init__(self):
        self._client = None
        self._cookies = httpx.Cookies()
        self._uuid = None

    @property
    def cookies(self):
        return self._cookies

    @cookies.setter
    def cookies(self, value):
        if isinstance(value, httpx.Cookies):
            self._cookies = value
        elif isinstance(value, list):
            self._cookies = list_to_cookies(value)
        elif isinstance(value, dict):
            new_cookies = httpx.Cookies()
            for k, v in value.items():
                new_cookies.set(k, str(v))
            self._cookies = new_cookies

        self.parse_uuid()

        if self._client is not None:
            self._client.cookies = self._cookies

    def parse_uuid(self):
        caslogc = self._cookies.get("CASLOGC")
        if caslogc:
            try:
                decoded = unquote(caslogc)
                data = json.loads(decoded)
                self._uuid = data.get("uuid")
            except (json.JSONDecodeError, TypeError):
                self._uuid = None
        else:
            self._uuid = None

        if self._uuid:
            self._cookies.set(f"exitRecod_{self._uuid}", "2", domain="zhihuishu.com")

    def api_query(self, resp):
        resp.raise_for_status()
        result: dict[str, Any] = resp.json()
        return result

    def close(self):
        if self._client:
            self._client.close()
            self._client = None
'''

class HTTPPatchTest(unittest.TestCase):
    def setUp(self):
        out, statuses = transform(SOURCE)
        self.patched = out
        self.cls = self.compile_class(out)
        self.assertEqual(len(statuses), len(FIXES))

    @staticmethod
    def compile_class(code):
        scope = {}
        exec(compile(code, '<isolated-http-fixture>', 'exec'), scope)
        return scope['HttpClient']

    def test_cookie_type_rejected_without_mutation(self):
        cli = self.cls()
        cli.cookies = {'k': 'v'}
        before = cli.cookies.get('k')
        with self.assertRaises(TypeError):
            cli.cookies = object()
        self.assertEqual(cli.cookies.get('k'), before)

    def test_caslogc_array_string_integer_null_handled(self):
        cli = self.cls()
        for val in ('[]', '"abc"', '123', 'null', '{"uuid": 42}', '{"uuid": null}', '{"uuid": {}}'):
            with self.subTest(val=val):
                cli.cookies = {'CASLOGC': val}
                self.assertIsNone(cli._uuid)

    def test_valid_cookie_uuid_unaffected(self):
        cli = self.cls()
        cli.cookies = {'CASLOGC': '{"uuid":"abc"}'}
        self.assertEqual(cli._uuid, 'abc')
        self.assertEqual(cli.cookies.get('exitRecod_abc'), '2')

    def test_invalid_json_is_error_without_leaking_body(self):
        cli = self.cls()
        response = httpx.Response(200, content=b'not a json secret-content', request=httpx.Request('GET', 'https://example.invalid'))
        with self.assertRaises(ValueError) as ctx:
            cli.api_query(response)
        self.assertNotIn('secret-content', str(ctx.exception))

    def test_json_array_rejected(self):
        cli = self.cls()
        response = httpx.Response(200, json=[1, 2], request=httpx.Request('GET', 'https://example.invalid'))
        with self.assertRaisesRegex(ValueError, 'JSON'):
            cli.api_query(response)

    def test_valid_json_unchanged(self):
        cli = self.cls()
        response = httpx.Response(200, json={'code': 0}, request=httpx.Request('GET', 'https://example.invalid'))
        self.assertEqual(cli.api_query(response), {'code': 0})

    def test_failed_close_clears_reference(self):
        cli = self.cls()
        class Broken:
            def close(self):
                raise OSError('close failed')
        cli._client = Broken()
        with self.assertRaises(OSError):
            cli.close()
        self.assertIsNone(cli._client)

    def test_idempotent(self):
        out, notes = transform(self.patched)
        self.assertEqual(out, self.patched)
        self.assertTrue(all(note.startswith('ALREADY') for note in notes))

    def test_mismatch_fails(self):
        with self.assertRaises(SourceMismatch):
            transform('# wrong version\n')

    def test_dry_run_and_apply_backup(self):
        with tempfile.TemporaryDirectory() as td:
            file = Path(td) / FILE
            file.parent.mkdir(parents=True)
            file.write_text(SOURCE, encoding='utf-8')
            before = file.read_bytes()
            run(Path(td), apply=False)
            self.assertEqual(file.read_bytes(), before)
            run(Path(td), apply=True)
            self.assertEqual(file.read_text(), self.patched)
            self.assertEqual(file.with_suffix('.py.before-v3.bak').read_bytes(), before)
            run(Path(td), apply=True)  # no more writes

    def test_syntax_guard_keeps_original(self):
        with tempfile.TemporaryDirectory() as td:
            file = Path(td) / FILE
            file.parent.mkdir(parents=True)
            file.write_text(SOURCE + '\ndef incomplete(\n', encoding='utf-8')
            before = file.read_bytes()
            with self.assertRaises(SyntaxError):
                run(Path(td), apply=True)
            self.assertEqual(file.read_bytes(), before)

    def test_symlink_refused(self):
        with tempfile.TemporaryDirectory() as td:
            file = Path(td) / FILE
            file.parent.mkdir(parents=True)
            outside = Path(td) / 'external.py'
            outside.write_text(SOURCE, encoding='utf-8')
            file.symlink_to(outside)
            with self.assertRaises(SourceMismatch):
                run(Path(td), apply=True)

    def test_crlf_refused(self):
        with tempfile.TemporaryDirectory() as td:
            file = Path(td) / FILE
            file.parent.mkdir(parents=True)
            file.write_bytes(SOURCE.replace('\n', '\r\n').encode('utf-8'))
            with self.assertRaises(SourceMismatch):
                run(Path(td), apply=False)

    def test_no_heartbeat_changes(self):
        texts = '\n'.join(f.old + '\n' + f.new for f in FIXES)
        for forbidden in ('lastWatchTime', 'studyTotalTime', '_report_progress_v2', 'time.sleep(', 'rate_limit', 'Retry-After'):
            self.assertNotIn(forbidden, texts)

if __name__ == '__main__':
    unittest.main()
