# WPF-only, read-only monitor rendering; main GUI owns task lifecycle.
# Pure heartbeat state and validations live in HeartbeatMonitor.ps1.
function Update-HeartbeatPanel {
    if ($null -eq $script:window) { return }
    $fp = Sync-HeartbeatMonitorSession
    $course = Current-Course
    $key = Get-HeartbeatCourseKey $course
    $taskLabel = '未启动'
    $commsLabel = '未观测'
    $verifyLabel = '未核验'
    $localLabel = '当前没有可观测的本地 HTML5 播放位置'
    $localPercent = 0
    $serverLabel = '—'
    $serverHint = '没有可确认的服务器进度'
    $serverPercent = 0

    if ($key -and $fp) {
        if ($script:hmTask.key -ceq $key) {
            $taskLabel = switch ($script:hmTask.state) {
                'running' { if ($script:hmTask.mode -eq 'official') { '官方窗口已启动' } else { 'ZHS 任务运行中' } }
                'ended' { '任务已退出' }
                'error' { '任务异常退出' }
                default { '未启动' }
            }
            if ($script:hmTask.mode -eq 'official' -and $script:hmTask.state -eq 'running') {
                $commsLabel = '官网独立通信'
            } elseif ($script:hmTask.mode -eq 'zhs-original' -and $script:hmTask.state -eq 'running') {
                $commsLabel = '原版心跳不可观测'
            }
        }
        if ($script:hmVerify.key -ceq $key) {
            $verifyLabel = switch ($script:hmVerify.state) {
                'running' { '正在只读核验' }
                'ok' { '读取成功' }
                'error' { '核验失败' }
                default { '未核验' }
            }
        }
        # Do not infer global course completion from local time or from an
        # individual knowledge point percentage.
        $progress = Find-Progress $course
        if ($script:hasProgress -and $null -ne $progress -and
            -not $progress.stale -and -not $course.stale -and $progress.lastVerifiedAt) {
            $part = if ($course.courseType -eq 'ai') { '已达满进度知识点' } else { '已完成视频数' }
            try {
                $total = if ($course.courseType -eq 'ai') { [int]$progress.knowledgePointCount } else { [int]$progress.videoCount }
                $done = if ($course.courseType -eq 'ai') { [int]$progress.fullProgressPoints } else { [int]$progress.completedVideos }
                if ($total -gt 0 -and $done -ge 0 -and $done -le $total) {
                    $serverPercent = [Math]::Round(100.0 * $done / $total, 1)
                    $serverLabel = [string]$done + '/' + [string]$total + ' 项'
                    $serverHint = $part + '：' + $serverLabel + '（' + $serverPercent + '%）；上次读取 ' + (Format-Time ([string]$progress.lastVerifiedAt))
                    if ($course.courseType -eq 'ai') {
                        $serverHint += '。此比例不是官方课程总进度或掌握度。'
                    } else {
                        $serverHint += '。此比例是完成视频数量，不是观看时长。'
                    }
                } else {
                    $serverHint = '服务器已返回记录，但该课程暂无可统计的学习项。'
                }
            } catch {
                $serverHint = '服务器记录包含不支持的统计字段；请重新同步。'
            }
            if ($verifyLabel -eq '未核验') { $verifyLabel = '上次已核验' }
        } elseif ($null -ne $progress -and ($progress.stale -or $course.stale)) {
            $serverHint = '当前仅有历史缓存，未确认本次会话的最新学习进度。'
        }
        # Only read the current launched official player, its own nonce, and the
        # original login session. Missing/stale events never fabricate progress.
        if ($null -ne $script:playerProcess -and $script:playerMonitorToken -and
            $script:playerSessionFingerprint -ceq $fp -and
            (Get-HeartbeatCourseKey $script:playerCourse) -ceq $key) {
            $sample = Get-HeartbeatLocalSnapshot $script:playerMonitorToken
            if ($null -ne $sample) {
                $caption = switch ($sample.event) {
                    'advancing' { '播放位置正在前进' }
                    'paused' { '已暂停' }
                    'buffering' { '缓冲中' }
                    'stalled' { '播放位置停滞' }
                    'ended' { '本地视频已结束' }
                    'position-jump' { '本地视频位置发生跳变' }
                    'seeking' { '正在跳转位置' }
                    'sampling-gap' { '采样中断，未确认连续播放' }
                    'visibility-changed' { '窗口可见性变化' }
                    default { '正在观测官方视频' }
                }
                $mm = [Math]::Floor($sample.position / 60)
                $ss = $sample.position % 60
                $positionText = ('{0:D2}:{1:D2}' -f [int]$mm,[int]$ss)
                $totalText = if ($sample.duration -gt 0) {
                    '{0:D2}:{1:D2}' -f [int][Math]::Floor($sample.duration / 60),[int]($sample.duration % 60)
                } else { '未知总时长' }
                $localLabel = $caption + ' · ' + $positionText + '/' + $totalText
                if (-not $sample.visible) { $localLabel += ' · 页面不在前台' }
                if ($sample.duration -gt 0) {
                    $localPercent = [Math]::Min(100,[Math]::Max(0,
                        [Math]::Round(100.0 * $sample.position / $sample.duration,1)))
                }
            }
        } elseif ($script:playMode -eq 'zhs-original') {
            $localLabel = '原版 ZHS 任务不提供可核实的 HTML5 实际播放位置'
        }
    }
    (Control 'HeartbeatTaskLabel').Text = $taskLabel
    (Control 'HeartbeatCommsLabel').Text = $commsLabel
    (Control 'HeartbeatVerifyLabel').Text = $verifyLabel
    (Control 'HeartbeatProgressLabel').Text = $serverLabel
    (Control 'HeartbeatProgressHint').Text = $serverHint
    (Control 'HeartbeatServerProgressBar').Value = [double]$serverPercent
    (Control 'HeartbeatLocalPlaybackText').Text = $localLabel
    (Control 'HeartbeatLocalProgressBar').Value = [double]$localPercent

    # Event cards are only allocated when the user expands the detail view.
    if ((Control 'HeartbeatExpandedPanel').Visibility -ne [System.Windows.Visibility]::Visible) { return }
    $panel = Control 'HeartbeatEventsPanel'
    $panel.Children.Clear()
    $history = @(Get-HeartbeatMonitorEvents $course)
    if ($history.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = '当前课程暂无可核实的运行事件'
        $empty.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#71859D')
        $empty.FontSize = 11
        [void]$panel.Children.Add($empty)
        return
    }
    for ($i = $history.Count - 1; $i -ge 0; $i--) {
        $item = $history[$i]
        $line = New-Object System.Windows.Controls.TextBlock
        $line.Text = [string]$item.at + '  ·  ' + [string]$item.message
        $line.FontSize = 11
        $line.TextWrapping = 'Wrap'
        $line.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#506781')
        $line.Margin = [System.Windows.Thickness]::new(0,0,0,5)
        [void]$panel.Children.Add($line)
    }
}

function Toggle-HeartbeatPanel {
    $panel = Control 'HeartbeatExpandedPanel'
    if ($panel.Visibility -eq [System.Windows.Visibility]::Visible) {
        $panel.Visibility = [System.Windows.Visibility]::Collapsed
        (Control 'BtnHeartbeatExpand').Content = '展开运行记录'
    } else {
        $panel.Visibility = [System.Windows.Visibility]::Visible
        (Control 'BtnHeartbeatExpand').Content = '收起运行记录'
    }
    Update-HeartbeatPanel
}
