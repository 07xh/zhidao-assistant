# Offline Windows PowerShell 5.1 regression for safe old-version removal.
# All app folders, temp folders, shortcuts and registry keys are test fixtures.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'payload\LegacyCleanup.ps1')
$testBase = Join-Path ([IO.Path]::GetTempPath()) ('zhidao-clean-test-' + [Guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $testBase 'ZHSDesktop'
$tempRoot = Join-Path $testBase 'temp'
$desktop = Join-Path $testBase 'desktop'
$menu = Join-Path $testBase 'menu'
$foreign = Join-Path $testBase 'AnotherProgram'
$registryRoot = 'HKCU:\Software\ZhidaoCleanupTest-' + [Guid]::NewGuid().ToString('N')
$uninstallRoot = Join-Path $registryRoot 'Uninstall'
foreach ($dir in @($installRoot,$tempRoot,$desktop,$menu,$foreign)) {
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
}
try {
    foreach ($name in @('ZhidaoAssistant.exe','ZHS-GUI.ps1','ZHS-CLI.cmd',
                        'Zhidao-OldUI.ps1','Zhidao-MyNotes.txt','my-homework.txt',
                        'Zhidao-GUI.ps1')) {
        [IO.File]::WriteAllText((Join-Path $installRoot $name),'fixture')
    }
    $previousManifest = '["ZhidaoAssistant.exe","install-files.json","ZHS-GUI.ps1","ZHS-CLI.cmd","Zhidao-OldUI.ps1","Zhidao-MyNotes.txt","Zhidao-GUI.ps1"]'
    [IO.File]::WriteAllText((Join-Path $installRoot 'install-files.json'),
        $previousManifest,[Text.UTF8Encoding]::new($false))
    New-Item -ItemType Directory -Path (Join-Path $installRoot '.venv') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $installRoot '.venv\user.txt'),'private runtime fixture')
    $live = @('ZhidaoAssistant.exe','Zhidao-GUI.ps1','install-files.json','LegacyCleanup.ps1')
    $old = Get-ZhidaoRetiredFiles -InstallRoot $installRoot -CurrentFiles $live
    if ($old -isnot [array] -or $old.Count -ne 3) {
        throw ('Unexpected obsolete filename set: ' + ($old -join ','))
    }
    foreach ($item in @('ZHS-GUI.ps1','ZHS-CLI.cmd','Zhidao-OldUI.ps1')) {
        if ($old -notcontains $item) { throw ('Old release file not detected: ' + $item) }
    }
    foreach ($item in @('Zhidao-GUI.ps1','ZhidaoAssistant.exe','Zhidao-MyNotes.txt','my-homework.txt')) {
        if ($old -contains $item) { throw ('Current or user file marked for deletion: ' + $item) }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot '.venv\user.txt'))) {
        throw 'Python venv was unexpectedly touched'
    }

    $token = ('a' * 32)
    $monitor = Join-Path $installRoot ('monitor-zhs-' + $token + '.json')
    $other = Join-Path $installRoot 'monitor-export-notes.json'
    [IO.File]::WriteAllText($monitor,'{}')
    [IO.File]::WriteAllText($other,'user log should remain')
    if ((Clear-ZhidaoStaleMonitorFiles -InstallRoot $installRoot) -ne 1) {
        throw 'Known session-bound monitor residue not removed'
    }
    if ((Test-Path -LiteralPath $monitor) -or -not (Test-Path -LiteralPath $other)) {
        throw 'Monitor garbage collection exceeded its exact-name scope'
    }

    $oldSetup = Join-Path $tempRoot 'zhidao-setup-1753729713'
    $activeSetup = Join-Path $tempRoot 'zhidao-setup-1753729714'
    $oldBackup = Join-Path $tempRoot ('zhidao-app-backup-' + ('b'*32))
    $unrelated = Join-Path $tempRoot 'my-project-setup-1753729713'
    foreach ($dir in @($oldSetup,$activeSetup,$oldBackup,$unrelated)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'fixture.txt'),'data')
        (Get-Item -LiteralPath $dir).LastWriteTime = (Get-Date).AddDays(-8)
    }
    $removed = Clear-ZhidaoOldSetupTemp -TempRoot $tempRoot -ActiveSetupDir $activeSetup -MinimumAgeHours 24
    if ($removed -ne 2 -or (Test-Path -LiteralPath $oldSetup) -or
        (Test-Path -LiteralPath $oldBackup) -or
        -not (Test-Path -LiteralPath $activeSetup) -or
        -not (Test-Path -LiteralPath $unrelated)) {
        throw 'Temp cleanup leaked into active installer or other folders'
    }

    # Delete only shortcuts that resolve to this application's exact launcher.
    $shell = New-Object -ComObject WScript.Shell
    $ownedLink = Join-Path $desktop 'ZHS Desktop.lnk'
    $otherLink = Join-Path $desktop 'Zhidao Desktop.lnk'
    $shortcut = $shell.CreateShortcut($ownedLink)
    $shortcut.TargetPath = Join-Path $installRoot 'ZhidaoAssistant.exe'
    $shortcut.Save()
    [IO.File]::WriteAllText((Join-Path $foreign 'ZhidaoAssistant.exe'),'other executable fixture')
    $shortcut = $shell.CreateShortcut($otherLink)
    $shortcut.TargetPath = Join-Path $foreign 'ZhidaoAssistant.exe'
    $shortcut.Save()
    $gone = Clear-ZhidaoLegacyShortcuts -InstallRoot $installRoot -ShortcutDirectories @($desktop,$menu) -IncludePrimaryShortcut
    if ($gone -ne 1 -or (Test-Path -LiteralPath $ownedLink) -or
        -not (Test-Path -LiteralPath $otherLink)) {
        throw 'Shortcut deletion did not validate app ownership'
    }

    # Registry fixture under private test key; never touches real uninstall keys.
    New-Item -Path $uninstallRoot -Force | Out-Null
    $ours = Join-Path $uninstallRoot 'ZHSDesktop'
    $theirs = Join-Path $uninstallRoot 'ZhidaoAssistant'
    New-Item -Path $ours -Force | Out-Null
    New-Item -Path $theirs -Force | Out-Null
    New-ItemProperty -Path $ours -Name InstallLocation -Value $installRoot -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $theirs -Name InstallLocation -Value $foreign -PropertyType String -Force | Out-Null
    $removedRegs = Clear-ZhidaoLegacyRegistry -InstallRoot $installRoot -UninstallRoot $uninstallRoot -IncludePrimaryKey
    if ($removedRegs -ne 1 -or (Test-Path $ours) -or -not (Test-Path $theirs)) {
        throw 'Registry cleanup did not verify installation location'
    }
    $installScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload\Install.ps1') -Raw -Encoding UTF8
    if ($installScript -notmatch 'retiredFiles' -or $installScript -notmatch 'pruned.Count' -or
        $installScript -notmatch 'Clear-ZhidaoOldSetupTemp' -or
        $installScript -notmatch 'Legacy rollback integrity failure') {
        throw 'Installer no longer stages retired files for rollback'
    }
    Write-Host 'PASS: legacy clean-up scopes, path ownership, rollback hooks and private data preservation'
} finally {
    if (Test-Path $registryRoot) { Remove-Item -Path $registryRoot -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $testBase) { Remove-Item -LiteralPath $testBase -Recurse -Force -ErrorAction SilentlyContinue }
}
