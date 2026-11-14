# Read-only view of the app's sanitized QR login lifecycle.
# All text is a fixed label; do not display QR tokens or upstream exceptions.
# Delete only this application's one-use QR picture; never use wildcards.
# This is also the GUI fallback if the Python QR child is force-terminated.
function Clear-ZhidaoQrImage([string]$path) {
    try {
        $expected = [IO.Path]::GetFullPath((Join-Path $script:dataDir 'qrcode.png'))
        $actual = [IO.Path]::GetFullPath($path)
        if (-not [string]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        if (Test-Path -LiteralPath $actual -PathType Leaf) {
            Remove-Item -LiteralPath $actual -Force -ErrorAction Stop
        }
        return (-not (Test-Path -LiteralPath $actual))
    } catch {
        return $false
    }
}

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
                             'unavailable','rejected','expired','cancelled','failed',
                             'environment-error')) { return $null }
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
        'environment-error' { '扫码组件启动失败 · 检查 ZHS 安装及本机配置' }
        default { '尚未开始新一轮扫码' }
    }
}

# A fresh QR file can arrive even if the local observation JSON write fails.
# This fallback is only allowed for the CURRENT randomized login attempt.
# Startup removes the previous QR, and the file must be newer than its start.
function Get-ZhidaoFreshQrFile {
    if ($script:activeQrToken -cnotmatch '^[0-9a-f]{32}$') { return $null }
    try {
        if (-not (Test-Path -LiteralPath $script:qrPath -PathType Leaf)) { return $null }
        $file = Get-Item -LiteralPath $script:qrPath -Force -ErrorAction Stop
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $null }
        if ($file.Length -lt 100 -or $file.Length -gt 1048576) { return $null }
        if ($file.LastWriteTimeUtc -lt $script:qrStartedAt.ToUniversalTime().AddSeconds(-2)) {
            return $null
        }
        return $file
    } catch { return $null }
}

function Update-ZhidaoQrView {
    if ($null -eq $script:window) { return }
    $observed = Get-ZhidaoQrObservation $script:activeQrToken
    # Do not display "not started" during an active QR task if its Python
    # startup or observation writer has not finished yet.
    $active = ($script:activeQrToken -cmatch '^[0-9a-f]{32}$')
    $stage = if ($observed) { $observed } elseif ($active) { 'requesting' } else { '' }
    $file = $null
    if ($active -and $stage -in @('requesting','ready')) {
        $file = Get-ZhidaoFreshQrFile
    }
    $caption = Get-ZhidaoQrStatusLabel $stage
    if ($script:lastQrStatus -and -not $active) {
        $caption = Get-ZhidaoQrStatusLabel $script:lastQrStatus
    } elseif ($stage -eq 'requesting' -and $null -ne $file) {
        $caption = '本次二维码图片已生成 · 状态同步延迟，请使用官方知到 App 扫码'
    } elseif ($stage -eq 'requesting' -and $active -and
             ((Get-Date) - $script:qrStartedAt).TotalSeconds -gt 15) {
        $caption = '二维码尚未生成；请检查扫码任务窗口中的 [QR_*] 诊断代码'
    }
    (Control 'QrLoginStateText').Text = $caption
    if ($null -eq $script:qrViewer -or -not $script:qrViewer.IsVisible) { return }
    $script:qrViewerStatus.Text = $caption
    # Only show the active, unscanned QR. Scanned/confirmed/failed QR images
    # are hidden immediately, even when an old PNG remains on disk.
    if ($null -eq $file) {
        if ($null -ne $script:qrViewerImage) { $script:qrViewerImage.Source = $null }
        $script:qrViewerImageStamp = 0
        return
    }
    try {
        $stamp = [string]$file.LastWriteTimeUtc.Ticks + ':' + [string]$file.Length
        if ($script:qrViewerImageStamp -eq $stamp) { return }
        $bytes = [IO.File]::ReadAllBytes($script:qrPath)
        # PowerShell 5.1: bind a single byte[] constructor argument reliably.
        $stream = [IO.MemoryStream]::new([byte[]]$bytes)
        try {
            $picture = [Windows.Media.Imaging.BitmapImage]::new()
            $picture.BeginInit()
            $picture.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $picture.StreamSource = $stream
            $picture.EndInit()
            $picture.Freeze()
            $script:qrViewerImage.Source = $picture
            $script:qrViewerImageStamp = $stamp
        } finally { $stream.Dispose() }
    } catch {
        $script:qrViewerStatus.Text = '本次二维码图片已生成，但无法解码显示；请检查安装文件完整性'
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
        # Closing the QR window does not stop the CLI; it must not retain the
        # one-use bitmap in WPF after the window itself disappears.
        if ($null -ne $script:qrViewerImage) {
            $script:qrViewerImage.Source = $null
        }
        $script:qrViewerImageStamp = 0
        $script:qrViewer = $null
        $script:qrViewerImage = $null
        $script:qrViewerStatus = $null
    })
    $dialog.Show() | Out-Null
    Update-ZhidaoQrView
}
