# Windows PowerShell 5.1 regression: JSON array MUST remain a flat string[].
# No network, ZHS, login, install, or external processes.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'payload\InstallerManifest.ps1')
$manifestFile = Join-Path $PSScriptRoot 'payload\install-files.json'
$names = Read-ZhidaoInstallerManifest $manifestFile
if ($names -isnot [array] -or $names.Count -lt 20) { throw 'Manifest was not returned as a flat array' }
if ($names -notcontains 'ZhidaoAssistant.exe' -or
    $names -notcontains 'install-files.json' -or
    $names -notcontains 'InstallerManifest.ps1') {
    throw 'PowerShell 5.1 manifest lost required entries'
}
foreach ($n in $names) {
    if ($n -isnot [string]) { throw 'Nested array or non-string in parsed manifest' }
    if ($n -ne 'ZhidaoAssistant.exe' -and
        -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot ('payload\' + $n)) -PathType Leaf)) {
        throw ('Manifest entry absent from staged source payload: ' + $n)
    }
}
# Show why the original code was unsafe on this runner without relying on its result.
$legacy = @(Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json)
Write-Host ("Legacy pipeline items: {0}; repaired items: {1}" -f $legacy.Count,$names.Count)
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('zhidao-manifest-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $file = Join-Path $tmp 'manifest.json'
    $bad = @(
        '{}',
        '[["ZhidaoAssistant.exe","install-files.json","InstallerManifest.ps1"]]',
        '["ZhidaoAssistant.exe","install-files.json"]',
        '["ZhidaoAssistant.exe","install-files.json","InstallerManifest.ps1","INSTALLERMANIFEST.ps1"]',
        '["ZhidaoAssistant.exe","install-files.json","InstallerManifest.ps1","../escape"]',
        '["ZhidaoAssistant.exe","install-files.json","InstallerManifest.ps1",5]',
        'not valid json'
    )
    foreach ($sample in $bad) {
        [IO.File]::WriteAllText($file,$sample,[Text.UTF8Encoding]::new($false))
        $rejected = $false
        try { $unused = Read-ZhidaoInstallerManifest $file }
        catch { $rejected = $true }
        if (-not $rejected) { throw ('Invalid manifest accepted: ' + $sample) }
    }
    Write-Host 'Installer manifest flat-array, inclusion, and malformed-document checks passed.'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
