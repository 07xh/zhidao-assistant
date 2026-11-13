"""Regression tests: Windows PowerShell 5.1 must load every localized PS1 as UTF-8 BOM."""
from pathlib import Path
root = Path(__file__).resolve().parent
for file in (root / "payload").glob("*.ps1"):
    raw = file.read_bytes()
    if any(byte >= 128 for byte in raw):
        assert raw.startswith(b"\xef\xbb\xbf"), f"Missing UTF-8 BOM: {file.name}"
        raw[3:].decode("utf-8")
module = (root / "payload" / "AppLifecycle.ps1").read_bytes()
assert module.startswith(b"\xef\xbb\xbf")
assert "function Get-ZhidaoAppProcesses" in module.decode('utf-8-sig')
assert "function Stop-ZhidaoAppProcesses" in module.decode('utf-8-sig')
print("PASS: all localized PowerShell scripts include UTF-8 BOM (Windows PS 5.1 safe).")
