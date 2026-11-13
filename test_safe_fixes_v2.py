"""Offline-only unit tests for a source patcher (no platform network calls)."""
import math
from pathlib import Path
import tempfile
import unittest

from apply_safe_fixes_v2 import AI, ZH, FIXES, LEGACY_FORMS, SourceMismatch, transform, run


def mock_source(path: str) -> str:
    # Original v0.1.5 fragments are tested as anchors; this is NOT a full repo.
    return '\n\n'.join(f.old for f in FIXES if f.path == path) + '\n'


class SafeFixesTests(unittest.TestCase):
    def test_all_changes_apply_once(self):
        for path in (AI, ZH):
            result, changes = transform(mock_source(path), path)
            self.assertTrue(all(x.startswith('APPLY ') for x in changes))
            self.assertEqual(len(changes), sum(f.path == path for f in FIXES))
            for f in FIXES:
                if f.path == path:
                    self.assertIn(f.new, result)

    def test_idempotence(self):
        for path in (AI, ZH):
            result, _ = transform(mock_source(path), path)
            again, changes = transform(result, path)
            self.assertEqual(result, again)
            self.assertTrue(all(x.startswith('ALREADY ') for x in changes))

    def test_refuse_mismatched_source(self):
        with self.assertRaises(SourceMismatch):
            transform('# different version\n', AI)

    def test_check_mode_does_not_change_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for rel in (AI, ZH):
                p = root / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(mock_source(rel), encoding='utf-8')
            before = {rel: (root / rel).read_bytes() for rel in (AI, ZH)}
            results = run(root, False)
            self.assertEqual(len(results), len(FIXES))
            self.assertEqual(before, {rel: (root / rel).read_bytes() for rel in (AI, ZH)})

    def test_apply_writes_backups_and_second_check(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for rel in (AI, ZH):
                p = root / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(mock_source(rel), encoding='utf-8')
            run(root, True)
            for rel in (AI, ZH):
                p = root / rel
                self.assertTrue(p.with_suffix(p.suffix+'.before-error-fixes.bak').exists())
                self.assertNotEqual(p.read_text(), mock_source(rel))
            states = run(root, False)
            self.assertTrue(all(x.startswith('ALREADY ') for x in states))

    def test_no_partial_write_on_second_file_mismatch(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for rel in (AI, ZH):
                p = root / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(mock_source(rel) if rel == AI else '# unsupported', encoding='utf-8')
            before = (root / AI).read_bytes()
            with self.assertRaises(SourceMismatch):
                run(root, True)
            self.assertEqual(before, (root / AI).read_bytes())

    def test_reject_crlf(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for rel in (AI, ZH):
                p = root / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(mock_source(rel).replace('\n', '\r\n').encode())
            with self.assertRaises(SourceMismatch):
                run(root, False)

    def test_duration_guard_empty_invalid_valid(self):
        # Extract the exact guard intended for ZHS and execute in an isolated fn.
        fix = next(f for f in FIXES if f.name == 'ai.validate_duration')
        scope = {'math': math}
        exec('def read_duration(result):\n' + fix.new + '\n        return video_length\n', scope)
        fn = scope['read_duration']
        for bad in [{}, {'data': []}, {'data': [{}]},
                    {'data': [{'time': 0}]}, {'data': [{'time': -3}]},
                    {'data': [{'time': True}]}, {'data': [{'time': float('nan')}]},
                    {'data': [{'time': float('inf')}]}, {'data': [{'time': '120'}]}, {'data': [{'time': 10**1000}]}]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                fn(bad)
        self.assertEqual(fn({'data': [{'time': 120}]}), 120)
        self.assertEqual(fn({'data': [{'time': 120.5}]}), 120.5)

    def test_legacy_first_patch_source_upgrades(self):
        original = mock_source(ZH)
        intermediate = original
        previous = {
            'zh.track_failed_tasks',
            'zh.report_partial_not_completed',
        }
        for f in FIXES:
            if f.path == ZH and f.name in previous:
                intermediate = intermediate.replace(f.old, f.new, 1)
        target = next(f for f in FIXES if f.name == 'zh.count_failures_and_redact_errors')
        intermediate = intermediate.replace(target.old, LEGACY_FORMS[target.name], 1)
        result, notes = transform(intermediate, ZH)
        self.assertIn('UPGRADE '+target.name, notes)
        self.assertIn(target.new, result)

    def test_no_heartbeat_payload_or_rate_changes_in_fixes(self):
        changes = '\n'.join(f.old+'\n'+f.new for f in FIXES)
        for forbidden in ('studyTotalTime', 'lastWatchTime', 'time.sleep(2)', 'dateFormate'):
            self.assertNotIn(forbidden, changes)


if __name__ == '__main__':
    unittest.main(verbosity=2)
