# SPDX-License-Identifier: GPL-3.0-only
# Safe local diagnostic: only booleans and app version; no filenames, cookies, IDs, or URL values exported.
param([switch]$SaveReport)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'
$py = Join-Path $root '.venv\Scripts\python.exe'
$required = @('Zhidao-GUI.ps1','Official-Player.ps1','zhidao_only.py','Zhidao-UI.xaml')
$scriptOK = $true
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) { $scriptOK = $false }
}
$pyOK = Test-Path -LiteralPath $py -PathType Leaf
$zhsOK = $false
if ($pyOK) {
    & $py (Join-Path $root 'Verify-Environment.py') *> $null
    $zhsOK = ($LASTEXITCODE -eq 0)
}
$runtimeOK = $false
try {
    $edge = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F1D57A04-6459-4C3D-BC3A-FD81D053AB0A}' -ErrorAction SilentlyContinue
    if ($edge -and $edge.pv) { $runtimeOK = $true }
} catch { }
# Registry is not authoritative on every Windows edition. The player does its own runtime check.
$sdkOK = (Test-Path -LiteralPath (Join-Path $root 'webview2\Microsoft.Web.WebView2.Core.dll')) -and
         (Test-Path -LiteralPath (Join-Path $root 'webview2\Microsoft.Web.WebView2.Wpf.dll')) -and
         (Test-Path -LiteralPath (Join-Path $root 'webview2\runtimes\win-x64\native\WebView2Loader.dll'))
$report = [ordered]@{
    application = 'ZhidaoAssistant'; build = '5.2.7';
    windows64bit = [Environment]::Is64BitOperatingSystem;
    scriptsPresent = $scriptOK; pythonPresent = $pyOK; zhs015Ready = $zhsOK;
    webview2SdkPresent = $sdkOK; webview2RuntimeRegistryHint = $runtimeOK;
    credentialsPresent = Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.zhs\cookies.json');
    note = 'No cookie values, course IDs, session tokens or full file paths are included. A passing preflight does not prove official course playback.'
}
$json = $report | ConvertTo-Json -Depth 3
Write-Host $json
if ($SaveReport) {
    $file = Join-Path ([Environment]::GetFolderPath('Desktop')) 'zhidao-preflight-v526.json'
    [System.IO.File]::WriteAllText($file,$json,[System.Text.Encoding]::UTF8)
    Write-Host 'Diagnostic saved on Desktop; review before sharing.'
}
if (-not ($scriptOK -and $pyOK -and $zhsOK)) { exit 1 }
exit 0
