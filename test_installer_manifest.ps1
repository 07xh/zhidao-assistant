# Windows PowerShell 5.1 regression: parse the exact installer manifest loader
# without executing dependency downloads, app process shutdown or installation.
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'payload\Install.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Install.ps1 syntax failed' }
$definitions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Read-InstallerResourceManifest'
}, $true))
if ($definitions.Count -ne 1) { throw 'Expected exactly one production installer manifest reader' }
Invoke-Expression $definitions[0].Extent.Text

$realManifest = Join-Path $PSScriptRoot 'payload\install-files.json'
$realNames = @(Read-InstallerResourceManifest $realManifest)
if ($realNames.Count -lt 25 -or $realNames -notcontains 'ZhidaoAssistant.exe' -or
    $realNames -notcontains 'install-files.json' -or
    $realNames -notcontains 'ZHS-ConsoleMonitor.py' -or
    $realNames -notcontains 'HeartbeatMonitor.ps1') {
    throw ('Real installer manifest incorrectly parsed: count=' + $realNames.Count)
}
foreach ($name in $realNames) {
    if ($name -isnot [string]) { throw 'Nested JSON array returned instead of file names' }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('zhidao-manifest-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $file = Join-Path $root 'test.json'
    [IO.File]::WriteAllText($file, ('["ZhidaoAssistant.exe","install-files.json","READ ME.txt"]'), [Text.UTF8Encoding]::new($false))
    $names = @(Read-InstallerResourceManifest $file)
    if ($names.Count -ne 3 -or $names -notcontains 'READ ME.txt') {
        throw 'Valid three-file manifest failed'
    }
    $invalidCases = @(
        '[]',
        '{}',
        '"ZhidaoAssistant.exe"',
        '["ZhidaoAssistant.exe"]',
        '["ZhidaoAssistant.exe","install-files.json","README","readme"]',
        '["ZhidaoAssistant.exe","install-files.json","../bad"]',
        '["ZhidaoAssistant.exe","install-files.json","a/b"]',
        '["ZhidaoAssistant.exe","install-files.json",null]',
        '["ZhidaoAssistant.exe","install-files.json",1]',
        '[["ZhidaoAssistant.exe","install-files.json"]]'
    )
    foreach ($bad in $invalidCases) {
        [IO.File]::WriteAllText($file, $bad, [Text.UTF8Encoding]::new($false))
        $rejected = $false
        try { $null = Read-InstallerResourceManifest $file } catch { $rejected = $true }
        if (-not $rejected) { throw ('Malformed manifest accepted: ' + $bad) }
    }
    Write-Host ('Windows PowerShell 5.1 installer manifest passed (' + $realNames.Count + ' real resources).')
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
