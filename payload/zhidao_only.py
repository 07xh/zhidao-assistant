"""Read-only Zhidao App course adapter and single-course progress verifier.

Reuses official ZHS 0.1.5 session and reader modules. Does not call video simulation, fabricated heartbeats, progress-writing,
question submission, or exam APIs. Official web player handles normal study records.
"""
from __future__ import annotations

import json
import re
import socket
import hmac
import hashlib
import tempfile
import time
from contextlib import contextmanager
from urllib.parse import quote
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from zhs.cli.bootstrap import load_config_and_session
from zhs.zhidao.course import ZhidaoCourseManager
from zhs.zhidao.models import extract_course_id
from zhs.ai.course import AiCourseManager

DATA = Path.home() / ".zhs"
COURSES = "zhidao-courses.json"
PROGRESS = "zhidao-progress.json"
SALT = "zhidao-cache-salt.bin"
LOCK = ".zhidao-cache.lock"
CACHE_SCHEMA = 4


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


def session_fingerprint(*, create: bool = False) -> str | None:
    """An HMAC of the *local login file*, not a stable user/account identifier.

    This deliberately fails closed when cookies rotate or the old cache has no
    marker. It can cause extra refreshes after normal re-login, but never silently
    treats a previous session's lessons as the current account's lessons.
    """
    cookie_file, salt_file = DATA / "cookies.json", DATA / SALT
    try:
        cookies = cookie_file.read_bytes()
        if not cookies:
            return None
        if create and not salt_file.exists():
            DATA.mkdir(parents=True, exist_ok=True)
            try:
                # Exclusive create is safe when two processes start concurrently.
                with salt_file.open("xb") as out:
                    out.write(os.urandom(32))
            except FileExistsError:
                pass
        salt = salt_file.read_bytes()
        if len(salt) != 32:
            return None
        return hmac.new(salt, cookies, hashlib.sha256).hexdigest()
    except OSError:
        return None


def read_cache(name: str) -> dict[str, Any]:
    """Legacy and other-session files are retained on disk but never displayed."""
    if name not in (COURSES, PROGRESS):
        raise ValueError("Unsupported cache name")
    try:
        data = json.loads((DATA / name).read_text(encoding="utf-8"))
        fp = session_fingerprint()
        if (isinstance(data, dict) and data.get("source") == "zhidao"
                and fp and hmac.compare_digest(str(data.get("sessionFingerprint") or ""), fp)):
            return data
    except (OSError, ValueError):
        pass
    return {}


@contextmanager
def cache_lock(timeout: float = 8.0):
    """Cross-process lock for cache read/modify/write, on Windows and in tests."""
    DATA.mkdir(parents=True, exist_ok=True)
    with (DATA / LOCK).open("a+b") as handle:
        handle.seek(0)
        handle.write(b"0")
        handle.flush()
        deadline = time.monotonic() + timeout
        while True:
            try:
                if os.name == "nt":
                    import msvcrt
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Course cache busy") from None
                time.sleep(0.1)
        try:
            yield
        finally:
            if os.name == "nt":
                import msvcrt
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def update_cache(name: str, update, expected_fingerprint: str) -> None:
    """Prevent stale login results and unsafe concurrent cache writes."""
    if name not in (COURSES, PROGRESS):
        raise ValueError("Unsupported cache name")
    with cache_lock():
        current = session_fingerprint()
        if not current or not hmac.compare_digest(current, expected_fingerprint):
            raise ResponseShapeError("Login session changed during sync")
        old = read_cache(name)
        data = update(old)
        if not isinstance(data, dict):
            raise ValueError("Invalid cache update")
        data.update(source="zhidao", schemaVersion=CACHE_SCHEMA,
                    sessionFingerprint=expected_fingerprint)
        path = DATA / name
        fd, temporary = tempfile.mkstemp(prefix=".zhidao-", suffix=".tmp", dir=DATA)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as out:
                json.dump(data, out, ensure_ascii=False, indent=2)
                out.flush()
                os.fsync(out.fileno())
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


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


class ResponseShapeError(ValueError):
    """An API response changed shape; no raw response or token should reach UI logs."""


def diagnose(exc: BaseException) -> tuple[str, str]:
    """Allowlisted error output, never print exception text or request URL/cookies."""
    status = getattr(getattr(exc, "response", None), "status_code", None)
    if status is None:
        status = getattr(exc, "status_code", None)
    if status in (401, 403):
        return "AUTH", "登录会话可能失效或权限不足；请重新扫码并重试"
    if status in (429, 500, 502, 503, 504):
        return "SERVICE", "服务器限流或暂时不可用；稍后再试"
    if isinstance(exc, (TimeoutError, socket.timeout)) or "timeout" in type(exc).__name__.lower():
        return "TIMEOUT", "请求超时；检查网络连接或稍后重试"
    if isinstance(exc, (ConnectionError, socket.gaierror)) or "connect" in type(exc).__name__.lower():
        return "NETWORK", "无法连接到课程服务；检查网络和代理设置"
    if isinstance(exc, (ResponseShapeError, ValueError, KeyError, TypeError)) or "validationerror" in type(exc).__name__.lower():
        return "API_SHAPE", "返回数据格式与当前适配器不符；需要核对课程接口"
    if status is not None:
        return "HTTP_ERROR", "课程服务返回错误状态；请稍后重试或核对登录"
    return "UNKNOWN", "请求未成功；请重新扫码并检查网络，保留了旧缓存"


def diagnostic(source: str, exc: BaseException) -> dict[str, str]:
    code, advice = diagnose(exc)
    return {"source": source, "code": code, "advice": advice}


def emit_failure(source: str, exc: BaseException) -> dict[str, str]:
    detail = diagnostic(source, exc)
    print(f"{source}读取失败 [{detail['code']}]：{detail['advice']}；仅保留同一登录会话的旧缓存。")
    return detail


def safe_close(session: Any) -> None:
    """Cleanup must never turn a successful read into an apparent sync failure."""
    if session is not None:
        try:
            session.close()
        except Exception:
            pass


def read_with_retry(operation, *, sleep=time.sleep):
    """One bounded retry for *read-only* operations after transient transport errors.

    Caller is responsible for supplying a genuinely read-only operation.
    Never retry authentication/authorization errors, HTTP 429, validation errors
    or unexpected exceptions.  This is not used for any playback/write requests.
    """
    for attempt in range(2):
        try:
            return operation()
        except Exception as exc:
            status = getattr(getattr(exc, "response", None), "status_code", None)
            if status is None:
                status = getattr(exc, "status_code", None)
            name = type(exc).__name__.lower()
            transient = (
                status in (502, 503, 504)
                or (status is None and (
                    isinstance(exc, (TimeoutError, socket.timeout, ConnectionError, socket.gaierror))
                    or "timeout" in name or "connection" in name))
            )
            if attempt or not transient:
                raise
            sleep(0.3)
    raise AssertionError("unreachable")


def local_login_file_state() -> str:
    """Only validate the ZHS cookie-file envelope; never infer server login from it.

    Matches the upstream read_cookies_file/list_to_cookies format. No cookie
    contents, identifiers or path details are included in diagnostic output.
    """
    try:
        with (DATA / "cookies.json").open("r", encoding="utf-8") as handle:
            rows = json.load(handle)
    except FileNotFoundError:
        return "missing"
    except (OSError, UnicodeError, ValueError):
        return "invalid"
    if (not isinstance(rows, list) or not rows
            or any(not isinstance(row, dict)
                   or not isinstance(row.get("name"), str)
                   or not row["name"]
                   or not isinstance(row.get("value"), str)
                   for row in rows)):
        return "invalid"
    return "present"


def doctor_server() -> int:
    """Verify read-only platform endpoints, not just local cookie parsing.

    No write operation, cached course mutation, video progress submission,
    sensitive identifiers or raw HTTP exception output is performed.
    Return 0=both read endpoints confirmed, 7=partial, 6=neither,
    3=no credential, 4=SDK login check failed/unknown, 5=unexpected bootstrap failure,
    8=malformed local credential file.
    """
    state = local_login_file_state()
    if state == "missing":
        print("[AUTH] 未找到扫码凭证，请先登录。")
        return 3
    if state == "invalid":
        print("[AUTH_LOCAL_INVALID] 本地登录凭证格式无效；未联系服务器，建议重新扫码登录。")
        return 8
    os.chdir(Path.home())
    session = None
    try:
        loaded = load_config_and_session(debug=False, console_log=False, proxy=None)
        if loaded is None:
            print("[AUTH_OR_NETWORK] 凭证存在但服务端登录校验未通过或暂时不可用；先检查网络，不要直接删除凭证。")
            return 4
        _, session = loaded
        # Upstream ZHS bootstrap has already verified getLoginUserInfo.
        # Business API failures must NOT be reclassified as login expiration.
        print("[SESSION_OK] 服务端登录校验通过；正在分别检测课程读取接口。")
        confirmed = []
        failed = []
        for name, read in (
            ("共享课", lambda: shared_course_list(ZhidaoCourseManager(session))[0]),
            ("智慧课程", lambda: ai_course_list(session)),
        ):
            try:
                rows = read_with_retry(read)
                confirmed.append(name)
                print(f"[SERVER_READ_OK] {name}读取成功；条数 {len(rows)}。")
            except Exception as exc:
                code, advice = diagnose(exc)
                failed.append(name)
                print(f"[SERVER_READ_{code}] {name}读取失败：{advice}")
        if not confirmed:
            print("[SERVER_UNCONFIRMED] 两类只读接口均失败；不能判断课程已同步。")
            return 6
        if failed:
            print("[SERVER_PARTIAL] 部分来源读取成功，其他来源需要检查。")
            return 7
        print("[SERVER_OK] 两类课程只读接口均返回有效结果；未发送视频进度。")
        return 0
    except Exception as exc:
        code, advice = diagnose(exc)
        print(f"[{code}] 服务器诊断未完成：{advice}")
        return 5
    finally:
        safe_close(session)


def ai_course_list(session: Any) -> list[dict[str, Any]]:
    """Use ZHS's authenticated, read-only query, but preserve API errors.

    Upstream AiCourseManager.get_ai_course_list() catches all exceptions and
    returns [], which hides network failure as 'zero AI courses'.
    """
    url = f"{session.urls.base}/gateway/t/v1/student/queryStudentAICourseList"
    result = session.zhidao_query(
        url, {"status": 3}, key=session.crypto.key_bytes("home_key"), ok_code=0
    )
    if not isinstance(result, dict):
        raise ResponseShapeError("Malformed AI course envelope")
    raw = result.get("rt")
    if not isinstance(raw, list):
        raise ValueError("AI 课程响应不包含列表")
    parsed = []
    invalid = 0
    for row in raw:
        if not isinstance(row, dict):
            invalid += 1
            continue
        try:
            course_id, class_id = int(row["courseId"]), int(row["classId"])
        except (TypeError, KeyError, ValueError):
            invalid += 1
            continue
        if course_id <= 0 or class_id <= 0:
            invalid += 1
            continue
        item = {
            "name": str(row.get("courseName") or "未命名智慧课程"),
            "courseId": course_id,
            "classId": class_id,
            "courseType": "ai",
        }
        item["officialLearningUrl"] = official_learning_url(item)
        parsed.append(item)
    # A legitimately empty list must remain valid for accounts with no AI courses.
    # The cache merger below protects previously nonempty same-session sources
    # against an unconfirmed transient empty response.
    if invalid and not parsed:
        raise ResponseShapeError("Malformed AI course list")
    if invalid:
        print(f"智慧课程有 {invalid} 条无法识别的记录，已跳过；其他课程仍可使用。")
    return parsed


def shared_course_list(manager: ZhidaoCourseManager) -> tuple[list[dict[str, Any]], dict[tuple[str, str, str], Any]]:
    raw = manager.get_course_list(force=True)
    if raw is None or isinstance(raw, (dict, str, bytes)):
        raise ResponseShapeError("Malformed shared course listing")
    rows, lookup = [], {}
    for item in raw:
        # Preserve the actual opaque route token for normal, official course-page navigation.
        token = str(item.secret or "")
        row = {"name": item.course_name, "courseId": extract_course_id(item),
               "courseType": "shared", "recruitAndCourseId": token}
        row["officialLearningUrl"] = official_learning_url(row)
        rows.append(row)
        lookup[identity(row)] = item
    return rows, lookup


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


def shared_progress(manager: ZhidaoCourseManager, raw: Any, row: dict[str, Any]) -> dict[str, Any]:
    ctx = manager.get_context(raw.secret, force=True)
    videos = list(ctx.videos.values())
    completed = sum(v.watch_state == 1 for v in videos)
    return {
        **row,
        "videoCount": len(videos),
        "completedVideos": completed,
        "videos": [{
            "name": v.name,
            "videoId": v.video_id,
            "durationSeconds": v.video_sec,
            "studiedSeconds": v.study_total_time,
            "serverCompleted": v.watch_state == 1,
        } for v in videos],
        "stale": False,
        "lastVerifiedAt": datetime.now(timezone.utc).isoformat(),
    }


def ai_progress(manager: AiCourseManager, row: dict[str, Any]) -> dict[str, Any]:
    course = manager.get_knowledge_points(int(row["courseId"]), int(row["classId"]))
    items = []
    for theme in course.cake_theme_list:
        for point in theme.knowledge_list:
            progress = max(0, min(100, int(point.study_progress)))
            items.append({
                "name": point.knowledge_name,
                "theme": theme.theme_name,
                "knowledgeId": point.knowledge_id,
                "progressPercent": progress,
                "isFullyProgressed": progress >= 100,
            })
    # Knowledge-point percentages are NOT the official overall course progress
    # nor the independent mastery score displayed in the Zhidao App.
    return {
        **row,
        "name": row.get("name") or course.course_name,
        "knowledgePointCount": len(items),
        "fullProgressPoints": sum(x["isFullyProgressed"] for x in items),
        "knowledgePoints": items,
        "stale": False,
        "lastVerifiedAt": datetime.now(timezone.utc).isoformat(),
    }


def verify_one(course_type: str, course_id: str, class_id: str = "") -> int:
    """Read one selected real course's server state; do not submit study progress."""
    if course_type not in ("shared", "ai"):
        print("不支持的课程类型")
        return 2
    if (not course_id.isdecimal() or len(course_id) > 20 or int(course_id) <= 0 or
            (course_type == "ai" and (not class_id.isdecimal() or len(class_id) > 20 or int(class_id) <= 0))):
        print("课程标识不合法")
        return 2
    if not (DATA / "cookies.json").is_file():
        print("[AUTH] 尚未扫码登录。请先登录再核验课程。")
        return 3
    os.chdir(Path.home())
    try:
        loaded = load_config_and_session(debug=False, console_log=False, proxy=None)
    except Exception as exc:
        emit_failure("单课会话", exc)
        return 1
    if loaded is None:
        print("[AUTH_OR_NETWORK] 登录状态未获服务器确认；可能是登录过期或网络异常，旧进度未改变")
        return 1
    _, session = loaded
    try:
        fp = session_fingerprint(create=True)
        if not fp:
            print("[AUTH] 未找到可验证的本机登录状态；不会读取旧账号课程")
            return 1
        cached = read_cache(COURSES).get("courses", [])
        if not isinstance(cached, list):
            cached = []
        candidates = [c for c in cached if isinstance(c, dict) and c.get("courseType") == course_type and
                      str(c.get("courseId")) == course_id and
                      (course_type != "ai" or str(c.get("classId")) == class_id)]
        if len(candidates) != 1:
            print("[API_SHAPE] 当前会话中课程不存在或标识不唯一；请先同步课程")
            return 2
        selected = candidates[0]
        if course_type == "ai":
            detail = read_with_retry(lambda: ai_progress(AiCourseManager(session), selected))
        else:
            mgr = ZhidaoCourseManager(session)
            _, lookups = read_with_retry(lambda: shared_course_list(mgr))
            raw = lookups.get(identity(selected))
            if raw is None:
                print("[API_SHAPE] 官方课程目录中找不到该共享课，旧进度已保留")
                return 1
            detail = read_with_retry(lambda: shared_progress(mgr, raw, selected))
        def updated(old: dict[str, Any]) -> dict[str, Any]:
            previous = old.get("courses") if isinstance(old.get("courses"), list) else []
            rows = [r for r in previous if isinstance(r, dict) and r.get("courseType") in ("ai", "shared")
                    and identity(r) != identity(selected)]
            rows.append(detail)
            # Preserve source-wide failures: verifying one course does not prove
            # that the entire source directory or other courses are now healthy.
            source_errors = old.get("failedSources") if isinstance(old.get("failedSources"), list) else []
            empty_sources = old.get("unconfirmedEmptySources") if isinstance(old.get("unconfirmedEmptySources"), list) else []
            names = old.get("failedCourses") if isinstance(old.get("failedCourses"), list) else []
            details = old.get("failedCourseDetails") if isinstance(old.get("failedCourseDetails"), list) else []
            remaining_names = []
            remaining_details = []
            for index, name in enumerate(names):
                if name == selected.get("name"):
                    continue
                remaining_names.append(name)
                if index < len(details):
                    remaining_details.append(details[index])
            # Old caches can have unstructured error markers. Unknown errors
            # remain incomplete until a full, successful read-only sync.
            unexplained = bool(old.get("incomplete")) and not (
                source_errors or empty_sources or names or any(r.get("stale") for r in previous))
            incomplete = bool(source_errors or empty_sources or remaining_names
                              or any(r.get("stale") for r in rows) or unexplained)
            return {"fetchedAt": datetime.now(timezone.utc).isoformat(),
                    "courses": rows, "incomplete": incomplete,
                    "failedSources": source_errors,
                    "failedSourceDetails": old.get("failedSourceDetails", []),
                    "unconfirmedEmptySources": empty_sources,
                    "failedCourses": remaining_names,
                    "failedCourseDetails": remaining_details}
        update_cache(PROGRESS, updated, fp)
        print("[VERIFIED] 已从服务器重新读取选定课程状态；本地播放时间不等于官方完成证明")
        return 0
    except Exception as exc:
        emit_failure("单课进度", exc)
        return 1
    finally:
        safe_close(session)

def doctor() -> int:
    """Read-only connection preflight. Never emits cookies, IDs or raw exceptions.

    Return codes: 0=local SDK session initialized (server login NOT verified),
    3=no local credential, 4=local session not available, 5=environment error.
    No login bypass or fabricated progress is performed.
    """
    if not (DATA / "cookies.json").is_file():
        print("[AUTH] 尚未找到本机扫码登录凭证。请在设置中扫码登录。")
        return 3
    os.chdir(Path.home())
    session = None
    try:
        loaded = load_config_and_session(debug=False, console_log=False, proxy=None)
        if loaded is None:
            print("[AUTH_OR_NETWORK] 登录未获服务器确认。可能是会话过期或网络异常；重新扫码后再试。")
            return 4
        _, session = loaded
        print("[READY_LOCAL] 本地 ZHS 会话初始化成功，但未验证服务器是否认可登录；请用只读课程同步进一步验证。官方网页还需独立登录。")
        return 0
    except Exception as exc:
        code, advice = diagnose(exc)
        print(f"[{code}] 连接诊断失败：{advice}")
        return 5
    finally:
        if session is not None:
            try:
                session.close()
            except Exception:
                pass


def main(mode: str) -> int:
    if mode not in ("courses", "progress"):
        print("仅允许读取课程或学习进度。")
        return 2
    # Do not interpret an absent local credential as an empty course list.
    if not (DATA / "cookies.json").is_file():
        print("[AUTH] 尚未扫码登录。请在设置中登录后再同步课程。")
        return 3
    # ZHS 0.1.5 uses .zhs relative to the process working directory.
    os.chdir(Path.home())
    session_result = load_config_and_session(debug=False, console_log=False, proxy=None)
    if session_result is None:
        print("[AUTH_OR_NETWORK] 会话初始化失败；请检查扫码登录、网络或代理。旧缓存已保留。")
        return 1
    _, session = session_result
    try:
        fp = session_fingerprint(create=True)
        if not fp:
            print("[AUTH] 登录状态未能绑定本地缓存。不会复用旧账号数据。")
            return 1
        shared_mgr = ZhidaoCourseManager(session)
        ai_mgr = AiCourseManager(session)
        fresh: dict[str, list[dict[str, Any]]] = {}
        lookups: dict[tuple[str, str, str], Any] = {}
        errors = []
        details = []
        try:
            fresh["shared"], lookups = read_with_retry(lambda: shared_course_list(shared_mgr))
        except Exception as exc:
            errors.append("共享课")
            details.append(emit_failure("共享课", exc))
        try:
            fresh["ai"] = read_with_retry(lambda: ai_course_list(session))
        except Exception as exc:
            errors.append("智慧课程")
            details.append(emit_failure("智慧课程", exc))
        if not fresh:
            print("两类课程均未成功读取，请勿将此结果视为没有课程。")
            return 1

        now = datetime.now(timezone.utc).isoformat()
        saved_courses: list[dict[str, Any]] = []
        unconfirmed_empty_sources: list[str] = []
        def updated_courses(old: dict[str, Any]) -> dict[str, Any]:
            nonlocal saved_courses, unconfirmed_empty_sources
            previous_courses = old.get("courses") if isinstance(old.get("courses"), list) else []
            # Empty-but-valid responses may be transient; do not silently treat
            # retained historical courses as a newly confirmed server result.
            unconfirmed_empty_sources = [
                typ for typ in ("shared", "ai")
                if typ in fresh and not fresh[typ] and any(
                    isinstance(row, dict) and row.get("courseType") == typ
                    for row in previous_courses
                )
            ]
            saved_courses = merge_source_lists(fresh, previous_courses)
            return {"fetchedAt": now, "courses": saved_courses,
                    "failedSources": errors, "failedSourceDetails": details,
                    "unconfirmedEmptySources": unconfirmed_empty_sources}
        update_cache(COURSES, updated_courses, fp)
        courses = saved_courses
        print(f"本次接口返回：共享课 {len(fresh.get('shared', []))} 门，智慧课程 {len(fresh.get('ai', []))} 门。")
        for row in courses:
            suffix = " [历史缓存，待确认]" if row.get("stale") else ""
            print(f"  [{ '智慧课程' if source_type(row) == 'ai' else '共享课'}] {row['name']}{suffix}")
        if unconfirmed_empty_sources:
            print("[EMPTY_UNCONFIRMED] 接口返回空列表，但当前会话存在该来源的历史课程；保留历史数据并标为待确认，不能认定同步完整。")
        if mode == "courses":
            return 1 if errors or unconfirmed_empty_sources else 0

        old_progress = read_cache(PROGRESS)
        prior_rows = old_progress.get("courses") if isinstance(old_progress.get("courses"), list) else []
        prior_by_id = {identity(x): x for x in prior_rows if isinstance(x, dict)}
        progress_rows = []
        failed_courses = []
        failed_detail_codes = []
        for row in courses:
            key = identity(row)
            try:
                if source_type(row) == "ai":
                    detail = read_with_retry(lambda: ai_progress(ai_mgr, row))
                else:
                    raw = lookups.get(key)
                    if raw is None:
                        raise ValueError("本次未成功获取共享课内部标识")
                    detail = read_with_retry(lambda: shared_progress(shared_mgr, raw, row))
                progress_rows.append(detail)
            except Exception as exc:
                failed_courses.append(row["name"])
                failed_detail_codes.append(diagnostic("单课进度", exc))
                old = prior_by_id.get(key)
                if old:
                    progress_rows.append({**old, "stale": True})
                code, advice = diagnose(exc)
                print(f"课程进度读取失败 [{code}]：{advice}；可用时保留旧记录。")
        def updated_progress(old: dict[str, Any]) -> dict[str, Any]:
            # Keep a newer single-course verification if it finished while this
            # full synchronization was reading the server.
            latest = {identity(x): x for x in old.get("courses", [])
                      if isinstance(x, dict) and x.get("courseType") in ("ai", "shared")}
            rows = []
            for item in progress_rows:
                prior = latest.get(identity(item))
                if (prior and str(prior.get("lastVerifiedAt") or "") >
                        str(item.get("lastVerifiedAt") or "")):
                    rows.append(prior)
                else:
                    rows.append(item)
            return {"fetchedAt": now, "courses": rows,
                    "incomplete": bool(errors or failed_courses or unconfirmed_empty_sources),
                    "failedSources": errors, "failedSourceDetails": details,
                    "unconfirmedEmptySources": unconfirmed_empty_sources,
                    "failedCourses": failed_courses, "failedCourseDetails": failed_detail_codes}
        update_cache(PROGRESS, updated_progress, fp)
        print(f"已保存 {len(progress_rows)} 门课程的可用进度；未完成同步的来源会明确标注。")
        return 1 if errors or failed_courses or unconfirmed_empty_sources else 0
    finally:
        safe_close(session)


if __name__ == "__main__":
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "doctor":
            sys.exit(doctor())
        elif len(sys.argv) == 2 and sys.argv[1] == "doctor-server":
            sys.exit(doctor_server())
        elif len(sys.argv) == 5 and sys.argv[1] == "verify-one":
            sys.exit(verify_one(sys.argv[2], sys.argv[3], sys.argv[4]))
        else:
            sys.exit(main(sys.argv[1] if len(sys.argv) == 2 else ""))
    except Exception as exc:
        # Never print raw exception: request URLs or auth tokens may be embedded.
        code, advice = diagnose(exc)
        print(f"读取失败 [{code}]：{advice}；旧缓存已保留。")
        sys.exit(1)
