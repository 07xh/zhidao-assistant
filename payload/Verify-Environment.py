"""Check app-local ZHS dependency without reading credentials or contacting a server."""
from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

PINNED_ZHS_VERSION = "0.1.5"


def dependency_ready() -> bool:
    try:
        return version("zhs") == PINNED_ZHS_VERSION
    except (PackageNotFoundError, OSError, ValueError):
        return False


def main() -> int:
    if not dependency_ready():
        print("Expected ZHS 0.1.5 is missing or mismatched")
        return 1
    print("ZHS 0.1.5 verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
