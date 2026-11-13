"""Ensure CMD batch scripts have no BOM, unlike Windows PowerShell 5.1."""
from pathlib import Path
root = Path(__file__).resolve().parent / 'payload'
for path in root.glob('*.cmd'):
    raw = path.read_bytes()
    assert not raw.startswith(b"\xef\xbb\xbf"), f"CMD UTF-8 BOM will break @echo off: {path.name}"
    assert raw.splitlines()[0].strip().lower() == b"@echo off", f"Missing @echo off: {path.name}"
    raw.decode('utf-8')
print('PASS: CMD files start at @echo off without BOM')
