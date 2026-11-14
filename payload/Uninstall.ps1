# SPDX-License-Identifier: GPL-3.0-only
# Remove this app's files, runtime, browser profile, caches, shortcut and HKCU
# registration. Shared upstream ~/.zhs remains unless explicitly requested
# with an interactive, typed confirmation; upgrades never invoke this script.
param([switch]$RemoveZhsData)
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'
$cleanup = Join-Path $PSScriptRoot 'LegacyCleanup.ps1'
if (-not (Test-Path -LiteralPath $cleanup -PathType Leaf)) {
    throw '安全清理模块缺失；请使用最新版安装包修复后重新卸载。'
}
. $cleanup
$root = Assert-ZhidaoOwnedRoot -InstallRoot $root

$shared = Join-Path $env:USERPROFILE '.zhs'
$sharedPresent = Test-Path -LiteralPath $shared
if ($RemoveZhsData -and $sharedPresent) {
    # This folder can contain credentials and may be shared by unrelated ZHS
    # tools. Never infer consent from a regular uninstall or an upgrade.
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        throw 'USERPROFILE is unavailable; refusing shared data deletion.'
    }
    $expectedShared = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.zhs'))
    $actualShared = [IO.Path]::GetFullPath($shared)
    if (-not [string]::Equals($actualShared,$expectedShared,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Shared ZHS path mismatch; refusing deletion.'
    }
    $sharedEntry = Get-Item -LiteralPath $actualShared -Force -ErrorAction Stop
    if (-not $sharedEntry.PSIsContainer -or
        ($sharedEntry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Shared ZHS path is a link or not a directory; refusing deletion.'
    }
    Assert-ZhidaoNoReparseTree -Directory $actualShared
    Write-Warning '这将永久删除共享 .zhs 目录，包含 Cookie、账号会话及其他 ZHS 工具的数据，无法恢复。'
    $typed = Read-Host '仅在确认备份且所有使用 .zhs 的程序都已关闭后，输入 DELETE SHARED ZHS DATA'
    if ($typed -cne 'DELETE SHARED ZHS DATA') {
        throw '未确认删除共享 ZHS 数据；卸载未开始，所有数据保持原样。'
    }
}

if (Test-Path -LiteralPath $root -PathType Container) {
    # Do not stop arbitrary PowerShell/Python processes, only exact app-owned
    # processes identified by the reviewed lifecycle module.
    $lifecycle = Join-Path $root 'AppLifecycle.ps1'
    if (-not (Test-Path -LiteralPath $lifecycle -PathType Leaf)) {
        throw '缺少进程识别模块，无法安全卸载；请运行最新版安装程序修复。'
    }
    . $lifecycle
    Stop-ZhidaoAppProcesses -InstallRoot $root
    # A junction/symlink to another location must not be traversed by -Recurse.
    Assert-ZhidaoNoReparseTree -Directory $root
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
}

$shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) '知到学习助手.lnk'
Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
$regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ZhidaoAssistant'
Remove-Item -LiteralPath $regKey -Recurse -Force -ErrorAction SilentlyContinue

# Previous failed setups may leave timestamped, app-owned files under TEMP.
# This only removes vetted names older than 7 days; it does not sweep TEMP.
try {
    $cleaned = Clear-ZhidaoInstallerTempResidue -OlderThanDays 7
    Write-Host ('已清理过期安装临时残留：' + $cleaned + ' 项')
} catch {
    Write-Warning ('部分安装临时残留未能清理：' + $_.Exception.Message)
}

if ($RemoveZhsData -and $sharedPresent) {
    # This is an explicitly selected full uninstall, never auto-upgrade.
    Remove-Item -LiteralPath $shared -Recurse -Force -ErrorAction Stop
    Write-Host '共享 .zhs 数据已按明确确认删除。'
} else {
    Write-Host '已删除应用目录、Python 专用运行环境、官方网页缓存、快捷方式与卸载注册项。'
    Write-Host '共享 %USERPROFILE%\.zhs 数据已保留。如需彻底清除，须单独使用 -RemoveZhsData 并确认。'
}
