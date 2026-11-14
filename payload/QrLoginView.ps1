# Read-only view of the app's sanitized QR login lifecycle.
# All text is a fixed label; do not display QR tokens or upstream exceptions.
function Get-ZhidaoQrObservation([string]$token) {
    if ($token -cnotmatch '^[0-9a-f]{32}$') { return $null }
    $file = Join-Path $script:root ('monitor-qr-' + $token + '.json')
    try {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
        $info = Get-Item -LiteralPath $file -ErrorAction Stop
        if ($info.Length -lt 2 -or $info.Length -gt 1024) { return $null }
        $data = Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if ([int]$data.v -ne 1 -or [string]$data.token -cne $token) { return $null }
        $status = [string]$data.stage
        if ($status -cnotin @('requesting','ready','scanned','confirming','verified',
                             'unavailable','rejected','expired','cancelled','failed')) { return $null }
        $at = [DateTimeOffset]::FromUnixTimeSeconds([long]$data.at)
        $age = ([DateTimeOffset]::UtcNow - $at).TotalSeconds
        if ($age -lt -10 -or $age -gt 600) { return $null }
        return $status
    } catch { return $null }
}

function Get-ZhidaoQrStatusLabel([string]$stage) {
    switch ($stage) {
        'requesting' { '正在从官方登录服务获取新二维码…' }
        'ready' { '新二维码已生成 · 使用官方知到 App 扫码' }
        'scanned' { '已扫码 · 请在手机知到 App 确认登录' }
        'confirming' { '手机已确认 · 正在校验 CAS 服务器会话' }
        'verified' { '服务器登录认证成功 · 凭证已保存' }
        'unavailable' { '扫码已确认 · 认证服务器暂不可用，请稍后诊断' }
        'rejected' { '扫码已确认但服务器未建立会话 · 旧凭证未覆盖' }
        'expired' { '二维码过期 · 重新扫码登录' }
        'cancelled' { '扫码已取消' }
        'failed' { '二维码登录失败 · 检查网络、代理或安装环境' }
        default { '尚未开始新一轮扫码' }
    }
}

function Update-ZhidaoQrView {
    if ($null -eq $script:window) { return }
    $stage = Get-ZhidaoQrObservation $script:activeQrToken
    $caption = Get-ZhidaoQrStatusLabel $stage
    if ($script:lastQrStatus -and -not $script:activeQrToken) {
        $caption = Get-ZhidaoQrStatusLabel $script:lastQrStatus
    }
    (Control 'QrLoginStateText').Text = $caption
    if ($null -eq $script:qrViewer -or -not $script:qrViewer.IsVisible) { return }
    $script:qrViewerStatus.Text = $caption
    if ($stage -notin @('ready','scanned','confirming')) {
        if ($stage -in @('verified','rejected','cancelled','failed','expired','unavailable')) {
            $script:qrViewerImage.Source = $null
        }
        return
    }
    try {
        if (-not (Test-Path -LiteralPath $script:qrPath -PathType Leaf)) { return }
        $file = Get-Item -LiteralPath $script:qrPath -ErrorAction Stop
        # A previously saved image can NEVER be shown for a fresh QR attempt.
        if ($file.LastWriteTimeUtc -lt $script:qrStartedAt.ToUniversalTime()) { return }
        if ($file.Length -lt 100 -or $file.Length -gt 1048576) { return }
        if ($script:qrViewerImageStamp -eq $file.LastWriteTimeUtc.Ticks) { return }
        $bytes = [IO.File]::ReadAllBytes($script:qrPath)
        $stream = New-Object IO.MemoryStream (,$bytes)
        try {
            $picture = New-Object Windows.Media.Imaging.BitmapImage
            $picture.BeginInit()
            $picture.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $picture.StreamSource = $stream
            $picture.EndInit()
            $picture.Freeze()
            $script:qrViewerImage.Source = $picture
            $script:qrViewerImageStamp = $file.LastWriteTimeUtc.Ticks
        } finally { $stream.Dispose() }
    } catch {
        $script:qrViewerStatus.Text = '二维码图片尚未准备就绪；可检查终端中的扫码阶段提示。'
    }
}

function Show-ZhidaoQrDialog {
    if ($null -ne $script:qrViewer -and $script:qrViewer.IsVisible) {
        $script:qrViewer.Activate() | Out-Null
        return
    }
    $dialog = New-Object System.Windows.Window
    $dialog.Title = '知到 · 扫码登录'
    $dialog.Width = 375; $dialog.Height = 470
    $dialog.MinWidth = 320; $dialog.MinHeight = 390
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.Owner = $script:window
    $dialog.Background = [System.Windows.Media.Brushes]::White
    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = [System.Windows.Thickness]::new(22)
    $headline = New-Object System.Windows.Controls.TextBlock
    $headline.Text = '使用官方知到 App 扫码'
    $headline.FontSize = 17
    $headline.FontWeight = [System.Windows.FontWeights]::SemiBold
    $headline.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    [void]$stack.Children.Add($headline)
    $picture = New-Object System.Windows.Controls.Image
    $picture.Height = 288
    $picture.Stretch = [System.Windows.Media.Stretch]::Uniform
    [void]$stack.Children.Add($picture)
    $status = New-Object System.Windows.Controls.TextBlock
    $status.FontSize = 12
    $status.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $status.Margin = [System.Windows.Thickness]::new(0,15,0,0)
    $status.Text = '正在请求新二维码…'
    [void]$stack.Children.Add($status)
    $footnote = New-Object System.Windows.Controls.TextBlock
    $footnote.FontSize = 11
    $footnote.Foreground = [System.Windows.Media.Brushes]::Gray
    $footnote.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $footnote.Text = '二维码到期后将读取原版自动生成的新图片。关闭此窗口不会强制停止扫码任务。'
    $footnote.Margin = [System.Windows.Thickness]::new(0,11,0,0)
    [void]$stack.Children.Add($footnote)
    $dialog.Content = $stack
    $script:qrViewer = $dialog
    $script:qrViewerImage = $picture
    $script:qrViewerStatus = $status
    $script:qrViewerImageStamp = 0
    $dialog.Add_Closed({
        $script:qrViewer = $null
        $script:qrViewerImage = $null
        $script:qrViewerStatus = $null
    })
    $dialog.Show() | Out-Null
    Update-ZhidaoQrView
}
