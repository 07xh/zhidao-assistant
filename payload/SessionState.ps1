# Session display helpers shared by the Windows WPF front end.
# Dot-source from Zhidao-GUI.ps1 after $script:cookiePath and Control exist.
# No credentials or digest are written to logs or disk.
function Get-CookieDigest {
    # Ephemeral digest only: never write Cookie contents or their hash to disk/logs.
    if (-not (Test-Path -LiteralPath $script:cookiePath -PathType Leaf)) { return '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($script:cookiePath)
        if ($bytes.Length -eq 0) { return '' }
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } catch { return '' }
    finally { $sha.Dispose() }
}
function Update-LoginState {
    $digest = Get-CookieDigest
    if (-not $digest) {
        $script:loginProbeState = ''
        $script:loginProbeCookieDigest = ''
        $script:loginProbeCheckedAt = $null
        (Control 'LoginStateText').Text = '尚无可验证的本地登录凭证'
        return
    }
    if ($script:loginProbeCookieDigest -ne $digest) {
        # A login, logout or account switch invalidates the old verification.
        $script:loginProbeState = ''
        $script:loginProbeCookieDigest = ''
        $script:loginProbeCheckedAt = $null
    }
    $time = if ($null -ne $script:loginProbeCheckedAt) {
        '（最近 ' + $script:loginProbeCheckedAt.ToString('HH:mm') + '）'
    } else { '' }
    (Control 'LoginStateText').Text = switch ($script:loginProbeState) {
        'checking' { '正在检查服务端登录及课程接口…' }
        'confirmed' { '服务端登录已验证 · 两类课程接口正常' + $time }
        'partial' { '服务端登录已验证 · 部分课程接口异常' + $time }
        'course-failed' { '服务端登录已验证 · 课程接口均异常' + $time }
        'session-unconfirmed' { '登录尚未确认 · 网络异常或凭证失效均有可能' }
        'local-invalid' { '登录凭证文件无效 · 需要重新扫码' }
        'environment-error' { '登录检测未完成 · 检查运行环境' }
        default { '存在本地凭证 · 尚未验证服务器登录' }
    }
}
