# Import an existing ZHS 0.1.5 cookies.json from the current user's own account.
# Never log cookie values or send them to a service other than the original ZHS endpoints.
# The caller immediately runs a read-only server diagnosis; any unverified import rolls back.

function Read-ZhidaoCookieImport([string]$SourcePath) {
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw 'NO_FILE' }
    $info = [System.IO.FileInfo]::new($SourcePath)
    if ($info.Length -lt 2 -or $info.Length -gt 262144) { throw 'FILE_SIZE' }
    $decoder = [System.Text.UTF8Encoding]::new($false, $true)
    $raw = [System.IO.File]::ReadAllText($SourcePath, $decoder)
    if (-not $raw.TrimStart().StartsWith('[')) { throw 'NOT_ZHS_JSON' }
    return Convert-ZhidaoCookieJson $raw
}

function Convert-ZhidaoCookieJson([string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Length -gt 262144 -or
        -not $raw.TrimStart().StartsWith('[')) { throw 'INVALID_JSON' }
    try { $rows = @(ConvertFrom-Json -InputObject $raw -ErrorAction Stop) }
    catch { throw 'INVALID_JSON' }
    if ($rows.Count -lt 1 -or $rows.Count -gt 250) { throw 'COOKIE_COUNT' }
    $items = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($row in $rows) {
        if ($null -eq $row -or $row -isnot [pscustomobject]) { throw 'INVALID_ROW' }
        if ($null -eq $row.name -or $null -eq $row.value) { throw 'MISSING_FIELD' }
        if ($row.name -isnot [string] -or $row.value -isnot [string]) { throw 'INVALID_FIELD' }
        $name = [string]$row.name
        $value = [string]$row.value
        if ($name.Length -gt 256 -or
            $name -notmatch "^[!#$%&'*+.^_`|~0-9A-Za-z-]+$" -or
            $value.Length -gt 8192 -or $value -match '[\r\n]') { throw 'INVALID_COOKIE' }

        $domain = ''
        $path = '/'
        if ($null -ne $row.domain) {
            if ($row.domain -isnot [string]) { throw 'INVALID_DOMAIN' }
            $domain = [string]$row.domain
        }
        if ($null -ne $row.path) {
            if ($row.path -isnot [string]) { throw 'INVALID_PATH' }
            $path = [string]$row.path
        }
        if ($domain.Length -gt 253 -or $domain -match '[\r\n;\\/\s]' -or
            ($domain -ne '' -and $domain.TrimStart('.') -notmatch '^(?:[a-z0-9-]+\.)*zhihuishu\.com$')) {
            throw 'OUT_OF_SCOPE_DOMAIN'
        }
        if (-not $path.StartsWith('/') -or $path.Length -gt 2048 -or $path -match '[\r\n]') {
            throw 'INVALID_PATH'
        }
        $key = $name + [char]0 + $domain + [char]0 + $path
        if ($seen.ContainsKey($key)) { throw 'DUPLICATE_COOKIE' }
        $seen[$key] = $true
        $items.Add([ordered]@{ name = $name; value = $value; domain = $domain; path = $path })
    }
    return (ConvertTo-Json -InputObject $items.ToArray() -Compress -Depth 4)
}

function Convert-ZhidaoCookieText([string]$inputText) {
    # Accept either a local ZHS JSON array or a single browser Cookie request-header value.
    # Do not echo inputText, include it in exceptions, or store it outside the ZHS file.
    if ([string]::IsNullOrWhiteSpace($inputText) -or $inputText.Length -gt 262144) {
        throw 'INVALID_TEXT_LENGTH'
    }
    $trimmed = $inputText.Trim()
    if ($trimmed.StartsWith('[')) { return Convert-ZhidaoCookieJson $trimmed }
    if ($trimmed -match '[\r\n]') { throw 'INVALID_MULTILINE_COOKIE' }
    if ($trimmed -match '^(?i:Cookie):\s*') {
        $trimmed = $trimmed -replace '^(?i:Cookie):\s*', ''
    }
    $pairs = $trimmed.Split(';')
    if ($pairs.Count -lt 1 -or $pairs.Count -gt 250) { throw 'COOKIE_COUNT' }
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($segment in $pairs) {
        $part = $segment.Trim()
        $position = $part.IndexOf('=')
        if ($position -lt 1) { throw 'INVALID_COOKIE_PAIR' }
        $name = $part.Substring(0, $position).Trim()
        $value = $part.Substring($position + 1).Trim()
        if ($name.Length -gt 256 -or
            $name -notmatch "^[!#$%&'*+.^_`|~0-9A-Za-z-]+$" -or
            $value.Length -gt 8192 -or $value -match '[\r\n]') {
            throw 'INVALID_COOKIE_PAIR'
        }
        # A pasted request header has no domain or path metadata. Restrict it
        # to the first-party Zhihuishu cookie scope; the server must verify login.
        $items.Add([ordered]@{
            name = $name; value = $value; domain = '.zhihuishu.com'; path = '/'
        })
    }
    return Convert-ZhidaoCookieJson (ConvertTo-Json -InputObject $items.ToArray() -Compress -Depth 4)
}

function Begin-ZhidaoCookieImport([string]$JsonContent) {
    if ($script:cookieImportActive) { throw 'ALREADY_IMPORTING' }
    if (-not (Test-Path -LiteralPath $script:dataDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:dataDir -Force | Out-Null
    }
    $previousExists = Test-Path -LiteralPath $script:cookiePath -PathType Leaf
    $previousBytes = if ($previousExists) { [System.IO.File]::ReadAllBytes($script:cookiePath) } else { $null }
    $tempPath = Join-Path $script:dataDir ('cookies-import-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = Join-Path $script:dataDir ('cookies-previous-' + [guid]::NewGuid().ToString('N') + '.bak')
    try {
        [System.IO.File]::WriteAllText($tempPath, $JsonContent, [System.Text.UTF8Encoding]::new($false))
        if ($previousExists) { [System.IO.File]::Replace($tempPath, $script:cookiePath, $backupPath, $true) }
        else { [System.IO.File]::Move($tempPath, $script:cookiePath) }
        $script:cookieImportPreviousExists = $previousExists
        $script:cookieImportPreviousBytes = $previousBytes
        $script:cookieImportExpectedDigest = Get-CookieDigest
        $script:cookieImportActive = $true
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
    }
}

function Complete-ZhidaoCookieImport($ServerExitCode) {
    if (-not $script:cookieImportActive) { return '' }
    try {
        # Upstream SDK login succeeds for codes 0, 6 and 7.
        # 6/7 are partial course API failures, not authentication failures.
        if ($null -ne $ServerExitCode -and [int]$ServerExitCode -in @(0, 6, 7)) {
            return 'Cookie 文件导入成功；服务器已确认登录。课程接口状态请参考连接诊断。'
        }
        if ($script:cookieImportExpectedDigest -ne (Get-CookieDigest)) {
            return 'Cookie 校验未完成，且会话已被其他操作修改；未覆盖新会话，请手动检查登录。'
        }
        $tempPath = Join-Path $script:dataDir ('cookies-restore-' + [guid]::NewGuid().ToString('N') + '.tmp')
        $backupPath = Join-Path $script:dataDir ('cookies-discard-' + [guid]::NewGuid().ToString('N') + '.bak')
        try {
            if ($script:cookieImportPreviousExists) {
                [System.IO.File]::WriteAllBytes($tempPath, [byte[]]$script:cookieImportPreviousBytes)
                [System.IO.File]::Replace($tempPath, $script:cookiePath, $backupPath, $true)
            } else {
                Remove-Item -LiteralPath $script:cookiePath -Force -ErrorAction Stop
            }
            return 'Cookie 导入未获服务器确认，已恢复导入前的本机登录状态；可用扫码登录重试。'
        } catch {
            return 'Cookie 导入未获服务器确认，回滚也失败；请使用设置页连接诊断，不要继续操作课程。'
        } finally {
            if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
        }
    } finally {
        $script:cookieImportActive = $false
        $script:cookieImportPreviousExists = $false
        $script:cookieImportPreviousBytes = $null
        $script:cookieImportExpectedDigest = ''
    }
}
