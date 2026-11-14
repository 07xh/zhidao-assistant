# Heartbeat monitor view state (Windows PowerShell 5.1, read-only).
# No network requests, player control, or ZHS heartbeat generation here.
function Initialize-HeartbeatMonitor {
    $script:hmSession = ''
    $script:hmEvents = @()
    $script:hmTask = @{ key=''; state='idle'; mode='' }
    $script:hmVerify = @{ key=''; state='idle' }
}

function Get-HeartbeatCourseKey($course) {
    if ($null -eq $course) { return '' }
    $parts = Valid-CourseArgs $course
    if ($null -eq $parts) { return '' }
    if ([string]$parts[0] -eq 'ai') {
        return 'ai:' + [string]$parts[1] + ':' + [string]$parts[2]
    }
    # The shared course's route identity, if present, is more specific than courseId.
    $route = [string]$course.recruitAndCourseId
    if ($route -and $route -match '^[A-Za-z0-9_+./=:-]{1,512}$') {
        return 'shared:' + [string]$parts[1] + ':' + $route
    }
    return 'shared:' + [string]$parts[1]
}

function Sync-HeartbeatMonitorSession {
    $current = [string](Get-SessionFingerprint)
    if ($current -cne $script:hmSession) {
        $script:hmSession = $current
        $script:hmEvents = @()
        $script:hmTask = @{ key=''; state='idle'; mode='' }
        $script:hmVerify = @{ key=''; state='idle' }
    }
    return $current
}

function Add-HeartbeatMonitorEvent($course, [string]$fingerprint, [string]$code) {
    $current = Sync-HeartbeatMonitorSession
    $key = Get-HeartbeatCourseKey $course
    if (-not $key -or -not $fingerprint -or $fingerprint -cne $current) { return $false }
    # All event strings are fixed labels: never render stdout, stderr, cookies,
    # URLs or third-party exceptions in the monitor panel.
    $messages = @{
        'zhs-start' = 'ZHS 原版任务进程已启动（不代表心跳发送成功）'
        'zhs-exit-ok' = 'ZHS 原版命令退出码 0；学习进度尚待服务器确认'
        'zhs-exit-error' = 'ZHS 原版命令异常退出；未自动重试'
        'player-start' = '已启动官方网页播放器；等待本地 HTML5 观测'
        'player-close' = '官方播放器窗口已关闭；需要核验服务器记录'
        'player-external' = '已转至系统浏览器；本工具无法观察关闭时间'
        'verify-queued' = '该课程已排队服务器只读核验'
        'verify-start' = '正在只读核验该课程服务器记录'
        'verify-ok' = '服务器只读核验成功；请查看实际返回的课程记录'
        'verify-error' = '服务器核验失败或结果未知；保留既有进度'
    }
    if (-not $messages.ContainsKey($code)) { return $false }
    $script:hmEvents += [pscustomobject]@{
        key = $key
        fingerprint = $fingerprint
        code = $code
        message = [string]$messages[$code]
        at = (Get-Date -Format 'HH:mm:ss')
    }
    if ($script:hmEvents.Count -gt 48) {
        $script:hmEvents = @($script:hmEvents | Select-Object -Last 48)
    }
    return $true
}

function Set-HeartbeatMonitorTask($course, [string]$fingerprint,
        [ValidateSet('running','ended','error','idle')][string]$state,
        [ValidateSet('official','zhs-original','')][string]$mode = '') {
    $current = Sync-HeartbeatMonitorSession
    $key = Get-HeartbeatCourseKey $course
    if (-not $key -or -not $fingerprint -or $fingerprint -cne $current) { return $false }
    $script:hmTask = @{ key = $key; state = $state; mode = $mode }
    return $true
}

function Set-HeartbeatMonitorVerify($course, [string]$fingerprint,
        [ValidateSet('running','ok','error','idle')][string]$state) {
    $current = Sync-HeartbeatMonitorSession
    $key = Get-HeartbeatCourseKey $course
    if (-not $key -or -not $fingerprint -or $fingerprint -cne $current) { return $false }
    $script:hmVerify = @{ key = $key; state = $state }
    return $true
}

function Get-HeartbeatMonitorEvents($course) {
    $fp = Sync-HeartbeatMonitorSession
    $key = Get-HeartbeatCourseKey $course
    if (-not $key -or -not $fp) { return @() }
    return @($script:hmEvents | Where-Object {
        $_.key -ceq $key -and $_.fingerprint -ceq $fp
    } | Select-Object -Last 7)
}
