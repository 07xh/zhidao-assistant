"""Offline integrity and transaction checks; upstream checkout is not included."""
from pathlib import Path
import tempfile
import unittest

from apply_safe_fixes_v2 import AI, ZH, FIXES as V2_FIXES, LEGACY_FORMS
from apply_http_safety_v3 import FILE as HTTP, FIXES as V3_FIXES
from verify_and_integrate_v4 import (RELS, IntegrationError, git_blob_sha, integrate,
                                     prepare, original_form)
from test_http_safety_v3 import SOURCE as HTTP_SOURCE


# Small syntax-valid stand-ins for the three files. They are NOT upstream source.
from test_safe_fixes_v2 import mock_source

AI_SOURCE = """import time
from typing import Any
import httpx
from loguru import logger

class Demo:
    def duration(self, result):
        video_length = result["data"][0]["time"]
        return video_length

    def process(self, course_id, class_id, file_id, knowledge_id, played_time):
        while False:
            self._report_video_progress(course_id, class_id, file_id, knowledge_id, played_time)

    def fetch(self, url, file_id):
        try:
            if True:
                client = httpx.Client(timeout=30.0)
                client.get(url, params={"fileId": file_id})
                client.close()
        except Exception as e:
            if True:
                logger.debug(f"watchVideo 请求失败（可忽略）: {e}")

    def report(self):
        try:
            return True
        except Exception as e:
            logger.error(f"上报视频进度失败: {e}")
            return False
"""
ZH_SOURCE = """import time

class Demo:
    def play_course(self, course_name, ctx, rac_id, logger, tree_print, msg_done, msg_error, video):
        begin_time = time.time()
        tv = True
        logger.info(f"play_course: {course_name}, chapters={len(ctx.chapters)}")
        for chapter in range(1):
            for lesson in range(1):
                for video_id in range(1):
                    try:
                        pass
                    except KeyboardInterrupt:
                        raise
                    except Exception as exc:
                        self._clear_progress()
                        logger.error(
                            "Video failed: {} (racId={}, videoId={}) - {}",
                            video.name,
                            rac_id,
                            video.video_id,
                            exc,
                        )
                        tree_print(msg_error(f"!! 视频失败: {video.name} - {exc}"), depth=3, enabled=tv)
                        continue
        cost = time.time() - begin_time
        logger.info("play_course done: {} ({:.1f}s)", course_name, cost)
        tree_print(msg_done(f"完成课程: {course_name} ({cost:.1f}s)"), depth=1, enabled=tv)

    def _watch(self, video_id, logger):
        try:
            pass
        except Exception as exc:
            logger.error(f"Failed to watch video {video_id}: {exc}")
"""

class IntegrationTests(unittest.TestCase):
    def make_tree(self, folder: Path) -> dict[str, str]:
        code = {AI: AI_SOURCE, ZH: ZH_SOURCE, HTTP: HTTP_SOURCE}
        for rel, source in code.items():
            file = folder / rel
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(source, encoding='utf-8')
        return {rel: git_blob_sha(source.encode()) for rel, source in code.items()}

    def test_git_blob_hash_stable(self):
        self.assertEqual(git_blob_sha(b'test\n'), '9daeafb9864cf43055ae93beb0afd6c7d144bfa4')

    def test_normalization_unpatched(self):
        for rel in RELS:
            source = mock_source(rel) if rel != HTTP else HTTP_SOURCE
            self.assertEqual(original_form(source, rel), source)

    def test_wrong_repository_is_rejected_without_writes(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'repo'
            expected = self.make_tree(root)
            expected[HTTP] = '0' * 40
            before = (root / HTTP).read_bytes()
            with self.assertRaises(IntegrationError):
                integrate(root, True, expected=expected)
            self.assertEqual((root / HTTP).read_bytes(), before)

    def test_reject_symlinks(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'repo'
            expected = self.make_tree(root)
            src = root / HTTP
            other = root / 'other.py'
            other.write_bytes(src.read_bytes())
            src.unlink()
            src.symlink_to(other)
            with self.assertRaises(IntegrationError):
                integrate(root, True, expected=expected)

    def test_successful_transaction_and_idempotent(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'repo'
            expected = self.make_tree(root)
            initial = {rel:(root/rel).read_bytes() for rel in RELS}
            check = integrate(root, False, expected=expected)
            self.assertEqual(len(check['changes']), 3)
            for rel in RELS:
                self.assertEqual((root/rel).read_bytes(), initial[rel])
            applied = integrate(root, True, expected=expected)
            self.assertTrue(applied['modified'])
            for rel in RELS:
                self.assertNotEqual((root/rel).read_bytes(),initial[rel])
            backup = Path(applied['backup'])
            self.assertTrue((backup/'manifest.json').exists())
            for rel in RELS:
                self.assertEqual((backup/rel).read_bytes(), initial[rel])
            result = integrate(root, True, expected=expected)
            self.assertEqual(result['changes'], [])
            self.assertFalse(result['modified'])

    def test_mid_transaction_failure_rolls_back(self):
        import os
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'repo'
            expected = self.make_tree(root)
            before = {rel:(root/rel).read_bytes() for rel in RELS}
            calls = 0
            def failed_replace(src, dst):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError('injected I/O failure')
                return os.replace(src,dst)
            with self.assertRaises(OSError):
                integrate(root, True, expected=expected, replace=failed_replace)
            for rel in RELS:
                self.assertEqual((root/rel).read_bytes(), before[rel])

    def test_corrupt_source_rejected_before_all_writes(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'repo'
            expected = self.make_tree(root)
            src = root / ZH
            src.write_text(src.read_text()+"\n# untracked edit\n",encoding='utf-8')
            pre = {rel:(root/rel).read_bytes() for rel in RELS}
            with self.assertRaises(IntegrationError):
                integrate(root, True, expected=expected)
            for rel in RELS:
                self.assertEqual((root/rel).read_bytes(), pre[rel])

    def test_existing_backup_blocks_second_apply(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'repo'
            expected = self.make_tree(root)
            b = root.parent / (root.name+'-pre-v4-backup')
            b.mkdir()
            with self.assertRaises(IntegrationError):
                integrate(root, True, expected=expected)

    def test_no_heartbeat_fields_in_patch_changes(self):
        patches = '\n'.join(f.old+f.new for f in V2_FIXES)+ '\n'.join(f.old+f.new for f in V3_FIXES)
        for key in ('lastWatchTime','studyTotalTime','watchUId','time.sleep(2)'):
            self.assertNotIn(key, patches)

    def test_pinned_upstream_blobs_declared(self):
        from verify_and_integrate_v4 import EXPECTED_GIT_BLOBS
        self.assertEqual(set(EXPECTED_GIT_BLOBS),set(RELS))
        self.assertTrue(all(len(h)==40 for h in EXPECTED_GIT_BLOBS.values()))

if __name__ == '__main__':
    unittest.main()
