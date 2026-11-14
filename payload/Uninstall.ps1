# SPDX-License-Identifier: GPL-3.0-only
# Full removal of this application's per-user installation and app-only
# residuals. Shared %USERPROFILE%\.zhs may be used by independent ZHS tools.
param([switch]$RemoveZhsData)
$ErrorActionPreference = 'Stop'
if ($RemoveZhsData) {
    throw 'For safety this uninstall cannot delete shared .zhs credentials or caches. Back up/manage those separately.'
}
$root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'
if (Test-Path -LiteralPath $root -PathType Container) {
    if ([bool]((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw '安装目录为重解析点，拒绝递归删除，避免误删其他程序数据。'
    }
    # Do not trust arbitrary similarly named processes. Fail closed when
    # the safety modules are missing from an older installation.
    $lifecycle = Join-Path $root 'AppLifecycle.ps1'
    $cleanup = Join-Path $root 'LegacyCleanup.ps1'
    foreach ($module in @($lifecycle,$cleanup)) {
        if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
            throw ('缺少卸载安全组件：' + (Split-Path -Leaf $module) + '。请先用最新版安装器修复。')
        }
    }
    . $lifecycle
    . $cleanup
    Stop-ZhidaoAppProcesses -InstallRoot $root
    # Whole app-local directory: installed files, private .venv, uv runtime,
    # WebView2 profile, app cache and all historical app-version files.
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
} else {
    # Reuse the bundled cleanup module when launched from an extracted setup.
    $fallback = Join-Path $PSScriptRoot 'LegacyCleanup.ps1'
    if (-not (Test-Path -LiteralPath $fallback -PathType Leaf)) {
        throw '缺少卸载清理组件，未删除任何其他文件。'
    }
    . $fallback
}
# Only delete shortcuts whose target is explicitly inside our install root.
try {
    $shortcuts = Clear-ZhidaoLegacyShortcuts -InstallRoot $root -IncludePrimaryShortcut
    Write-Host ('[Uninstall] Removed app shortcuts: ' + $shortcuts)
} catch {
    Write-Warning ('Shortcuts cleanup incomplete: ' + $_.Exception.Message)
}
try {
    $registrations = Clear-ZhidaoLegacyRegistry -InstallRoot $root -IncludePrimaryKey
    Write-Host ('[Uninstall] Removed app registry entries: ' + $registrations)
} catch {
    Write-Warning ('Registry cleanup incomplete: ' + $_.Exception.Message)
}
try {
    $oldSetup = Clear-ZhidaoOldSetupTemp -TempRoot $env:TEMP -MinimumAgeHours 24
    Write-Host ('[Uninstall] Removed stale setup/temp items: ' + $oldSetup)
} catch {
    Write-Warning ('Temp cleanup incomplete: ' + $_.Exception.Message)
}
Write-Host '知到学习助手已卸载：应用文件、应用运行环境与识别出的旧版残留已清理。'
Write-Host '保留共享 %USERPROFILE%\.zhs 数据（含可能存在的 cookies.json），未影响其他 ZHS 工具。'
