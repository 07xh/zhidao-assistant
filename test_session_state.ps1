# Offline PowerShell 5.1 regression: session state must not survive cookie rotation.
# This uses temporary fake data; no real account, network, WPF window or heartbeat.
$ErrorActionPreference = 'Stop'
$directory = Join-Path $env:TEMP ('zhidao-session-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory -Force | Out-Null
try {
    $script:cookiePath = Join-Path $directory 'cookies.json'
    $script:loginProbeState = ''
    $script:loginProbeCookieDigest = ''
    $script:loginProbeCheckedAt = $null
    $script:label = [pscustomobject]@{ Text = '' }
    function Control([string]$name) {
        if ($name -ne 'LoginStateText') { throw 'Unexpected fake control name' }
        return $script:label
    }
    . (Join-Path $PSScriptRoot 'payload/SessionState.ps1')
    Update-LoginState
    if ($script:label.Text -ne '尚无可验证的本地登录凭证') { throw 'Missing cookie must not look verified' }
    [System.IO.File]::WriteAllText($script:cookiePath, 'FAKE_LOGIN_1', [System.Text.Encoding]::UTF8)
    Update-LoginState
    if ($script:label.Text -notlike '*尚未验证服务器登录*') { throw 'Presence alone must not confirm server session' }
    $script:loginProbeCookieDigest = Get-CookieDigest
    $script:loginProbeState = 'confirmed'
    $script:loginProbeCheckedAt = Get-Date
    Update-LoginState
    if ($script:label.Text -notlike '*服务端登录已验证*') { throw 'Verified state display missing' }
    [System.IO.File]::WriteAllText($script:cookiePath, 'FAKE_LOGIN_2', [System.Text.Encoding]::UTF8)
    Update-LoginState
    if ($script:loginProbeState -ne '') { throw 'Old verification must be reset after account rotation' }
    if ($script:loginProbeCookieDigest -ne '') { throw 'Old session digest must be reset' }
    if ($script:label.Text -notlike '*尚未验证服务器登录*') { throw 'Rotated account must not inherit verified label' }
    Remove-Item -LiteralPath $script:cookiePath -Force
    Update-LoginState
    if ($script:label.Text -ne '尚无可验证的本地登录凭证') { throw 'Logged out account must show missing cookie' }
    Write-Host 'PASS: offline Windows session state transitions and cookie rotation'
} finally {
    Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
}
