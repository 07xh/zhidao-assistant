"""V5.2.7 offline regression tests; all ZHS session dependencies are stubbed."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import patch

# Import the read-only adapter without requiring user credentials or a live API.
for name in ('zhs', 'zhs.cli', 'zhs.cli.bootstrap', 'zhs.zhidao', 'zhs.zhidao.course',
             'zhs.zhidao.models', 'zhs.ai', 'zhs.ai.course'):
    sys.modules.setdefault(name, types.ModuleType(name))
sys.modules['zhs.cli.bootstrap'].load_config_and_session = lambda **_: None
sys.modules['zhs.zhidao.course'].ZhidaoCourseManager = object
sys.modules['zhs.zhidao.models'].extract_course_id = lambda x: x.course_id
sys.modules['zhs.ai.course'].AiCourseManager = object
spec = importlib.util.spec_from_file_location('zhidao_only_test', Path(__file__).parent/'payload/zhidao_only.py')
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.previous_data = app.DATA
        app.DATA = Path(self.directory.name)
        self.addCleanup(lambda: setattr(app, 'DATA', self.previous_data))
        (app.DATA/'cookies.json').write_text('SESSION_A', encoding='utf-8')
        self.fp = app.session_fingerprint(create=True)

    def test_new_session_roundtrip(self):
        self.assertEqual(len(self.fp),64)
        app.update_cache(app.COURSES, lambda old: {'courses':[{'courseType':'ai','courseId':1}]}, self.fp)
        self.assertEqual(len(app.read_cache(app.COURSES)['courses']),1)
        raw = (app.DATA/app.COURSES).read_text()
        self.assertNotIn('SESSION_A',raw)
        self.assertNotIn('cookies.json',raw)

    def test_session_rotation_hides_old_cache(self):
        app.update_cache(app.COURSES, lambda old: {'courses':[{'courseType':'ai','courseId':1}]}, self.fp)
        (app.DATA/'cookies.json').write_text('SESSION_B')
        self.assertEqual(app.read_cache(app.COURSES), {})
        with self.assertRaises(app.ResponseShapeError):
            app.update_cache(app.PROGRESS,lambda old:{'courses':[]},self.fp)
        new_fp=app.session_fingerprint()
        app.update_cache(app.COURSES, lambda old: {'courses':[{'courseType':'ai','courseId':2}]}, new_fp)
        self.assertEqual(app.read_cache(app.COURSES)['courses'][0]['courseId'],2)

    def test_legacy_cache_hidden(self):
        (app.DATA/app.COURSES).write_text(json.dumps({'source':'zhidao','courses':[{'courseId':101}]}))
        self.assertEqual(app.read_cache(app.COURSES),{})

    def test_missing_cookies_fail_closed(self):
        app.update_cache(app.COURSES,lambda old:{'courses':[]},self.fp)
        (app.DATA/'cookies.json').unlink()
        self.assertEqual(app.read_cache(app.COURSES),{})

    def test_shared_course_distinct_routes(self):
        a={'courseType':'shared','courseId':0,'name':'Same','recruitAndCourseId':'a/123'}
        b={'courseType':'shared','courseId':0,'name':'Same','recruitAndCourseId':'b/123'}
        self.assertNotEqual(app.identity(a),app.identity(b))
        self.assertEqual(len(app.merge_source_lists({'shared':[a,b]},[])),2)

    def test_only_same_session_partial_failure_retained_as_stale(self):
        old=[{'courseType':'ai','courseId':1,'classId':9,'name':'Old'}]
        merged=app.merge_source_lists({'shared':[{'courseType':'shared','courseId':2,'name':'New'}]}, old)
        self.assertTrue(next(x for x in merged if x['courseType']=='ai')['stale'])

    def test_empty_new_source_preserves_only_prior_nonempty(self):
        old=[{'courseType':'ai','courseId':1,'classId':9}]
        self.assertEqual(len(app.merge_source_lists({'ai':[]},old)),1)
        self.assertEqual(app.merge_source_lists({'ai':[]},[]),[])

    def test_unknown_type_refused(self):
        with self.assertRaises(app.ResponseShapeError):
            app.source_type({'courseType':'invalid'})

    def test_no_lost_updates_under_contention(self):
        exceptions=[]
        def increment():
            try:
                for _ in range(10):
                    def update(old):
                        return {'value': int(old.get('value',0))+1}
                    app.update_cache(app.COURSES,update,self.fp)
            except Exception as e:
                exceptions.append(str(e))
        jobs=[threading.Thread(target=increment) for _ in range(5)]
        for job in jobs:job.start()
        for job in jobs:job.join()
        self.assertFalse(exceptions,exceptions)
        self.assertEqual(app.read_cache(app.COURSES).get('value'),50)


if __name__=='__main__':
    unittest.main(verbosity=2)
