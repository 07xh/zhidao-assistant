# WPF smoke test without real browser, ZHS login or platform network traffic.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$script:root = Join-Path ([IO.Path]::GetTempPath()) ('zhidao-wpf-monitor-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:root -Force | Out-Null
try {
    $script:window = [System.Windows.Markup.XamlReader]::Parse(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload\Zhidao-UI.xaml') -Raw -Encoding UTF8))
    function Control([string]$name) {
        $result = $script:window.FindName($name)
        if ($null -eq $result) { throw ('Missing WPF control ' + $name) }
        return $result
    }
    $script:fakeSession = ('a' * 64)
    function Get-SessionFingerprint { return $script:fakeSession }
    function Valid-CourseArgs($c) {
        if ($null -eq $c -or [string]$c.courseType -ne 'ai') { return $null }
        return @('ai',[string]$c.courseId,[string]$c.classId)
    }
    $script:course = [pscustomobject]@{ courseType='ai';courseId='110';classId='210';stale=$false }
    $script:progress = [pscustomobject]@{
        courseType='ai';courseId='110';classId='210';stale=$false;
        lastVerifiedAt=[DateTime]::UtcNow.ToString('o');
        knowledgePointCount=4;fullProgressPoints=2
    }
    function Current-Course { return $script:course }
    function Find-Progress($c) {
        if ($null -ne $c -and [string]$c.courseId -eq [string]$script:progress.courseId) {
            return $script:progress
        }
        return $null
    }
    function Format-Time([string]$stamp) { return '服务器读取时间' }
    $script:hasProgress = $true
    $script:playMode = 'official'
    $script:playerProcess = $null
    $script:playerMonitorToken = ''
    $script:playerSessionFingerprint = ''
    $script:playerCourse = $null
    . (Join-Path $PSScriptRoot 'payload\HeartbeatMonitor.ps1')
    . (Join-Path $PSScriptRoot 'payload\HeartbeatView.ps1')
    Initialize-HeartbeatMonitor
    Update-HeartbeatPanel
    if ((Control 'HeartbeatServerProgressBar').Value -ne 50 -or
        (Control 'HeartbeatProgressLabel').Text -ne '2/4 项' -or
        (Control 'HeartbeatVerifyLabel').Text -ne '上次已核验') {
        throw 'Per-course server record was not presented independently'
    }
    Toggle-HeartbeatPanel
    if ((Control 'HeartbeatExpandedPanel').Visibility -ne 'Visible') { throw 'Expand failed' }
    if (-not (Add-HeartbeatMonitorEvent $script:course $script:fakeSession 'player-start')) {
        throw 'Fixture event missing'
    }
    Update-HeartbeatPanel
    $events = Control 'HeartbeatEventsPanel'
    if ($events.Children.Count -lt 1 -or [string]$events.Children[0].Text -notmatch '官方网页播放器') {
        throw 'Visible event timeline missing'
    }
    # The local HTML5 bar is never used as server progress.
    $token = [Guid]::NewGuid().ToString('N')
    $path = Join-Path $script:root ('monitor-playback-' + $token + '.json')
    $fakeMedia = @{v=1;token=$token;event='advancing';position=60;duration=120;visible=$true;at=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($path, ($fakeMedia | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    $script:playerProcess = [pscustomobject]@{ Id=999 }
    $script:playerCourse = $script:course
    $script:playerMonitorToken = $token
    $script:playerSessionFingerprint = $script:fakeSession
    Update-HeartbeatPanel
    if ((Control 'HeartbeatLocalProgressBar').Value -ne 50 -or
        (Control 'HeartbeatServerProgressBar').Value -ne 50) {
        throw 'Local observation / server record render failed'
    }
    # Show observed ZHS segment percent, never the official course percent.
    $zhsToken = [Guid]::NewGuid().ToString('N')
    $zhsPath = Join-Path $script:root ('monitor-zhs-' + $zhsToken + '.json')
    $zhsData = @{v=1;token=$zhsToken;videoSegmentPercent=48.5;
        resourceIndex=2;resourceTotal=5;at=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
    [IO.File]::WriteAllText($zhsPath, ($zhsData | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    $script:playMode = 'zhs-original'
    $script:activeTaskProcess = [pscustomobject]@{Id=111}
    $script:activeTaskAction = 'play-ai'
    $script:activeTaskZhsToken = $zhsToken
    $script:activeTaskSessionFingerprint = $script:fakeSession
    $script:activeTaskCourse = $script:course
    Update-HeartbeatPanel
    if ((Control 'HeartbeatZhsPanel').Visibility -ne 'Visible' -or
        (Control 'HeartbeatZhsProgressBar').Value -ne 48.5 -or
        (Control 'HeartbeatZhsPercentText').Text -ne '48.5%' -or
        (Control 'HeartbeatServerProgressBar').Value -ne 50 -or
        (Control 'HeartbeatZhsResourceText').Text -notmatch '2/5') {
        throw 'Original ZHS stdout simulated progress was not displayed separately'
    }
    $script:course = [pscustomobject]@{courseType='ai';courseId='111';classId='210';stale=$false}
    Update-HeartbeatPanel
    if ((Control 'HeartbeatProgressLabel').Text -ne '—' -or
        (Control 'HeartbeatServerProgressBar').Value -ne 0 -or
        (Control 'HeartbeatLocalProgressBar').Value -ne 0 -or
        (Control 'HeartbeatZhsProgressBar').Value -ne 0) {
        throw 'Switching courses leaked progress'
    }
    Toggle-HeartbeatPanel
    if ((Control 'HeartbeatExpandedPanel').Visibility -ne 'Collapsed') { throw 'Collapse failed' }
    Write-Host 'WPF panel parse, expand/collapse, progress, playback and course isolation passed.'
} finally {
    Remove-Item -LiteralPath $script:root -Force -Recurse -ErrorAction SilentlyContinue
}
