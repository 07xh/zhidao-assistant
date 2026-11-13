"""Offline regressions for truthful read-only sync results and stale-progress UI."""
from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from test_cache_v527 import app


class FakeSession:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True


class SyncIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.original_data = app.DATA
        app.DATA = Path(self.tempdir.name)
        self.addCleanup(lambda: setattr(app, 'DATA', self.original_data))
        (app.DATA / 'cookies.json').write_text('LOCAL_FAKE_LOGIN', encoding='utf-8')
        self.fp = app.session_fingerprint(create=True)

    def sync(self, mode='courses', shared=None, ai=None, ai_progress=None):
        session = FakeSession()
        with patch.object(app.os, 'chdir'), \
             patch.object(app, 'load_config_and_session', return_value=(object(), session)), \
             patch.object(app, 'ZhidaoCourseManager', return_value=object()), \
             patch.object(app, 'AiCourseManager', return_value=object()), \
             patch.object(app, 'shared_course_list', return_value=(shared or [], {})), \
             patch.object(app, 'ai_course_list', return_value=ai or []), \
             patch.object(app, 'ai_progress', side_effect=ai_progress):
            with contextlib.redirect_stdout(io.StringIO()) as captured:
                code = app.main(mode)
        self.assertTrue(session.closed)
        self.assertNotIn('LOCAL_FAKE_LOGIN', captured.getvalue())
        return code, captured.getvalue()

    def test_first_confirmed_empty_is_valid(self):
        code, output = self.sync()
        self.assertEqual(code, 0)
        cache = app.read_cache(app.COURSES)
        self.assertEqual(cache['courses'], [])
        self.assertEqual(cache['unconfirmedEmptySources'], [])
        self.assertNotIn('EMPTY_UNCONFIRMED', output)

    def test_cached_course_and_empty_response_must_not_report_success(self):
        old = {'courseType': 'ai', 'courseId': 70, 'classId': 4, 'name': 'Prior course'}
        app.update_cache(app.COURSES, lambda _: {'courses': [old]}, self.fp)
        code, output = self.sync()
        self.assertEqual(code, 1)
        cache = app.read_cache(app.COURSES)
        self.assertEqual(cache['unconfirmedEmptySources'], ['ai'])
        self.assertEqual(len(cache['courses']), 1)
        self.assertTrue(cache['courses'][0]['stale'])
        self.assertIn('[EMPTY_UNCONFIRMED]', output)
        self.assertIn('[历史缓存，待确认]', output)

    def test_partial_sources_preserve_old_and_display_new(self):
        old = {'courseType': 'ai', 'courseId': 70, 'classId': 4, 'name': 'Old'}
        current = {'courseType': 'shared', 'courseId': 9, 'name': 'New', 'recruitAndCourseId': 'signed-route'}
        app.update_cache(app.COURSES, lambda _: {'courses': [old]}, self.fp)
        code, _ = self.sync(shared=[current])
        self.assertEqual(code, 1)
        cache = app.read_cache(app.COURSES)
        self.assertEqual(len(cache['courses']), 2)
        self.assertTrue(next(c for c in cache['courses'] if c['courseType'] == 'ai')['stale'])
        self.assertFalse(next(c for c in cache['courses'] if c['courseType'] == 'shared').get('stale', False))

    def test_progress_records_incomplete_if_course_list_unconfirmed(self):
        old = {'courseType': 'ai', 'courseId': 70, 'classId': 4, 'name': 'Old'}
        app.update_cache(app.COURSES, lambda _: {'courses': [old]}, self.fp)
        detail = {**old, 'stale': False, 'knowledgePointCount': 1, 'fullProgressPoints': 0,
                  'knowledgePoints': [], 'lastVerifiedAt': '2026-11-12T00:00:00+00:00'}
        code, _ = self.sync('progress', ai_progress=lambda _manager, _row: detail)
        self.assertEqual(code, 1)
        progress = app.read_cache(app.PROGRESS)
        self.assertTrue(progress['incomplete'])
        self.assertEqual(progress['unconfirmedEmptySources'], ['ai'])
        self.assertEqual(progress['courses'][0]['name'], 'Old')

    def test_malformed_ai_envelope_fails_closed(self):
        session = SimpleNamespace(
            urls=SimpleNamespace(base='https://example.invalid'),
            crypto=SimpleNamespace(key_bytes=lambda _key: b'fake'),
            zhidao_query=lambda *_args, **_kw: [],
        )
        with self.assertRaises(app.ResponseShapeError):
            app.ai_course_list(session)

    def test_malformed_shared_list_fails_closed(self):
        manager = SimpleNamespace(get_course_list=lambda **_kw: None)
        with self.assertRaises(app.ResponseShapeError):
            app.shared_course_list(manager)

    def test_gui_marks_stale_and_excludes_it_from_dashboard(self):
        ps1 = (Path(__file__).parent / 'payload/Zhidao-GUI.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('if ($c.stale) { $cachedRows++; continue }', ps1)
        self.assertIn('历史缓存未计入汇总', ps1)
        self.assertIn('课程接口返回空列表', ps1)
        self.assertIn('历史缓存，尚未重新核验', ps1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
