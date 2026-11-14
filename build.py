#!/usr/bin/env python3
"""Build the Windows installer from an explicit, audited payload allowlist.

Builds take place in an isolated temporary directory. Importing this module
does not build anything and bundle_payload() can be tested without Go.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

BASE = Path(__file__).resolve().parent
SRC = BASE / "src"
PAYLOAD = BASE / "payload"
OUTPUT = BASE / "ZhidaoAssistant-Setup-v5.2.9-beta.2.exe"
INSTALLER_SCRIPT = "Install.ps1"
MANIFEST = "install-files.json"


def load_install_files(payload_dir: Path) -> list[str]:
    """Read the install/packaging contract; reject unsafe or missing entries."""
    paths = json.loads((payload_dir / MANIFEST).read_text(encoding="utf-8"))
    if not isinstance(paths, list) or not paths:
        raise ValueError("Invalid installer file manifest")
    names: set[str] = set()
    for entry in paths:
        if (not isinstance(entry, str) or not entry or entry in (".", "..")
                or any(ch in entry for ch in '/\\:*?"<>|')
                or entry.casefold() in names):
            raise ValueError("Unsafe or duplicated installer resource")
        names.add(entry.casefold())
    if MANIFEST not in paths or "ZhidaoAssistant.exe" not in paths:
        raise ValueError("Manifest must include itself and the launcher")
    required = set(paths) - {"ZhidaoAssistant.exe"}
    for name in required | {INSTALLER_SCRIPT}:
        path = payload_dir / name
        if not path.is_file() or path.is_symlink():
            raise FileNotFoundError("Missing or linked installer resource: " + name)
    # Catch accidental sensitive files, stale artifacts and forgotten modules.
    unexpected = [entry.name for entry in payload_dir.iterdir()
                  if entry.is_file() and entry.name not in required | {INSTALLER_SCRIPT, "ZhidaoAssistant.exe"}]
    if unexpected:
        raise ValueError("Unlisted payload files: " + ", ".join(sorted(unexpected)))
    return paths


def bundle_payload(payload_dir: Path, launcher: Path, output_zip: Path) -> list[str]:
    """Create a deterministic flat ZIP: only manifest entries + Install.ps1."""
    names = load_install_files(payload_dir)
    if not launcher.is_file() or launcher.is_symlink():
        raise FileNotFoundError("Windows launcher was not generated")
    contents = {name: (launcher if name == "ZhidaoAssistant.exe" else payload_dir / name)
                for name in names}
    contents[INSTALLER_SCRIPT] = payload_dir / INSTALLER_SCRIPT
    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=8, strict_timestamps=True) as archive:
        for name, source in sorted(contents.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, source.read_bytes(), compress_type=zipfile.ZIP_DEFLATED,
                             compresslevel=8)
    return sorted(contents)


def build() -> None:
    env = dict(os.environ, GOOS="windows", GOARCH="amd64", CGO_ENABLED="0")
    load_install_files(PAYLOAD)  # Preflight before compiling or replacing output.
    with tempfile.TemporaryDirectory(prefix="zhidao-installer-build-") as temp:
        stage = Path(temp)
        launcher = stage / "ZhidaoAssistant.exe"
        subprocess.run(["go", "build", "-trimpath", "-ldflags=-s -w -H=windowsgui",
                        "-o", str(launcher), "launcher.go"], cwd=SRC, env=env, check=True)
        work = stage / "setup"
        work.mkdir()
        bundle_payload(PAYLOAD, launcher, work / "payload.zip")
        shutil.copyfile(SRC / "installer.go", work / "installer.go")
        subprocess.run(["go", "build", "-trimpath", "-ldflags=-s -w",
                        "-o", str(OUTPUT), "installer.go"], cwd=work, env=env, check=True)
    print(f"Created {OUTPUT} {OUTPUT.stat().st_size:,} bytes")


if __name__ == "__main__":
    build()
