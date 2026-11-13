#!/usr/bin/env python3
'''ZHS v0.1.5 conservative error-handling fixes. Does not alter heartbeat inputs/rhythm.'''
from __future__ import annotations
import argparse
from dataclasses import dataclass
from pathlib import Path
import shutil
import sys

@dataclass(frozen=True)
class Fix:
    name: str
    path: str
    old: str
    new: str

AI = "src/zhs/ai/video.py"
ZH = "src/zhs/zhidao/video.py"
FIXES = [
    Fix("ai.import_math", AI, "import time\nfrom typing import Any\n", "import math\nimport time\nfrom typing import Any\n"),
    Fix("ai.validate_duration", AI,
        '        video_length = result["data"][0]["time"]',
        '''        try:
            video_length = result["data"][0]["time"]
        except (KeyError, IndexError, TypeError) as exc:
            raise ValueError("视频时长接口响应缺少有效数据；任务已停止") from exc
        if isinstance(video_length, bool) or not isinstance(video_length, (int, float)) or video_length <= 0:
            raise ValueError("视频时长接口返回非法时长；任务已停止")
        try:
            finite = math.isfinite(video_length)
        except (OverflowError, TypeError, ValueError):
            finite = False
        if not finite:
            raise ValueError("视频时长接口返回非法时长；任务已停止")'''),
    Fix("ai.report_failure_is_not_success", AI,
        '            self._report_video_progress(course_id, class_id, file_id, knowledge_id, played_time)',
        '''            if not self._report_video_progress(course_id, class_id, file_id, knowledge_id, played_time):
                wipe_line()
                raise RuntimeError("进度提交失败，已停止本地任务；请只读核对服务器记录")'''),
    Fix("ai.http_client_closed", AI,
        '''                client = httpx.Client(timeout=30.0)
                client.get(url, params={"fileId": file_id})
                client.close()''',
        '''                with httpx.Client(timeout=30.0) as client:
                    client.get(url, params={"fileId": file_id})'''),
    Fix("ai.redact_watch_exception", AI,
        '                logger.debug(f"watchVideo 请求失败（可忽略）: {e}")',
        '                logger.debug("watchVideo 后台请求失败: {}", type(e).__name__)'),
    Fix("ai.redact_progress_exception", AI,
        '            logger.error(f"上报视频进度失败: {e}")',
        '            logger.error("进度提交失败（{}），服务器记录尚未核验", type(e).__name__)'),
    Fix("zh.track_failed_tasks", ZH,
        '''        begin_time = time.time()
        tv = True
        logger.info(f"play_course: {course_name}, chapters={len(ctx.chapters)}")''',
        '''        begin_time = time.time()
        tv = True
        failed_count = 0
        logger.info(f"play_course: {course_name}, chapters={len(ctx.chapters)}")'''),
    Fix("zh.clear_on_keyboard_interrupt", ZH,
        '''                    except KeyboardInterrupt:
                        raise''',
        '''                    except KeyboardInterrupt:
                        self._clear_progress()
                        logger.warning("Course task interrupted by user")
                        raise'''),
    Fix("zh.count_failures_and_redact_errors", ZH,
        '''                    except Exception as exc:
                        self._clear_progress()
                        logger.error(
                            "Video failed: {} (racId={}, videoId={}) - {}",
                            video.name,
                            rac_id,
                            video.video_id,
                            exc,
                        )
                        tree_print(msg_error(f"!! 视频失败: {video.name} - {exc}"), depth=3, enabled=tv)
                        continue''',
        '''                    except Exception as exc:
                        failed_count += 1
                        self._clear_progress()
                        logger.error(
                            "Video failed: {} (racId={}, videoId={}) - {}",
                            video.name,
                            rac_id,
                            video.video_id,
                            type(exc).__name__,
                        )
                        tree_print(msg_error(f"!! 视频失败: {video.name} - {type(exc).__name__}"), depth=3, enabled=tv)
                        continue'''),
    Fix("zh.report_partial_not_completed", ZH,
        '''        logger.info("play_course done: {} ({:.1f}s)", course_name, cost)
        tree_print(msg_done(f"完成课程: {course_name} ({cost:.1f}s)"), depth=1, enabled=tv)''',
        '''        if failed_count:
            logger.warning("Course finished with {} failed video task(s): {}", failed_count, course_name)
            tree_print(msg_warn(f"课程处理结束，但有 {failed_count} 个视频任务失败（{cost:.1f}s）"), depth=1, enabled=tv)
        else:
            logger.info("Course processed without task exceptions: {} ({:.1f}s)", course_name, cost)
            tree_print(msg_done(f"课程任务执行结束（{cost:.1f}s），服务器进度须另行核验"), depth=1, enabled=tv)'''),
    Fix("zh.redact_background_request_error", ZH,
        '            logger.error(f"Failed to watch video {video_id}: {exc}")',
        '            logger.error("Video stream request failed (videoId={}, error={})", video_id, type(exc).__name__)'),
]

class SourceMismatch(RuntimeError):
    pass

# The first error-visibility patch added failed_count but did not redact
# the exception text. Accept it as an input form, too.
LEGACY_FORMS = {
    "zh.count_failures_and_redact_errors": (
        "                    except Exception as exc:\n"
        "                        failed_count += 1\n"
        "                        self._clear_progress()\n"
        "                        logger.error(\n"
        "                            \"Video failed: {} (racId={}, videoId={}) - {}\",\n"
        "                            video.name,\n"
        "                            rac_id,\n"
        "                            video.video_id,\n"
        "                            exc,\n"
        "                        )\n"
        "                        tree_print(msg_error(f\"!! 视频失败: {video.name} - {exc}\"), depth=3, enabled=tv)\n"
        "                        continue"
    )
}

def transform(text: str, path: str) -> tuple[str, list[str]]:
    states = []
    result = text
    for fix in FIXES:
        if fix.path != path:
            continue
        old_count = result.count(fix.old)
        new_count = result.count(fix.new)
        # Check the new form first: some replacements deliberately retain the old
        # one-line expression within a larger guarded block.
        if new_count == 1:
            states.append("ALREADY " + fix.name)
        elif old_count == 1:
            result = result.replace(fix.old, fix.new, 1)
            states.append("APPLY " + fix.name)
        elif fix.name in LEGACY_FORMS and result.count(LEGACY_FORMS[fix.name]) == 1:
            result = result.replace(LEGACY_FORMS[fix.name], fix.new, 1)
            states.append("UPGRADE " + fix.name)
        else:
            raise SourceMismatch(f"{fix.name}: source does not match expected ZHS 0.1.5 snippet "
                                 f"(old={old_count}, new={new_count}); no files written")
    return result, states

def run(repo: Path, apply: bool) -> list[str]:
    originals = {}
    results = {}
    status = []
    for rel in (AI, ZH):
        p = repo / rel
        if not p.is_file():
            raise SourceMismatch(f"missing source file: {p}")
        b = p.read_bytes()
        # Preserve all source newlines (CRLF rejected rather than silently rewritten).
        if b'\r\n' in b:
            raise SourceMismatch(f"CRLF source needs manual review: {p}")
        original = b.decode('utf-8')
        revised, notes = transform(original, rel)
        originals[p] = original
        results[p] = revised
        status.extend(notes)
    # Atomic per-file writes are guarded by a per-file rollback backup.
    if apply:
        for p, result in results.items():
            if result == originals[p]:
                continue
            backup = p.with_suffix(p.suffix + '.before-error-fixes.bak')
            if backup.exists():
                raise SourceMismatch(f"backup already exists; refusing overwrite: {backup}")
        written = []
        try:
            for p, result in results.items():
                if result == originals[p]:
                    continue
                backup = p.with_suffix(p.suffix + '.before-error-fixes.bak')
                shutil.copy2(p, backup)
                tmp = p.with_suffix(p.suffix + '.temporary-error-fixes')
                tmp.write_text(result, encoding='utf-8', newline='')
                tmp.replace(p)
                written.append((p, backup))
        except BaseException:
            for p, backup in reversed(written):
                shutil.copy2(backup, p)
            raise
    return status

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', required=True, type=Path, help='Path to an offline checkout of ZHS v0.1.5')
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true', help='Validate patch anchors; no modifications')
    mode.add_argument('--apply', action='store_true', help='Create backups and edit two source files')
    opts = ap.parse_args()
    try:
        states = run(opts.repo, opts.apply)
        for state in states:
            print(state)
        print(f'OK: {"applied (backups kept)" if opts.apply else "all anchors matched"}; '
              'does not verify platform behavior')
        return 0
    except (SourceMismatch, OSError, UnicodeError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 2

if __name__ == '__main__':
    raise SystemExit(main())
