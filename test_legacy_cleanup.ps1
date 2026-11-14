# Offline Windows PowerShell 5.1 filesystem-scope regression.
# Does not call Uninstall.ps1, touch real account data or modify registry.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'payload\LegacyCleanup.ps1')
$previousLocal = $env:LOCALAPPDATA
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('zhidao-cleanup-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
try {
    $env:LOCALAPPDATA = Join-Path $fixture 'Local'
    $root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'
    $temp = Join-Path $fixture 'FakeTemp'
    $other = Join-Path $env:LOCALAPPDATA 'OtherApp'
    foreach ($dir in @($root,$temp,$other,(Join-Path $root '.venv'))) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $root 'ZHS-GUI.ps1'), 'obsolete')
    [IO.File]::WriteAllText((Join-Path $root 'ZHS-CLI.cmd'), 'obsolete')
    [IO.File]::WriteAllText((Join-Path $root 'cookies.json'), 'app-owned fake data')
    [IO.File]::WriteAllText((Join-Path $root 'unlisted-user-notes.txt'), 'keep')
    [IO.File]::WriteAllText((Join-Path $root '.venv\python.exe'), 'keep')
    [IO.File]::WriteAllText((Join-Path $other 'ZHS-GUI.ps1'), 'other user application')
    $oldMonitor = Join-Path $root ('monitor-zhs-' + ('a' * 32) + '.json')
    $freshMonitor = Join-Path $root ('monitor-zhs-' + ('b' * 32) + '.json')
    $oldQRStatus = Join-Path $root ('monitor-qr-' + ('c' * 32) + '.json')
    [IO.File]::WriteAllText($oldMonitor, '{}')
    [IO.File]::WriteAllText($freshMonitor, '{}')
    [IO.File]::WriteAllText($oldQRStatus, '{}')
    (Get-Item $oldMonitor).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-10)
    (Get-Item $oldQRStatus).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-10)

    $n = Remove-ZhidaoOldAppResidue -InstallRoot $root
    if ($n -ne 4) { throw ('Wrong obsolete cleanup count: ' + $n) }
    foreach ($file in @('ZHS-GUI.ps1','ZHS-CLI.cmd')) {
        if (Test-Path -LiteralPath (Join-Path $root $file)) { throw ('Obsolete file retained: ' + $file) }
    }
    foreach ($file in @('cookies.json','unlisted-user-notes.txt','.venv\python.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $file))) {
            throw ('User data or runtime deleted during upgrade: ' + $file)
        }
    }
    if (Test-Path $oldMonitor -or Test-Path $oldQRStatus) { throw 'Expired monitor or QR status file was not cleaned' }
    if (-not (Test-Path $freshMonitor)) { throw 'Fresh active monitor file was removed' }
    if (-not (Test-Path (Join-Path $other 'ZHS-GUI.ps1'))) { throw 'Different app was modified' }

    $blocked = $false
    try { $null = Remove-ZhidaoOldAppResidue -InstallRoot $other }
    catch { $blocked = $true }
    if (-not $blocked) { throw 'Outside owned app root cleanup was accepted' }

    $oldSetup = Join-Path $temp 'zhidao-setup-1753729713'
    $oldBackup = Join-Path $temp ('zhidao-app-backup-' + ('c' * 32))
    $freshSetup = Join-Path $temp 'zhidao-setup-9876543210'
    $unrelated = Join-Path $temp 'otherapp-setup-1753729713'
    foreach ($dir in @($oldSetup,$oldBackup,$freshSetup,$unrelated)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'fixture.txt'), 'test only')
    }
    foreach ($oldDir in @($oldSetup,$oldBackup,$unrelated)) {
        (Get-Item $oldDir).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-12)
    }
    $removed = Clear-ZhidaoInstallerTempResidue -TempRoot $temp -OlderThanDays 7
    if ($removed -ne 2) { throw ('Wrong app-owned TEMP residue count: ' + $removed) }
    foreach ($path in @($oldSetup,$oldBackup)) {
        if (Test-Path $path) { throw ('Old installer residue retained: ' + $path) }
    }
    foreach ($path in @($freshSetup,$unrelated)) {
        if (-not (Test-Path $path)) { throw ('Fresh or unrelated folder removed: ' + $path) }
    }
    Write-Host 'Safe legacy cleanup: owned root, runtime retention, stale temp and cross-app isolation passed.'
} finally {
    $env:LOCALAPPDATA = $previousLocal
    Remove-Item -LiteralPath $fixture -Force -Recurse -ErrorAction SilentlyContinue
}
