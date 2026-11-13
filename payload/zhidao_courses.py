"""Pure course identity, official navigation URL and fail-closed stale-cache policy.

No authentication, HTTP requests, files or platform progress writes.
Adapter functions are re-exported by zhidao_only for compatibility.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any
from urllib.parse import quote

from zhidao_diagnostics import ResponseShapeError


def source_type(course: dict[str, Any]) -> str:
    value = course.get("courseType")
    if value not in ("ai", "shared"):
        raise ResponseShapeError("Unknown course type")
    return value


def identity(course: dict[str, Any]) -> tuple[str, str, str]:
    typ = source_type(course)
    if typ == "ai":
        return ("ai", str(course.get("courseId") or ""), str(course.get("classId") or ""))
    route = str(course.get("recruitAndCourseId") or "").strip()
    # Shared course display IDs can be zero, duplicated, or not the actual route.
    if re.fullmatch(r"[A-Za-z0-9_+./=:-]{1,512}", route):
        return ("shared", "route:" + route, "")
    course_id = str(course.get("courseId") or "").strip()
    if course_id and course_id != "0":
        return ("shared", "id:" + course_id, "")
    return ("shared", "name:" + str(course.get("name") or ""), "")


def progress_key(course: dict[str, Any]) -> str:
    """Non-reversible identity key for failed-course bookkeeping (no raw route in logs)."""
    raw = json.dumps(identity(course), ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def official_learning_url(row: dict[str, Any]) -> str:
    """Build navigational URLs from trusted fixed origins, never from API-supplied URLs.

    The AI knowledgeStudy route is documented upstream, but may require re-login
    or fail for certain institution deployments; users can navigate from portal.
    """
    if source_type(row) == "ai":
        try:
            course_id, class_id = int(row["courseId"]), int(row["classId"])
            if course_id > 0 and class_id > 0:
                return ("https://ai-smart-course-student-pro.zhihuishu.com/"
                        f"singleCourse/knowledgeStudy/{course_id}/{class_id}")
        except (ValueError, TypeError, KeyError):
            pass
    token = str(row.get("recruitAndCourseId") or "").strip()
    # The official ZHS README documents this study URL. Never treat an API-supplied URL as trusted.
    if source_type(row) == "shared" and re.fullmatch(r"[A-Za-z0-9_+./=:-]{1,512}", token):
        return "https://studyvideoh5.zhihuishu.com/stuStudy?recruitAndCourseId=" + quote(token, safe="")
    return "https://www.zhihuishu.com/"


def merge_source_lists(fresh: dict[str, list[dict[str, Any]]], old: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Never carry stale lessons across sessions; retain same-session failed sources."""
    results: list[dict[str, Any]] = []
    for typ in ("shared", "ai"):
        previous = [c for c in old if isinstance(c, dict) and c.get("courseType") == typ]
        if typ in fresh and fresh[typ]:
            results.extend(fresh[typ])
        elif typ in fresh and not previous:
            continue  # confirmed valid empty list for this previously empty source
        else:
            # Do not erase lessons merely because an API temporarily returned [].
            results.extend({**c, "stale": True} for c in previous)
    unique: dict[tuple[str, str, str], dict[str, Any]] = {}
    for course in results:
        if isinstance(course, dict) and course.get("courseType") in ("ai", "shared"):
            unique[identity(course)] = course
    return list(unique.values())


