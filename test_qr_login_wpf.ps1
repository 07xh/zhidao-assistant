# Windows PowerShell 5.1 tests: only sanitized QR lifecycle state reaches WPF.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
$script:root = Join-Path ([IO.Path]::GetTempPath()) ('zhidao-qr-wpf-' + [Guid]::NewGuid().ToString('N'))
New-Item -Path $script:root -ItemType Directory -Force | Out-Null
try {
    $script:window = [Windows.Markup.XamlReader]::Parse(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload\Zhidao-UI.xaml') -Raw -Encoding UTF8))
    function Control([string]$name) {
        $found = $script:window.FindName($name)
        if ($null -eq $found) { throw ('QR WPF control missing: ' + $name) }
        return $found
    }
    $script:activeQrToken = [Guid]::NewGuid().ToString('N')
    $script:lastQrStatus = ''
    $script:qrStartedAt = Get-Date
    $script:qrPath = Join-Path $script:root 'qrcode.png'
    $script:qrViewer = $null
    . (Join-Path $PSScriptRoot 'payload\QrLoginView.ps1')
    Update-ZhidaoQrView
    if ((Control 'QrLoginStateText').Text -notmatch '尚未开始') {
        throw 'Unobserved QR status was invented'
    }
    $file = Join-Path $script:root ('monitor-qr-' + $script:activeQrToken + '.json')
    $state = @{v=1;token=$script:activeQrToken;stage='ready';
        at=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
    [IO.File]::WriteAllText($file,($state | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    Update-ZhidaoQrView
    if ((Control 'QrLoginStateText').Text -notmatch '新二维码已生成') {
        throw 'Current fresh QR status was not displayed'
    }
    $state.stage = 'confirming'
    [IO.File]::WriteAllText($file,($state | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    Update-ZhidaoQrView
    if ((Control 'QrLoginStateText').Text -notmatch 'CAS 服务器会话') {
        throw 'QR confirmation was confused with login success'
    }
    $state.token = ('f' * 32)
    [IO.File]::WriteAllText($file,($state | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    if ($null -ne (Get-ZhidaoQrObservation $script:activeQrToken)) {
        throw 'Cross-session QR status was accepted'
    }
    $state.token = $script:activeQrToken
    $state.stage = 'verified'
    $state.at = [DateTimeOffset]::UtcNow.AddMinutes(-20).ToUnixTimeSeconds()
    [IO.File]::WriteAllText($file,($state | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    if ($null -ne (Get-ZhidaoQrObservation $script:activeQrToken)) {
        throw 'Expired QR authentication status was shown as current'
    }
    $script:lastQrStatus = 'unavailable'
    $script:activeQrToken = ''
    Update-ZhidaoQrView
    if ((Control 'QrLoginStateText').Text -notmatch '认证服务器暂不可用') {
        throw 'Offline authentication incorrectly appeared verified'
    }
    Write-Host 'QR login WPF stage labels and token/time isolation passed.'
} finally {
    Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
}
