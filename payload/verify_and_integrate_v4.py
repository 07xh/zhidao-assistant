#!/usr/bin/env python3
"""ZHS v0.1.5 conservative patch integrator (offline source checkout only).

Never starts ZHS, talks to course servers, or changes heartbeat protocol, timing,
progress math or endpoints. An exact pinned upstream file or its known V2/V3
patched form is required. All three files are staged before any are written.
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Callable

from apply_safe_fixes_v2 import AI, ZH, FIXES as V2_FIXES, LEGACY_FORMS, transform as v2_transform
from apply_http_safety_v3 import FILE as HTTP, FIXES as V3_FIXES, transform as v3_transform

# Pinned to git tag v0.1.5; obtained from the GitHub repository file blobs.
EXPECTED_GIT_BLOBS = {
    AI: 'c86d8de2f18b66c3a74921a35211ef0f6f1bf789',
    ZH: '03261b9497df2108e5151d100fca2af469a28551',
    HTTP: 'c4cb00cabb146b26999be59456ae2dc4ab95e658',
}
RELS = (AI, ZH, HTTP)


class IntegrationError(Exception):
    pass


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()


def original_form(source: str, rel: str) -> str:
    """Reverse only known, exact replacements for upstream identity check."""
    if rel == HTTP:
        fixes = V3_FIXES
    else:
        fixes = [f for f in V2_FIXES if f.path == rel]
    result = source
    # Reverse in opposite order to account for mutually adjacent edits.
    for fix in reversed(fixes):
        if result.count(fix.new) == 1:
            result = result.replace(fix.new, fix.old, 1)
        elif rel == ZH and fix.name in LEGACY_FORMS and result.count(LEGACY_FORMS[fix.name]) == 1:
            result = result.replace(LEGACY_FORMS[fix.name], fix.old, 1)
        elif result.count(fix.old) != 1:
            raise IntegrationError(f'无法识别源文件修订形式: {rel} / {fix.name}')
    return result


def normalize_and_validate(source: str, rel: str, expected: dict[str, str]) -> tuple[str, list[str]]:
    try:
        source.encode('utf-8')
        restored = original_form(source, rel)
    except Exception as exc:
        raise IntegrationError(f'{rel}: 补丁前置状态验证失败: {exc}') from exc
    sha = git_blob_sha(restored.encode('utf-8'))
    if sha != expected[rel]:
        raise IntegrationError(f'{rel}: 与 ZHS v0.1.5 原始文件不匹配 (git blob {sha}); 拒绝修改')
    if rel == HTTP:
        edited, changes = v3_transform(source)
    else:
        edited, changes = v2_transform(source, rel)
    try:
        ast.parse(edited, filename=rel)
    except SyntaxError as exc:
        raise IntegrationError(f'{rel}: 生成代码语法检查失败: {exc}') from exc
    return edited, changes


def _validate_path(root: Path, rel: str) -> Path:
    path = root / rel
    # Do not follow symlinked source files or their parent directories.
    for item in (path, *path.parents):
        if item == root.parent:
            break
        if item.is_symlink():
            raise IntegrationError(f'{rel}: 禁止修改符号链接路径')
    if not path.is_file() or not path.resolve().is_relative_to(root):
        raise IntegrationError(f'{rel}: 源文件不存在或位于仓库外')
    return path


def prepare(repo: Path, expected: dict[str, str] | None = None) -> tuple[dict[Path, bytes], dict[Path, bytes], dict[str, list[str]]]:
    root = repo.resolve(strict=True)
    expected = expected if expected is not None else EXPECTED_GIT_BLOBS
    originals, updated, notes = {}, {}, {}
    for rel in RELS:
        path = _validate_path(root, rel)
        raw = path.read_bytes()
        if b'\r\n' in raw or b'\r' in raw:
            raise IntegrationError(f'{rel}: 不支持 CRLF/CRLF 混合源文件，请先人工核对')
        try:
            content = raw.decode('utf-8')
        except UnicodeDecodeError as exc:
            raise IntegrationError(f'{rel}: 不是有效 UTF-8') from exc
        edited, changes = normalize_and_validate(content, rel, expected)
        originals[path] = raw
        updated[path] = edited.encode('utf-8')
        notes[rel] = changes
    return originals, updated, notes


def integrate(repo: Path, apply: bool, *, expected: dict[str, str] | None = None,
              replace: Callable[[Path, Path], None] | None = None) -> dict:
    root = repo.resolve(strict=True)
    originals, updated, notes = prepare(root, expected)
    changes = [p for p in originals if originals[p] != updated[p]]
    result = {'mode': 'apply' if apply else 'check', 'upstream': 'v0.1.5',
              'changes': [str(p.relative_to(root)) for p in changes],
              'statuses': notes, 'modified': False, 'backup': None}
    if not apply or not changes:
        return result

    # Backup location is outside working tree. Check all inputs again before mutation.
    bkroot = root.parent / (root.name + '-pre-v4-backup')
    if bkroot.exists():
        raise IntegrationError(f'备份目录已存在，不覆盖: {bkroot}')
    bkroot.mkdir(mode=0o700)
    manifest = {'source': str(root), 'version': 'ZHS v0.1.5',
                'generated_utc': datetime.now(timezone.utc).isoformat(),
                'sha256_before': {}, 'sha256_after': {}}
    for p, raw in originals.items():
        rel = p.relative_to(root)
        target = bkroot / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        shutil.copystat(p, target)
        manifest['sha256_before'][str(rel)] = hashlib.sha256(raw).hexdigest()
        manifest['sha256_after'][str(rel)] = hashlib.sha256(updated[p]).hexdigest()
    (bkroot / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

    replace = replace or os.replace
    written: list[Path] = []
    try:
        for p in changes:
            if p.read_bytes() != originals[p]:
                raise IntegrationError(f'并发修改: {p} 已变化，开始回滚')
            fd, tmppath = tempfile.mkstemp(prefix='.zhs-v4-', suffix='.tmp', dir=p.parent)
            tmp = Path(tmppath)
            try:
                with os.fdopen(fd, 'wb') as f:
                    f.write(updated[p])
                    f.flush()
                    os.fsync(f.fileno())
                shutil.copystat(p, tmp)
                # Record BEFORE rename so even failures after rename can be rolled back.
                written.append(p)
                replace(tmp, p)
            finally:
                tmp.unlink(missing_ok=True)
        for p, raw in updated.items():
            if p.read_bytes() != raw:
                raise IntegrationError(f'写入后校验失败: {p}')
        result['modified'] = True
        result['backup'] = str(bkroot)
        return result
    except BaseException:
        restore_errors = []
        for p in reversed(written):
            try:
                src = bkroot / p.relative_to(root)
                shutil.copy2(src, p)
            except Exception as e:
                restore_errors.append(f'{p}: {type(e).__name__}')
        if restore_errors:
            raise IntegrationError('回滚不完整，请从备份目录手动恢复：' + ', '.join(restore_errors))
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path, help='ZHS v0.1.5 源码根目录，不能指向现有 EXE')
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--check', action='store_true', help='仅检查，永不修改')
    modes.add_argument('--apply', action='store_true', help='保留完整备份，应用补丁')
    args = parser.parse_args()
    try:
        result = integrate(args.repo, apply=args.apply)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (IntegrationError, OSError, ValueError, SyntaxError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
