# Offline Windows PowerShell 5.1 contract tests; only synthetic Cookie strings are used.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'payload\CookieImport.ps1')
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('zhs-cookie-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $script:dataDir = $root
    $script:cookiePath = Join-Path $root 'cookies.json'
    $script:cookieImportActive = $false
    $script:cookieImportExpectedDigest = ''
    $script:cookieImportPreviousBytes = $null
    $script:cookieImportPreviousExists = $false
    function Get-CookieDigest {
        if (-not (Test-Path -LiteralPath $script:cookiePath -PathType Leaf)) { return '' }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($script:cookiePath))).Replace('-', '') }
        finally { $sha.Dispose() }
    }
    $original = '[{"name":"old","value":"old-fake","domain":".zhihuishu.com","path":"/"}]'
    [IO.File]::WriteAllText($script:cookiePath, $original, [Text.UTF8Encoding]::new($false))
    $source = Join-Path $root 'import.json'
    $candidate = '[{"name":"CASLOGC","value":"fake-only","domain":".zhihuishu.com","path":"/"}]'
    [IO.File]::WriteAllText($source, $candidate, [Text.UTF8Encoding]::new($false))
    $normalized = Read-ZhidaoCookieImport $source
    $rows = @(ConvertFrom-Json -InputObject $normalized)
    if ($rows.Count -ne 1 -or $rows[0].name -ne 'CASLOGC') { throw 'Valid cookie normalization failed' }
    Begin-ZhidaoCookieImport $normalized
    if (-not $script:cookieImportActive) { throw 'Import did not begin' }
    if ((Get-Content $script:cookiePath -Raw) -notmatch 'CASLOGC') { throw 'Import did not install candidate' }
    $message = Complete-ZhidaoCookieImport 4
    if ($script:cookieImportActive -or [IO.File]::ReadAllText($script:cookiePath) -ne $original) {
        throw 'Unverified login did not restore original bytes'
    }
    if ($message -notmatch '恢复') { throw 'Rollback status was missing' }

    Begin-ZhidaoCookieImport $normalized
    $message = Complete-ZhidaoCookieImport 6
    if ($script:cookieImportActive -or [IO.File]::ReadAllText($script:cookiePath) -ne $normalized) {
        throw 'Verified SDK login was not retained on partial course API failure'
    }
    if ($message -notmatch '成功') { throw 'Successful import status was missing' }

    $badInputs = @(
        '{"name":"CASLOGC","value":"fake"}',
        '[{"name":"CASLOGC","value":"fake","domain":"example.com"}]',
        '[{"name":"CASLOGC","value":"fake","domain":".zhihuishu.com","path":"/"},{"name":"CASLOGC","value":"other","domain":".zhihuishu.com","path":"/"}]',
        '[{"name":"x","value":17}]',
        '[]'
    )
    foreach ($bad in $badInputs) {
        [IO.File]::WriteAllText($source, $bad, [Text.UTF8Encoding]::new($false))
        $rejected = $false
        try { $null = Read-ZhidaoCookieImport $source } catch { $rejected = $true }
        if (-not $rejected) { throw 'Untrusted cookie shape was accepted' }
    }
    Write-Host 'Cookie import parsing, account scope, rollback and verified commit passed.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
