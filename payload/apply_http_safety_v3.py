#!/usr/bin/env python3
"""ZHS v0.1.5 conservative HTTP error-handling patch.

Only changes input validation, response error reporting and local resource cleanup.
Never changes request destinations, payloads, timing, retry count or progress rules.
"""
from __future__ import annotations
import argparse
import ast
from dataclasses import dataclass
from pathlib import Path
import shutil
import sys
import tempfile

FILE = 'src/zhs/api/http_client.py'

@dataclass(frozen=True)
class Fix:
    name: str
    old: str
    new: str

FIXES = (
    Fix('reject_unsupported_cookie_type',
        '''        if isinstance(value, httpx.Cookies):
            self._cookies = value''',
        '''        if not isinstance(value, (httpx.Cookies, list, dict)):
            raise TypeError("cookies must be httpx.Cookies, a list or a dict")
        if isinstance(value, httpx.Cookies):
            self._cookies = value'''),
    Fix('reject_malformed_caslogc_json_shape',
        '''                self._uuid = data.get("uuid")''',
        '''                self._uuid = data.get("uuid") if isinstance(data, dict) and isinstance(data.get("uuid"), str) else None'''),
    Fix('api_json_error_classification',
        '''        result: dict[str, Any] = resp.json()
        return result''',
        '''        try:
            result = resp.json()
        except ValueError as exc:
            raise ValueError("接口响应不是合法 JSON；未确认业务结果") from exc
        if not isinstance(result, dict):
            raise ValueError("接口响应格式错误：应为 JSON 对象；未确认业务结果")
        return result'''),
    Fix('close_clear_reference_even_on_exception',
        '''        if self._client:
            self._client.close()
            self._client = None''',
        '''        if self._client is not None:
            client, self._client = self._client, None
            client.close()'''),
)

class SourceMismatch(RuntimeError):
    pass


def transform(source: str) -> tuple[str, list[str]]:
    output = source
    status: list[str] = []
    for fix in FIXES:
        n_old, n_new = output.count(fix.old), output.count(fix.new)
        if n_new == 1:
            status.append(f'ALREADY {fix.name}')
        elif n_old == 1 and n_new == 0:
            output = output.replace(fix.old, fix.new, 1)
            status.append(f'APPLY {fix.name}')
        else:
            raise SourceMismatch(f'{fix.name}: expected unique v0.1.5 anchor (old={n_old}, new={n_new})')
    ast.parse(output, filename=FILE)
    return output, status


def run(repo: Path, apply: bool = False) -> list[str]:
    root = repo.resolve(strict=True)
    path = root / FILE
    # Reject links that redirect outside the working tree, and non-regular files.
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
        raise SourceMismatch(f'unsafe or missing source path: {path}')
    original_bytes = path.read_bytes()
    if b'\r\n' in original_bytes:
        raise SourceMismatch('CRLF source format must be reviewed before patching')
    original = original_bytes.decode('utf-8')
    ast.parse(original, filename=FILE)
    revised, statuses = transform(original)
    if not apply or revised == original:
        return statuses
    backup = path.with_suffix(path.suffix + '.before-v3.bak')
    if backup.exists():
        raise SourceMismatch(f'backup already exists: {backup}')
    tempname = None
    # Keep unchanged source if temporary staging fails; backup is never overwritten.
    try:
        with tempfile.NamedTemporaryFile('wb', dir=path.parent, prefix='.v3-', suffix='.tmp', delete=False) as f:
            tempname = Path(f.name)
            f.write(revised.encode('utf-8'))
            f.flush()
        shutil.copystat(path, tempname)
        if path.read_bytes() != original_bytes:
            raise SourceMismatch('source changed during verification; no changes applied')
        shutil.copy2(path, backup)
        tempname.replace(path)
    finally:
        if tempname is not None:
            tempname.unlink(missing_ok=True)
    return statuses


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, required=True, help='offline checkout of ZHS v0.1.5')
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true', help='read-only anchor and syntax check')
    mode.add_argument('--apply', action='store_true', help='create backup and apply conservative fix')
    args = p.parse_args()
    try:
        for item in run(args.repo, apply=args.apply):
            print(item)
        print('OK; no platform or heartbeat verification performed')
        return 0
    except (SourceMismatch, OSError, ValueError, UnicodeError, SyntaxError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 2

if __name__ == '__main__':
    raise SystemExit(main())
