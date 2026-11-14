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
    # Browser Cookie request header text is parsed locally, not sent to any new service.
    $typed = Convert-ZhidaoCookieText 'Cookie: CASLOGC=fake%3Dvalue; other=fake=='
    $parsed = @(ConvertFrom-Json -InputObject $typed)
    Write-Host ('Synthetic parse debug: count={0}, firstName={1}, firstValueMatch={2}, secondValueMatch={3}, firstDomain={4}' -f $parsed.Count, [string]$parsed[0].name, ([string]$parsed[0].value -ceq 'fake%3Dvalue'), ([string]$parsed[1].value -ceq 'fake=='), [string]$parsed[0].domain)
    if ($parsed.Count -ne 2 -or $parsed[0].name -ne 'CASLOGC' -or
        $parsed[0].value -ne 'fake%3Dvalue' -or $parsed[1].value -ne 'fake==' -or
        $parsed[0].domain -ne '.zhihuishu.com') {
        throw 'Direct input parse failed'
    }
    $typedJson = Convert-ZhidaoCookieText $candidate
    if ($typedJson -ne $normalized) { throw 'Direct ZHS JSON paste differs from file import' }

    foreach ($badText in @(
        'Cookie: CASLOGC=fake; CASLOGC=second',
        'Cookie: CASLOGC',
        'Cookie: a=b;; c=d',
        "Cookie: a=b`r`nX-Header: injected",
        'Cookie: =empty',
        'Cookie: good=ok;badname',
        ''
    )) {
        $rejected = $false
        try { $null = Convert-ZhidaoCookieText $badText } catch { $rejected = $true }
        if (-not $rejected) { throw 'Invalid direct input accepted' }
    }
    # The text import uses exactly the same transaction and rollback as file import.
    Begin-ZhidaoCookieImport $typed
    $rollbackMessage = Complete-ZhidaoCookieImport 4
    if ([IO.File]::ReadAllText($script:cookiePath) -ne $normalized -or
        $rollbackMessage -notmatch '恢复') { throw 'Direct input did not roll back' }
    Write-Host 'Direct Cookie input parsing and rollback passed (synthetic values).'
    Write-Host 'Cookie import parsing, account scope, rollback and verified commit passed.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
