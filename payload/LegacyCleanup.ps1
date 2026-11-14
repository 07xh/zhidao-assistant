# SPDX-License-Identifier: GPL-3.0-only
# Upgrade/uninstall cleanup of *owned* Zhidao Assistant paths only.
# Never use recursive wildcards outside the exact app root.
function Assert-ZhidaoOwnedRoot {
    param([Parameter(Mandatory=$true)][string]$InstallRoot)
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is unavailable; refusing destructive cleanup.'
    }
    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ZHSDesktop')).TrimEnd('\','/')
    $actual = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/')
    if (-not [string]::Equals($actual,$expected,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing cleanup outside the owned ZHSDesktop install directory.'
    }
    if (Test-Path -LiteralPath $actual) {
        $entry = Get-Item -LiteralPath $actual -Force -ErrorAction Stop
        if (-not $entry.PSIsContainer -or
            ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'App install path is not a normal directory; refusing cleanup.'
        }
    }
    return $actual
}

function Assert-ZhidaoNoReparseTree {
    param([Parameter(Mandatory=$true)][string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return }
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Directory)
    $checked = 0
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
            $checked++
            if ($checked -gt 200000) {
                throw 'Too many files under application path; refusing recursive cleanup.'
            }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw ('Reparse point found in app-owned path; safe cleanup refused: ' + $item.FullName)
            }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
}

function Remove-ZhidaoOldAppResidue {
    param([Parameter(Mandatory=$true)][string]$InstallRoot)
    $root = Assert-ZhidaoOwnedRoot -InstallRoot $InstallRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return 0 }
    # A tightly reviewed legacy allowlist, never a directory wildcard or a
    # user-provided/old install-files.json (which is not a trusted delete list).
    $obsolete = @('ZHS-GUI.ps1','ZHS-CLI.cmd')
    $count = 0
    foreach ($name in $obsolete) {
        $file = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $item = Get-Item -LiteralPath $file -Force -ErrorAction Stop
        if ($item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Write-Warning ('Obsolete path not a normal file; left unchanged: ' + $name)
            continue
        }
        Remove-Item -LiteralPath $file -Force -ErrorAction Stop
        $count++
    }
    # Crashed player/monitor snapshots are cache, not official progress or
    # account data. Never delete a fresh live session's observations.
    foreach ($item in @(Get-ChildItem -LiteralPath $root -File -Force -ErrorAction Stop)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $name = $item.Name
        $orphan = (
            $name -cmatch '^monitor-(zhs|playback|qr)-[0-9a-f]{32}\.json$' -or
            $name -cmatch '^monitor-(write|old)-[0-9a-f]{32}\.(tmp|bak)$' -or
            $name -ceq 'pending-verify.json.tmp'
        )
        if (-not $orphan -or $item.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddDays(-2)) { continue }
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
        $count++
    }
    return $count
}

function Clear-ZhidaoInstallerTempResidue {
    param([string]$TempRoot = $env:TEMP, [int]$OlderThanDays = 7)
    if ($OlderThanDays -lt 1 -or $OlderThanDays -gt 365) {
        throw 'Invalid installer temporary-file retention threshold.'
    }
    if ([string]::IsNullOrWhiteSpace($TempRoot) -or
        -not (Test-Path -LiteralPath $TempRoot -PathType Container)) { return 0 }
    # Exact direct children of TEMP only; do not traverse other user folders.
    $base = [IO.Path]::GetFullPath($TempRoot).TrimEnd('\','/')
    $cutoff = [DateTime]::UtcNow.AddDays(-$OlderThanDays)
    $removed = 0
    foreach ($item in @(Get-ChildItem -LiteralPath $base -Force -ErrorAction Stop)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($item.LastWriteTimeUtc -gt $cutoff) { continue }
        $name = $item.Name
        $valid = (
            $name -cmatch '^zhidao-(setup|app-stage|app-backup)-[A-Za-z0-9-]{6,}$' -or
            $name -cmatch '^zhidao-uv-[0-9a-f]{32}(\.whl)?$' -or
            $name -cmatch '^zhidao-installer-build-[A-Za-z0-9_-]{6,}$'
        )
        if (-not $valid) { continue }
        try {
            if ($item.PSIsContainer) {
                Assert-ZhidaoNoReparseTree -Directory $item.FullName
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
            }
            $removed++
        } catch {
            Write-Warning ('Could not safely remove old setup residue ' + $name + ': ' + $_.Exception.Message)
        }
    }
    return $removed
}
