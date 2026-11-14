"""Read-only ZHS 0.1.5 console-output observer.

This wraps the original public ZHS entrypoint, forwards stdout unchanged to the
interactive console and writes ONLY validated numeric progress to a temporary
local file. It never modifies ZHS network/heartbeat behavior.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import runpy
import sys
import tempfile
import time
from typing import TextIO

TOKEN_RE = re.compile(r"^[0-9a-f]{32}$")
ID_RE = re.compile(r"^[1-9][0-9]{0,19}$")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
VIDEO_RE = re.compile(r"\bplaying\s+\[[^\r\n]{0,512}\]\s*(\d{1,3}(?:\.\d)?)%", re.I)
RESOURCE_RE = re.compile(r"处理资源\s+(\d{1,6})/(\d{1,6})")
MAX_PERCENT = 100.0
MAX_RESOURCE_TOTAL = 100000


def app_data_dir() -> Path:
    root = os.environ.get("LOCALAPPDATA")
    if not root:
        raise RuntimeError("LOCALAPPDATA unavailable")
    return Path(root) / "ZHSDesktop"


class NumericTelemetry:
    """No course names, log lines, credentials, URLs or response bodies persist."""

    def __init__(self, token: str, directory: Path | None = None):
        if not TOKEN_RE.fullmatch(token):
            raise ValueError("invalid monitor token")
        self.token = token
        self.root = directory if directory is not None else app_data_dir()
        self.path = self.root / f"monitor-zhs-{token}.json"
        self.percent: float | None = None
        self.resource_index: int | None = None
        self.resource_total: int | None = None
        self.last_snapshot: tuple[float | None, int | None, int | None] | None = None

    def receive(self, chunk: str) -> None:
        # Only the final console frame is needed: ZHS overwrites progress via CR.
        # Input may contain arbitrary user/API text; never store or echo it.
        safe = ANSI_RE.sub("", chunk[-4096:])
        newest = re.split(r"[\r\n]", safe)[-1]
        r = RESOURCE_RE.search(newest)
        if r:
            i, n = int(r.group(1)), int(r.group(2))
            if 1 <= i <= n <= MAX_RESOURCE_TOTAL:
                if (self.resource_index, self.resource_total) != (i, n):
                    self.percent = None
                self.resource_index, self.resource_total = i, n
        v = VIDEO_RE.search(newest)
        if v:
            p = float(v.group(1))
            if 0 <= p <= MAX_PERCENT:
                self.percent = p
        if r or v:
            self.publish()

    def publish(self) -> None:
        observation = (self.percent, self.resource_index, self.resource_total)
        if observation == self.last_snapshot:
            return
        self.root.mkdir(parents=True, exist_ok=True)
        data = {
            "v": 1, "token": self.token,
            "videoSegmentPercent": self.percent,
            "resourceIndex": self.resource_index,
            "resourceTotal": self.resource_total,
            "at": time.time(),
        }
        temp_path: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=self.root,
                prefix="monitor-zhs-write-", suffix=".tmp", delete=False
            ) as stream:
                temp_path = Path(stream.name)
                json.dump(data, stream, separators=(",", ":"), ensure_ascii=True)
            os.replace(temp_path, self.path)
            self.last_snapshot = observation
        finally:
            if temp_path is not None:
                try:
                    temp_path.unlink(missing_ok=True)
                except OSError:
                    pass


class StdoutObserver:
    def __init__(self, output: TextIO, sink: NumericTelemetry):
        self.output = output
        self.sink = sink
        self.frame = ""

    def write(self, text: str) -> int:
        n = self.output.write(text)
        # Never interfere with the original ZHS console on malformed output,
        # bad local filesystem permissions, or telemetry errors.
        try:
            self.frame = (self.frame + text)[-4096:]
            # Upstream progress typically prints CR + playing ... without LF.
            self.sink.receive(self.frame)
            self.frame = re.split(r"[\r\n]", self.frame)[-2048:]
        except Exception:
            pass
        return n

    def flush(self) -> None:
        self.output.flush()

    def __getattr__(self, name: str):
        return getattr(self.output, name)


def main() -> int:
    if len(sys.argv) != 4:
        return 2
    _, token, course_id, class_id = sys.argv
    if not TOKEN_RE.fullmatch(token) or not ID_RE.fullmatch(course_id) or not ID_RE.fullmatch(class_id):
        return 2
    sink = NumericTelemetry(token)
    original_stdout = sys.stdout
    original_argv = sys.argv
    try:
        sys.stdout = StdoutObserver(original_stdout, sink)
        sys.argv = ["zhs", "play", "-c", f"{course_id}:{class_id}", "--type", "ai"]
        # Invoke the installed ZHS 0.1.5 CLI without patching its APIs,
        # report generation, send logic, delays or session state.
        runpy.run_module("zhs.__main__", run_name="__main__", alter_sys=False)
        return 0
    finally:
        sys.stdout = original_stdout
        sys.argv = original_argv
        try:
            sink.path.unlink(missing_ok=True)
        except OSError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
