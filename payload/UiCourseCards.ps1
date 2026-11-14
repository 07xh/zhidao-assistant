# UI-only course card rendering. Server evidence is supplied by Find-Progress.
# No network requests, heartbeat generation or login mutations.
function New-CourseCard($course, [int]$index) {
    # Read-only presentation of the last available per-course record.
    $progress = Find-Progress $course
    $isAi = ([string]$course.courseType -eq 'ai')
    $stale = [bool]$course.stale -or ($null -ne $progress -and [bool]$progress.stale)
    $verified = ($null -ne $progress -and -not $stale -and -not [string]::IsNullOrWhiteSpace([string]$progress.lastVerifiedAt))
    $card = New-Object System.Windows.Controls.Border
    $card.Background = Get-UiBrush 'UiBackground_FFFFFF'
    $card.BorderBrush = Get-UiBrush 'UiBorderBrush_DCE9FA'
    $card.BorderThickness = [System.Windows.Thickness]::new(1)
    $card.CornerRadius = [System.Windows.CornerRadius]::new(18)
    $card.Margin = [System.Windows.Thickness]::new(0,0,14,14)
    $card.Padding = [System.Windows.Thickness]::new(18)
    $card.MinHeight = 208
    $stack = New-Object System.Windows.Controls.StackPanel
    $card.Child = $stack
    $badges = New-Object System.Windows.Controls.DockPanel
    $badges.LastChildFill = $false
    $badges.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    $kind = New-Object System.Windows.Controls.Border
    $kind.Background = Get-UiBrush 'UiBackground_F8FBFF'
    $kind.CornerRadius = [System.Windows.CornerRadius]::new(9)
    $kind.Padding = [System.Windows.Thickness]::new(9,5,9,5)
    $kind.HorizontalAlignment = 'Left'
    $typeText = New-Object System.Windows.Controls.TextBlock
    $typeText.Text = if ($isAi) { '智慧课程' } else { '共享课程' }
    $typeText.FontSize = 11
    $typeText.Foreground = Get-UiBrush 'UiForeground_234F97'
    $kind.Child = $typeText
    [void]$badges.Children.Add($kind)
    $statusText = if ($stale) { '历史缓存' } elseif ($verified) { '上次已核验' } else { '未核验' }
    $status = New-Object System.Windows.Controls.Border
    $status.Background = if ($stale) { Get-UiBrush 'UiBackground_FFFBF5' } elseif ($verified) { Get-UiBrush 'UiBackground_F7FCFA' } else { Get-UiBrush 'UiBackground_EDF3FC' }
    $status.CornerRadius = [System.Windows.CornerRadius]::new(9)
    $status.Padding = [System.Windows.Thickness]::new(8,5,8,5)
    $status.HorizontalAlignment = 'Right'
    [System.Windows.Controls.DockPanel]::SetDock($status,[System.Windows.Controls.Dock]::Right)
    $statusLabel = New-Object System.Windows.Controls.TextBlock
    $statusLabel.FontSize = 11
    $statusLabel.Text = $statusText
    $statusLabel.Foreground = if ($stale) { Get-UiBrush 'UiForeground_AB763D' } elseif ($verified) { Get-UiBrush 'UiForeground_277A68' } else { Get-UiBrush 'UiForeground_566C87' }
    $status.Child = $statusLabel
    [void]$badges.Children.Add($status)
    [void]$stack.Children.Add($badges)
    $name = [string]$course.name
    if ([string]::IsNullOrWhiteSpace($name)) { $name = '未命名课程' }
    $title = Add-Text $stack $name 16 '#1A2B42' $true
    $title.Margin = [System.Windows.Thickness]::new(0,0,0,10)
    $title.ToolTip = $name
    $total = 0.0; $done = 0.0
    if ($null -ne $progress) {
        try {
            if ($isAi) {
                $total = [double]$progress.knowledgePointCount
                $done = [double]$progress.fullProgressPoints
            } else {
                $total = [double]$progress.videoCount
                $done = [double]$progress.completedVideos
            }
        } catch { $total = 0.0; $done = 0.0 }
    }
    $validCounts = ($total -gt 0 -and $done -ge 0 -and $done -le $total)
    $description = if ($stale) { '历史进度仅供参考，请重新同步核验' }
        elseif (-not $verified) { '暂无可核验的最新学习进度' }
        elseif (-not $validCounts) { '服务器已返回记录，暂无有效进度统计' }
        elseif ($isAi) { '满进度知识点：' + [int]$done + ' / ' + [int]$total }
        else { '已完成视频：' + [int]$done + ' / ' + [int]$total }
    $subtitle = Add-Text $stack $description 12 '#75869B'
    $subtitle.Margin = [System.Windows.Thickness]::new(0,0,0,9)
    if ($verified -and $validCounts) {
        $bar = New-Object System.Windows.Controls.ProgressBar
        $bar.Height = 7; $bar.Minimum = 0; $bar.Maximum = 100
        $bar.Value = [Math]::Round(100.0 * $done / $total,1)
        $bar.Foreground = Get-UiBrush 'UiForeground_2566B2'
        $bar.Background = Get-UiBrush 'UiBackground_E3EAF3'
        $bar.Margin = [System.Windows.Thickness]::new(0,0,0,6)
        [void]$stack.Children.Add($bar)
        $note = if ($isAi) { '知识点项目比例，并非官方整课进度' } else { '已完成视频数量比例，并非观看时长' }
        $hint = Add-Text $stack $note 10 '#75869B'
        $hint.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    }
    $button = New-Object System.Windows.Controls.Button
    $button.Content = if ($isAi) { '查看知识点  ›' } else { '查看视频详情  ›' }
    $button.Tag = $index
    $button.HorizontalAlignment = 'Left'
    $button.Style = $script:window.Resources['SecondaryButton']
    $button.Margin = [System.Windows.Thickness]::new(0,5,0,0)
    $button.Add_Click({ param($sender,$eventArgs) Select-Course ([int]$sender.Tag); Show-Page 'detail' })
    [void]$stack.Children.Add($button)
    return $card
}
