"""Offline contracts for pure course identity, safe URLs and stale-cache retention."""
from __future__ import annotations

import unittest

from test_cache_v527 import app
import zhidao_courses as model


class CourseModelTests(unittest.TestCase):
    def test_backward_compatible_adapter_exports(self):
        for name in ("source_type", "identity", "progress_key",
                     "official_learning_url", "merge_source_lists"):
            self.assertIs(getattr(app, name), getattr(model, name))

    def test_shared_course_id_is_not_unique_without_route(self):
        a = {"courseType": "shared", "courseId": 0, "name": "重复", "recruitAndCourseId": "route/a"}
        b = {**a, "recruitAndCourseId": "route/b"}
        self.assertNotEqual(model.identity(a), model.identity(b))
        self.assertNotEqual(model.progress_key(a), model.progress_key(b))

    def test_same_course_identity_is_stable_without_exposing_token(self):
        course = {"courseType": "shared", "recruitAndCourseId": "opaque-private-route",
                  "courseId": 4, "name": "课程"}
        marker = model.progress_key(course)
        self.assertEqual(marker, model.progress_key(dict(course)))
        self.assertEqual(len(marker), 64)
        self.assertNotIn("opaque-private-route", marker)

    def test_learning_url_only_uses_known_origins(self):
        course = {"courseType": "shared", "recruitAndCourseId": "a/b?c=d", "name": "课程"}
        url = model.official_learning_url(course)
        self.assertTrue(url.startswith("https://studyvideoh5.zhihuishu.com/stuStudy?"))
        self.assertIn("a%2Fb%3Fc%3Dd", url)
        bad = {**course, "recruitAndCourseId": "http://evil.invalid/redirect"}
        self.assertEqual(model.official_learning_url(bad), "https://www.zhihuishu.com/")
        ai = {"courseType": "ai", "courseId": 45, "classId": 2}
        self.assertTrue(model.official_learning_url(ai).startswith(
            "https://ai-smart-course-student-pro.zhihuishu.com/"
        ))

    def test_unknown_course_type_is_rejected(self):
        with self.assertRaises(app.ResponseShapeError):
            model.identity({"courseType": "unknown"})

    def test_transient_empty_keeps_stale_same_session_course(self):
        old = [{"courseType": "ai", "courseId": 20, "classId": 2, "name": "曾经"}]
        merged = model.merge_source_lists({"ai": []}, old)
        self.assertEqual(len(merged), 1)
        self.assertTrue(merged[0]["stale"])
        self.assertFalse(old[0].get("stale", False))
        self.assertEqual(model.merge_source_lists({"ai": []}, []), [])

    def test_valid_fresh_records_replace_prior_records(self):
        old = [{"courseType": "ai", "courseId": 20, "classId": 2, "name": "曾经"}]
        fresh = [{**old[0], "name": "更新", "stale": False}]
        merged = model.merge_source_lists({"ai": fresh}, old)
        self.assertEqual(merged, fresh)


if __name__ == "__main__":
    unittest.main()
