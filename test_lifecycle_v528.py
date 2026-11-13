"""Cross-platform, fail-closed contract checks (not a substitute for Windows integration)."""
from pathlib import Path
import re

root = Path(__file__).parent
module = (root / 'payload/AppLifecycle.ps1').read_text('utf-8')
installer = (root / 'payload/Install.ps1').read_text('utf-8-sig')
uninstaller = (root / 'payload/Uninstall.ps1').read_text('utf-8-sig')
assert 'Get-CimInstance -ClassName Win32_Process' in module
assert '[regex]::Escape($absolute)' in module
assert "$path -ieq $launcher" in module
assert '$hostNames -icontains $name' in module
assert 'Stop-Process -Id ([int]$proc.ProcessId) -Force' in module
assert 'Get-ZhidaoAppProcesses -InstallRoot $InstallRoot | Where-Object' in module
assert '$_.CreationDate -eq $proc.CreationDate' in module
assert 'CloseMainWindow()' in module
assert "'Zhidao-GUI.ps1'" in module and "'Official-Player.ps1'" in module
assert "'Zhidao-Task.cmd'" in module and "'zhidao_only.py'" in module
assert 'ParentProcessId' in module and '.venv\\Scripts\\zhs.exe' in module
assert "throw '无法验证正在运行的旧版知到助手进程" in module
assert 'Stop-ZhidaoAppProcesses -InstallRoot $root' in installer
assert 'Stop-ZhidaoAppProcesses -InstallRoot $root' in uninstaller
assert 'Read-Host' not in installer
assert 'Wait-LauncherAvailable' not in installer
assert 'Assert-LauncherAvailable' in installer
assert "'AppLifecycle.ps1'" in installer
assert 'Get-FileHash -LiteralPath $src -Algorithm SHA256' in installer
assert "foreach ($oldName in @('ZHS-CLI.cmd','ZHS-GUI.ps1'))" in installer
assert "Remove-Item -LiteralPath $root -Recurse -Force" not in installer
assert "Remove-Item -LiteralPath $root -Recurse -Force" in uninstaller
assert 'if ($RemoveZhsData)' in uninstaller
assert 'privacy-accepted-v5.2.7.flag' in (root / 'payload/Zhidao-GUI.ps1').read_text('utf-8-sig')
print('Passed lifecycle safety/upgrade assertions (source contracts only).')
