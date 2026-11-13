# SPDX-License-Identifier: GPL-3.0-only
# Safe application-only uninstall. The shared .zhs directory belongs to ZHS itself.
param([switch]$RemoveZhsData)
$ErrorActionPreference = 'Stop'
if ($RemoveZhsData) {
    throw 'For safety this installer cannot delete the shared .zhs folder. Other ZHS tools use it; manage your own backup separately.'
}
$root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'
if (Test-Path -LiteralPath $root -PathType Container) {
    # Close exactly this installation's processes, not arbitrary PowerShell/Python tasks.
    $lifecycle = Join-Path $root 'AppLifecycle.ps1'
    if (-not (Test-Path -LiteralPath $lifecycle -PathType Leaf)) {
        throw '缺少进程识别模块，无法安全自动卸载；请重新运行最新版安装程序修复。'
    }
    . $lifecycle
    Stop-ZhidaoAppProcesses -InstallRoot $root
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
}
$shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) '知到学习助手.lnk'
Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
$regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ZhidaoAssistant'
Remove-Item -LiteralPath $regKey -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Uninstalled Zhidao Assistant V5.2.8. Shared %USERPROFILE%\.zhs was preserved.'
Write-Warning 'The shared .zhs directory may still contain plaintext cookies.json; this standalone app cannot encrypt upstream ZHS storage.'
