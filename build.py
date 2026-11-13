#!/usr/bin/env python3
"""Cross-compile V5 Windows installer; keep all app resources in zip root."""
from pathlib import Path
import os
import subprocess
import zipfile

BASE = Path(__file__).resolve().parent
SRC = BASE / 'src'
PAYLOAD = BASE / 'payload'
OUTPUT = BASE / 'ZhidaoAssistant-Setup-v5.2.8-hotfix9-zhs-reliability.exe'
ENV = dict(os.environ, GOOS='windows', GOARCH='amd64', CGO_ENABLED='0')
subprocess.run(['go','build','-trimpath','-ldflags=-s -w -H=windowsgui','-o',str(PAYLOAD/'ZhidaoAssistant.exe'),'launcher.go'],cwd=SRC,env=ENV,check=True)
with zipfile.ZipFile(SRC / 'payload.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=8) as z:
    for f in sorted(PAYLOAD.iterdir()):
        if f.is_file() and not f.name.endswith(('.pyc', '.zip')):
            z.write(f, f.name)
subprocess.run(['go','build','-trimpath','-ldflags=-s -w','-o',str(OUTPUT),'installer.go'],cwd=SRC,env=ENV,check=True)
print(f'Created {OUTPUT} {OUTPUT.stat().st_size:,} bytes')
