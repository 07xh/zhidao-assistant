#!/usr/bin/env python3
"""Pinned ZHS v0.1.5 local source repair.

Modifies only error reporting, input validation and cleanup. It cannot change
heartbeat protocol/timing/progress formulas and never contacts course servers.
Always requires exact matching upstream Git blob fingerprints, including if
already patched. Works only within the assistant-managed Python venv.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
from importlib import metadata
import json
import os
from pathlib import Path
import secrets
import shutil
import sys
import sysconfig
import tempfile

from verify_and_integrate_v4 import (
    RELS, EXPECTED_GIT_BLOBS, IntegrationError, normalize_and_validate,
)


def installed_package_root() -> Path:
    if sys.prefix == sys.base_prefix:
        raise IntegrationError('拒绝修改系统 Python：请通过知到助手的 .venv Python 执行')
    if metadata.version('zhs') != '0.1.5':
        raise IntegrationError('只允许匹配 ZHS 0.1.5；未知版本拒绝修改')
    site_packages = Path(sysconfig.get_path('purelib')).resolve(strict=True)
    root = site_packages / 'zhs'
    if root.is_symlink() or not root.is_dir() or not root.resolve().is_relative_to(site_packages):
        raise IntegrationError('ZHS 安装目录不存在或存在不安全的链接')
    return root


def installed_files(root: Path) -> dict[str, Path]:
    root = root.resolve(strict=True)
    paths = {}
    for rel in RELS:
        shortened = rel.removeprefix('src/zhs/')
        path = root / shortened
        if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root):
            raise IntegrationError(f'目标文件缺失、为符号链接或路径不安全: {shortened}')
        for parent in path.parents:
            if parent == root:
                break
            if parent.is_symlink():
                raise IntegrationError(f'目标路径含符号链接: {shortened}')
        paths[rel] = path
    return paths


def patch_installed(root: Path, backup_parent: Path, apply: bool,
                    *, expected: dict[str, str] | None = None, replace=os.replace) -> dict:
    """Preflight ALL files, then backup, then atomic replace with rollback.

    expected is injectable only for unit tests; CLI never accepts an override.
    """
    expected = EXPECTED_GIT_BLOBS if expected is None else expected
    paths = installed_files(root)
    original: dict[str, bytes] = {}
    updated: dict[str, bytes] = {}
    statuses: dict[str, list[str]] = {}
    for rel, path in paths.items():
        raw = path.read_bytes()
        if b'\r' in raw:
            raise IntegrationError(f'{rel}: 源码换行格式发生变化，拒绝自动修复')
        text = raw.decode('utf-8')
        revised, notes = normalize_and_validate(text, rel, expected)
        original[rel], updated[rel], statuses[rel] = raw, revised.encode('utf-8'), notes
    changes = [rel for rel in RELS if original[rel] != updated[rel]]
    result = {'mode': 'apply' if apply else 'check', 'version': '0.1.5',
              'changes': changes, 'statuses': statuses, 'modified': False,
              'backup': None}
    if not apply or not changes:
        return result

    backup_parent.mkdir(parents=True, exist_ok=True)
    backup = backup_parent / ('zhs015-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + secrets.token_hex(4))
    backup.mkdir(mode=0o700, exist_ok=False)
    record = {'package_path': str(root), 'version': '0.1.5',
              'created_utc': datetime.now(timezone.utc).isoformat(),
              'sha256_before': {}, 'sha256_after': {}}
    for rel in RELS:
        short = rel.removeprefix('src/zhs/')
        dest = backup / short
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(original[rel])
        shutil.copystat(paths[rel], dest)
        record['sha256_before'][short] = hashlib.sha256(original[rel]).hexdigest()
        record['sha256_after'][short] = hashlib.sha256(updated[rel]).hexdigest()
    (backup / 'manifest.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

    touched = []
    try:
        for rel in changes:
            path = paths[rel]
            if path.read_bytes() != original[rel]:
                raise IntegrationError(f'源文件在校验后发生变化: {rel}')
            fd, name = tempfile.mkstemp(prefix='.zhs-repair-', suffix='.tmp', dir=path.parent)
            tmp = Path(name)
            try:
                with os.fdopen(fd, 'wb') as f:
                    f.write(updated[rel])
                    f.flush()
                    os.fsync(f.fileno())
                shutil.copystat(path, tmp)
                # Mark before replace: failing implementations may mutate then raise.
                touched.append(rel)
                replace(tmp, path)
            finally:
                tmp.unlink(missing_ok=True)
        for rel in RELS:
            if paths[rel].read_bytes() != updated[rel]:
                raise IntegrationError(f'写入后内容校验失败: {rel}')
        result['modified'], result['backup'] = True, str(backup)
        return result
    except BaseException:
        errors = []
        for rel in reversed(touched):
            try:
                shutil.copy2(backup / rel.removeprefix('src/zhs/'), paths[rel])
            except OSError as exc:
                errors.append(f'{rel}:{type(exc).__name__}')
        if errors:
            raise IntegrationError('部分源码未能回滚；请根据备份恢复: ' + str(backup) + ' / ' + ','.join(errors))
        raise


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    grp = p.add_mutually_exclusive_group(required=True)
    grp.add_argument('--check', action='store_true', help='核验但不修改环境')
    grp.add_argument('--apply', action='store_true', help='应用安全修复（保留备份）')
    args = p.parse_args()
    try:
        root = installed_package_root()
        backup_parent = Path(os.environ['LOCALAPPDATA']) / 'ZHSDesktop' / 'ZHS-source-backups'
        result = patch_installed(root, backup_parent, args.apply)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (IntegrationError, OSError, ValueError, UnicodeError) as exc:
        print(f'ZHS 安全修复失败: {type(exc).__name__}: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
