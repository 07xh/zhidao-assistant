# SPDX-License-Identifier: GPL-3.0-only
# Cleanup confined to the current user's Zhidao Assistant installation.
# Do NOT remove shared %USERPROFILE%\.zhs, login data, custom files,
# virtualenv or WebView2 profile during in-place upgrades.

function Test-ZhidaoOrdinaryFile([string]$path) {
    try {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        $entry = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        return -not [bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } catch { return $false }
}

function Test-ZhidaoOrdinaryDirectory([string]$path) {
    try {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { return $false }
        $entry = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        return -not [bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } catch { return $false }
}

function Test-ZhidaoPathInsideRoot([string]$path,[string]$root) {
    try {
        $base = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        $full = [IO.Path]::GetFullPath($path)
        return $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Get-ZhidaoRetiredFiles {
    param(
        [Parameter(Mandatory=$true)][string]$InstallRoot,
        [Parameter(Mandatory=$true)][string[]]$CurrentFiles
    )
    # Explicit pre-manifest names from early standalone releases.
    $retired = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [void]$retired.Add('ZHS-CLI.cmd')
    [void]$retired.Add('ZHS-GUI.ps1')

    # For future upgrades, only consider previous, explicitly packaged
    # application-code names. Do not trust arbitrary JSON names or recursive
    # globs and never infer ownership of cookies, caches or user files.
    $oldManifest = Join-Path $InstallRoot 'install-files.json'
    if (Test-ZhidaoOrdinaryFile $oldManifest) {
        try {
            $parsed = ConvertFrom-Json -InputObject (
                Get-Content -LiteralPath $oldManifest -Raw -Encoding UTF8 -ErrorAction Stop
            ) -ErrorAction Stop
            if ($parsed -is [array] -and $parsed -contains 'ZhidaoAssistant.exe' -and
                $parsed -contains 'install-files.json') {
                foreach ($name in $parsed) {
                    if ($name -isnot [string]) { continue }
                    # Only known app-code prefixes & extensions; not data,
                    # logs, installation backups, folders or symlinks.
                    if ($name -cmatch '^(?:Zhidao[A-Za-z0-9_.-]*|ZHS[A-Za-z0-9_.-]*|Heartbeat[A-Za-z0-9_.-]*|Official[A-Za-z0-9_.-]*|Install[A-Za-z0-9_.-]*|Uninstall|SessionState|CookieImport|AppLifecycle|Verify-Environment|Windows-Preflight|Patch-ZHS[A-Za-z0-9_.-]*)\.(?:ps1|cmd|py|js|xaml|exe)$') {
                        [void]$retired.Add($name)
                    }
                }
            }
        } catch {
            Write-Warning 'Legacy package manifest could not be parsed. Only explicitly known legacy scripts will be removed.'
        }
    }

    $now = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $CurrentFiles) { [void]$now.Add($name) }
    $found = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $retired) {
        if ($now.Contains($name)) { continue }
        $file = Join-Path $InstallRoot $name
        if (-not (Test-ZhidaoPathInsideRoot $file $InstallRoot)) { continue }
        if (Test-ZhidaoOrdinaryFile $file) { [void]$found.Add($name) }
    }
    return ,($found.ToArray())
}

function Clear-ZhidaoStaleMonitorFiles {
    param([Parameter(Mandatory=$true)][string]$InstallRoot)
    if (-not (Test-ZhidaoOrdinaryDirectory $InstallRoot)) { return 0 }
    $count = 0
    foreach ($entry in (Get-ChildItem -LiteralPath $InstallRoot -File -Force -ErrorAction Stop)) {
        if ($entry.Name -cnotmatch '^monitor-(?:(?:playback|zhs)-[0-9a-f]{32}\.json|(?:write|old)-[0-9a-f]{32}\.(?:tmp|bak))$') { continue }
        if (-not (Test-ZhidaoOrdinaryFile $entry.FullName)) { continue }
        Remove-Item -LiteralPath $entry.FullName -Force -ErrorAction Stop
        $count++
    }
    return $count
}

function Clear-ZhidaoOldSetupTemp {
    param(
        [Parameter(Mandatory=$true)][string]$TempRoot,
        [string]$ActiveSetupDir = '',
        [int]$MinimumAgeHours = 24
    )
    if (-not (Test-ZhidaoOrdinaryDirectory $TempRoot)) { return 0 }
    if ($MinimumAgeHours -lt 1) { throw 'Cleanup retention must be at least one hour.' }
    $count = 0
    $cutoff = (Get-Date).AddHours(-$MinimumAgeHours)
    $base = [IO.Path]::GetFullPath($TempRoot).TrimEnd('\')
    $active = if ($ActiveSetupDir) { [IO.Path]::GetFullPath($ActiveSetupDir).TrimEnd('\') } else { '' }
    foreach ($entry in (Get-ChildItem -LiteralPath $TempRoot -Force -ErrorAction Stop)) {
        $name = [string]$entry.Name
        if ($name -cnotmatch '^(?:zhidao-setup-[0-9]{6,16}|zhidao-app-(?:stage|backup)-[0-9a-f]{32}|zhidao-uv-[0-9a-f]{32}(?:\.(?:zip|whl))?)$') { continue }
        $full = [IO.Path]::GetFullPath($entry.FullName).TrimEnd('\')
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($full),$base,[StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($active -and [string]::Equals($full,$active,[StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($entry.LastWriteTime -ge $cutoff) { continue }
        if ([bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        if (-not ($entry.PSIsContainer -or $entry -is [IO.FileInfo])) { continue }
        # Only these exact app-owned temp names; no wildcard directory deletion.
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
        $count++
    }
    return $count
}

function Clear-ZhidaoLegacyShortcuts {
    param(
        [Parameter(Mandatory=$true)][string]$InstallRoot,
        [string[]]$ShortcutDirectories = @(
            [Environment]::GetFolderPath('Desktop'),
            (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs')
        ),
        [switch]$IncludePrimaryShortcut
    )
    $names = @('ZHS Desktop.lnk','Zhidao Desktop.lnk','知到助手.lnk','知到学习助手 Beta.lnk')
    if ($IncludePrimaryShortcut) { $names += '知到学习助手.lnk' }
    $targets = @(
        (Join-Path $InstallRoot 'ZhidaoAssistant.exe'),
        (Join-Path $InstallRoot 'ZHSDesktop.exe')
    )
    $count = 0
    $shell = New-Object -ComObject WScript.Shell
    foreach ($folder in $ShortcutDirectories) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        foreach ($name in $names) {
            $link = Join-Path $folder $name
            if (-not (Test-ZhidaoOrdinaryFile $link)) { continue }
            try {
                $destination = [string]$shell.CreateShortcut($link).TargetPath
                $matches = $false
                foreach ($expected in $targets) {
                    if ([string]::Equals([IO.Path]::GetFullPath($destination),
                        [IO.Path]::GetFullPath($expected),
                        [StringComparison]::OrdinalIgnoreCase)) {
                        $matches = $true
                    }
                }
                if (-not $matches) { continue }
                Remove-Item -LiteralPath $link -Force -ErrorAction Stop
                $count++
            } catch {
                Write-Warning ('Could not remove an old app shortcut: ' + $name)
            }
        }
    }
    return $count
}

function Clear-ZhidaoLegacyRegistry {
    param(
        [Parameter(Mandatory=$true)][string]$InstallRoot,
        [string]$UninstallRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        [switch]$IncludePrimaryKey
    )
    # Never touch HKLM or a registration whose InstallLocation is not ours.
    $keys = @('ZHSDesktop','ZhidaoDesktop','ZhidaoAssistantV5')
    if ($IncludePrimaryKey) { $keys += 'ZhidaoAssistant' }
    $count = 0
    foreach ($name in $keys) {
        $key = Join-Path $UninstallRoot $name
        if (-not (Test-Path -LiteralPath $key)) { continue }
        try {
            $value = Get-ItemProperty -LiteralPath $key -Name InstallLocation -ErrorAction Stop
            $location = [string]$value.InstallLocation
            if (-not [string]::Equals([IO.Path]::GetFullPath($location).TrimEnd('\'),
                [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\'),
                [StringComparison]::OrdinalIgnoreCase)) { continue }
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
            $count++
        } catch {
            Write-Warning ('Could not remove a legacy app registration: ' + $name)
        }
    }
    return $count
}
