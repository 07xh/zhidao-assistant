# No live network, cookies, ZHS or platform access. PS 5.1 fixture.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('monitor-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $script:root = $root
    $script:fakeSession = ('a' * 64)
    function Get-SessionFingerprint { return $script:fakeSession }
    function Valid-CourseArgs($course) {
        if ($null -eq $course) { return $null }
        if ([string]$course.courseType -eq 'ai') {
            if ([string]$course.courseId -notmatch '^\d+$' -or [string]$course.classId -notmatch '^\d+$') { return $null }
            return @('ai',[string]$course.courseId,[string]$course.classId)
        }
        if ([string]$course.courseType -eq 'shared') { return @('shared',[string]$course.courseId,'0') }
        return $null
    }
    . (Join-Path $PSScriptRoot 'payload\HeartbeatMonitor.ps1')
    Initialize-HeartbeatMonitor
    $course1 = [pscustomobject]@{ courseType='ai';courseId='1001';classId='3001' }
    $course2 = [pscustomobject]@{ courseType='ai';courseId='1002';classId='3001' }
    $shared1 = [pscustomobject]@{ courseType='shared';courseId='10';recruitAndCourseId='route-1' }
    $shared2 = [pscustomobject]@{ courseType='shared';courseId='10';recruitAndCourseId='route-2' }
    if ((Get-HeartbeatCourseKey $shared1) -ceq (Get-HeartbeatCourseKey $shared2)) {
        throw 'Shared course route identity collision'
    }
    if (-not (Add-HeartbeatMonitorEvent $course1 $script:fakeSession 'zhs-start')) { throw 'Event missing' }
    if (-not (Set-HeartbeatMonitorTask $course1 $script:fakeSession 'running' 'zhs-original')) {
        throw 'Task state not stored'
    }
    if ((@(Get-HeartbeatMonitorEvents $course1)).Count -ne 1) { throw 'Event not visible for same course' }
    if ((@(Get-HeartbeatMonitorEvents $course2)).Count -ne 0) { throw 'Cross-course event leaked' }
    if ($script:hmTask.key -cne (Get-HeartbeatCourseKey $course1)) { throw 'Task key mismatch' }
    if ((Add-HeartbeatMonitorEvent $course1 $script:fakeSession 'raw-cookie=sentinel')) {
        throw 'Unknown/untrusted event text accepted'
    }
    if ((@(Get-HeartbeatMonitorEvents $course1) | Where-Object { $_.message -match 'sentinel' }).Count -gt 0) {
        throw 'Raw event entered visible timeline'
    }
    # Reject events from older login sessions; no stale status may survive rotation.
    $old = $script:fakeSession
    $script:fakeSession = ('b' * 64)
    if ((Add-HeartbeatMonitorEvent $course1 $old 'verify-ok')) { throw 'Cross-account event accepted' }
    if ((@(Get-HeartbeatMonitorEvents $course1)).Count -ne 0 -or $script:hmTask.state -ne 'idle') {
        throw 'Session rotation retained task or event'
    }
    if (-not (Set-HeartbeatMonitorVerify $course2 $script:fakeSession 'running')) { throw 'Verify start missing' }
    if ($script:hmVerify.key -cne (Get-HeartbeatCourseKey $course2)) { throw 'Verify course mismatch' }
    if (-not (Set-HeartbeatMonitorVerify $course2 $script:fakeSession 'error')) { throw 'Verify error missing' }

    # Local HTML5 observation is a fresh, allowlisted, one-time-token file.
    $token = [Guid]::NewGuid().ToString('N')
    $path = Join-Path $root ('monitor-playback-' + $token + '.json')
    $observation = @{v=1;token=$token;event='advancing';position=72;duration=360;visible=$true;at=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($path, ($observation | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    $snapshot = Get-HeartbeatLocalSnapshot $token
    if ($null -eq $snapshot -or $snapshot.event -ne 'advancing' -or $snapshot.position -ne 72) {
        throw 'Fresh real-player observation was not displayed'
    }
    if ($null -ne (Get-HeartbeatLocalSnapshot ('f' * 32))) { throw 'Wrong token file matched' }
    $observation.at = [DateTime]::UtcNow.AddSeconds(-65).ToString('o')
    [IO.File]::WriteAllText($path, ($observation | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    if ($null -ne (Get-HeartbeatLocalSnapshot $token)) { throw 'Stale playback observed as live' }
    $observation.at = [DateTime]::UtcNow.ToString('o')
    $observation.event = 'forged-heartbeat-success'
    [IO.File]::WriteAllText($path, ($observation | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    if ($null -ne (Get-HeartbeatLocalSnapshot $token)) { throw 'Untrusted playback status accepted' }
    Write-Host 'Heartbeat monitor course/session isolation and local observations passed (offline).'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
