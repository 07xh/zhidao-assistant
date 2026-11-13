# SPDX-License-Identifier: GPL-3.0-only
# Installs Microsoft WebView2 WPF SDK assemblies from a pinned official NuGet package.
# The WebView2 Runtime itself is supplied/updated by Microsoft on Windows.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'
$dst = Join-Path $root 'webview2'
$version = '1.0.4191.47'
$address = 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/' + $version + '/microsoft.web.webview2.' + $version + '.nupkg'
$needed = @{
    'lib/net462/Microsoft.Web.WebView2.Core.dll' = 'Microsoft.Web.WebView2.Core.dll'
    'lib/net462/Microsoft.Web.WebView2.Wpf.dll' = 'Microsoft.Web.WebView2.Wpf.dll'
    'runtimes/win-x64/native/WebView2Loader.dll' = 'runtimes/win-x64/native/WebView2Loader.dll'
}
if ((Test-Path (Join-Path $dst 'Microsoft.Web.WebView2.Core.dll')) -and
    (Test-Path (Join-Path $dst 'Microsoft.Web.WebView2.Wpf.dll')) -and
    (Test-Path (Join-Path $dst 'runtimes/win-x64/native/WebView2Loader.dll'))) {
    Write-Host 'WebView2 SDK assemblies already present.'
    return
}
$temp = Join-Path $env:TEMP ('zhidao-webview2-' + [Guid]::NewGuid().ToString('N')+'.nupkg')
$stage = Join-Path $env:TEMP ('zhidao-webview2-stage-' + [Guid]::NewGuid().ToString('N'))
try {
    Write-Host '[Optional] Downloading WebView2 SDK from api.nuget.org... (progress visible when server reports size)'
    $ProgressPreference = 'Continue'
    try { Invoke-WebRequest -Uri $address -UseBasicParsing -OutFile $temp -TimeoutSec 180 } catch { throw ('WebView2 SDK download from api.nuget.org failed: ' + $_.Exception.Message) }
    # NuGet flat-container exposes official package SHA512 as a Base64 string.
    $checkUrl = $address + '.sha512'
    $expectedSha512 = ([string](Invoke-WebRequest -Uri $checkUrl -UseBasicParsing -TimeoutSec 45).Content).Trim()
    $reader = [System.IO.File]::OpenRead($temp)
    try {
        $sha = [System.Security.Cryptography.SHA512]::Create()
        try { $actualSha512 = [Convert]::ToBase64String($sha.ComputeHash($reader)) }
        finally { $sha.Dispose() }
    } finally { $reader.Dispose() }
    if ($actualSha512 -cne $expectedSha512) { throw 'WebView2 NuGet SHA512 verification failed; SDK installation aborted.' }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($temp)
    try {
        foreach ($src in $needed.Keys) {
            $entry = $zip.GetEntry($src)
            if ($null -eq $entry) { throw ('Missing required NuGet entry: ' + $src) }
            $path = Join-Path $stage $needed[$src]
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            $reader = $entry.Open()
            try {
                $writer = [System.IO.File]::Open($path,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write)
                try { $reader.CopyTo($writer) } finally { $writer.Close() }
            } finally { $reader.Close() }
        }
    } finally { $zip.Dispose() }
    foreach ($relative in $needed.Values) {
        $from = Join-Path $stage $relative
        if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { throw ('Missing staged WebView2 SDK component: ' + $relative) }
        $to = Join-Path $dst $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
        Copy-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop
    }
    Write-Host 'Microsoft WebView2 SDK files installed.'
} finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
