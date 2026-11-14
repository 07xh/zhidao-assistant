# SPDX-License-Identifier: GPL-3.0-only
# Official Zhidao learning page WebView2 host. Does not implement/watch/report fake heartbeats.
param(
    [ValidateSet('ai','shared')][string]$CourseType = 'ai',
    [ValidatePattern('^[0-9]{1,20}$')][string]$CourseId = '0',
    [ValidatePattern('^[0-9]{1,20}$')][string]$ClassId = '0',
    [ValidatePattern('^[A-Za-z0-9_+./=:-]{0,512}$')][string]$RecruitAndCourseId = '',
    [ValidateSet('1','1.25','1.5','2')][string]$Speed = '1.5',
    [switch]$AllowMinimize,
    [switch]$AutoStart,
    [switch]$AutoNext,
    [ValidatePattern('^[0-9a-f]{32}$')][string]$MonitorToken = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
$root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'

# A short-lived sanitized local observation only. No account, URL, cookie or
# server progress is written to this monitor file.
$script:monitorStatusFile = if ($MonitorToken) { Join-Path $root ('monitor-playback-' + $MonitorToken + '.json') } else { '' }
$script:monitorLastWritten = [DateTime]::MinValue
function Write-OfficialPlaybackObservation([string]$eventName, [int]$position, [int]$duration, [bool]$pageVisible) {
    if (-not $script:monitorStatusFile -or $eventName -notin @(
        'observing','advancing','stalled','paused','buffering','seeking',
        'position-jump','sampling-gap','visibility-changed','ended')) { return }
    $now = [DateTime]::UtcNow
    if (($now - $script:monitorLastWritten).TotalMilliseconds -lt 1500) { return }
    if ($position -lt 0 -or $position -gt 864000 -or $duration -lt 0 -or $duration -gt 864000) { return }
    $tmp = Join-Path $root ('monitor-write-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $bak = Join-Path $root ('monitor-old-' + [Guid]::NewGuid().ToString('N') + '.bak')
    try {
        $body = @{
            v = 1; token = $MonitorToken; event = $eventName;
            position = $position; duration = $duration;
            visible = $pageVisible; at = $now.ToString('o')
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($tmp, $body, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $script:monitorStatusFile -PathType Leaf) {
            [IO.File]::Replace($tmp, $script:monitorStatusFile, $bak, $true)
        } else {
            [IO.File]::Move($tmp, $script:monitorStatusFile)
        }
        $script:monitorLastWritten = $now
    } catch {
        # Optional UI observation must not interrupt real playback.
    } finally {
        foreach ($item in @($tmp,$bak)) {
            if (Test-Path -LiteralPath $item) { Remove-Item -LiteralPath $item -Force -ErrorAction SilentlyContinue }
        }
    }
}
$sdk = Join-Path $root 'webview2'
$runtimeDll = Join-Path $sdk 'runtimes\win-x64\native\WebView2Loader.dll'
$coreDll = Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll'
$wpfDll = Join-Path $sdk 'Microsoft.Web.WebView2.Wpf.dll'
$directUri = if ($CourseType -eq 'ai') {
    if ($CourseId -eq '0' -or $ClassId -eq '0') { throw '缺少有效的 AI 课程 ID' }
    'https://ai-smart-course-student-pro.zhihuishu.com/singleCourse/knowledgeStudy/' + $CourseId + '/' + $ClassId
} else {
    if ([string]::IsNullOrWhiteSpace($RecruitAndCourseId)) { throw '共享课缺少原始路由标识；请重新同步课程' }
    'https://studyvideoh5.zhihuishu.com/stuStudy?recruitAndCourseId=' + [uri]::EscapeDataString($RecruitAndCourseId)
}
# Deep links may not work until the OFFICIAL web session has been established.
# ZHS CLI cookies are not WebView2 cookies, so always start from the official course portal.
$portalUri = if ($CourseType -eq 'ai') { 'https://ai.zhihuishu.com/' } else { 'https://www.zhihuishu.com/' }
function Test-OfficialUrl([string]$candidate) {
    if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.Length -gt 2048) { return $false }
    $parsed = $null
    if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$parsed)) { return $false }
    if ($parsed.Scheme -ne 'https' -or -not $parsed.IsDefaultPort -or $parsed.UserInfo -or $parsed.IsFile) { return $false }
    $hostName = $parsed.Host.ToLowerInvariant()
    return ($hostName -eq 'zhihuishu.com' -or $hostName.EndsWith('.zhihuishu.com'))
}
function Message([string]$msg) {
    [System.Windows.MessageBox]::Show($msg,'知到学习助手 V5.2.8 · 官方视频',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information) | Out-Null
}
function External-Browser([string]$reason) {
    Message ("内嵌 WebView2 播放器暂不可用："+$reason+"`n`n将改为打开官方浏览器页面。外部浏览器的倍速请在播放器内手动设置。")
    Start-Process -FilePath $portalUri
    # Code 22 tells the parent GUI not to verify before external-browser watching ends.
    exit 22
}
if (-not (Test-Path -LiteralPath $runtimeDll) -or -not (Test-Path -LiteralPath $coreDll) -or -not (Test-Path -LiteralPath $wpfDll)) {
    External-Browser '缺少 WebView2 SDK 文件。可重新运行安装包。'
    return
}
try {
    # Loader is installed under a user-owned application directory and located via PATH.
    $env:PATH = (Split-Path -Parent $runtimeDll) + ';' + $env:PATH
    Add-Type -Path $coreDll
    Add-Type -Path $wpfDll
    [void][Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString()
} catch {
    External-Browser 'Windows 未检测到可用的 Microsoft Edge WebView2 Runtime，或依赖加载失败。'
    return
}
# Browser storage is isolated from ZHS Python cookies; website login is handled on official pages.
$data = Join-Path $env:LOCALAPPDATA 'ZHSDesktop\official-webview-profile'
New-Item -ItemType Directory -Path $data -Force | Out-Null
$window = New-Object System.Windows.Window
$window.Title = '知到学习助手 V5.2.8 · 官方课程播放器'
$window.Width = 1120; $window.Height = 760
$window.MinWidth = 720; $window.MinHeight = 520
$window.WindowStartupLocation = 'CenterScreen'
$window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F5F8FC')
$window.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
$window.ShowInTaskbar = $true
$window.WindowState = 'Normal'
$grid = New-Object System.Windows.Controls.Grid
$grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) | Out-Null
$grid.RowDefinitions[0].Height = [System.Windows.GridLength]::Auto
$grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) | Out-Null
$grid.RowDefinitions[1].Height = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
$grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) | Out-Null
$grid.RowDefinitions[2].Height = [System.Windows.GridLength]::Auto
$window.Content = $grid
$controls = New-Object System.Windows.Controls.WrapPanel
$controls.Orientation = 'Horizontal'; $controls.Margin = [System.Windows.Thickness]::new(14,10,14,10)
$controls.VerticalAlignment = 'Center'
[System.Windows.Controls.Grid]::SetRow($controls,0)
[void]$grid.Children.Add($controls)
function Btn([string]$caption) {
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $caption; $b.Padding = [System.Windows.Thickness]::new(13,8,13,8)
    $b.Margin = [System.Windows.Thickness]::new(0,0,10,0)
    $b.Background = [System.Windows.Media.Brushes]::White
    [void]$controls.Children.Add($b)
    return $b
}
$apply = Btn ('尝试 '+$Speed+'× 倍速')
$playNow = Btn '播放当前视频'
$checkPlayback = Btn '查看本地播放状态'
# These two flags come from the locally saved GUI preferences.
# The HTML5 media controller does not inject heartbeat/progress requests.
$portal = Btn '官方课程门户'
$goCourse = Btn '直达选中课程'
$paste = Btn '粘贴官方课程链接'
$refresh = Btn '刷新页面'
$browser = Btn '在系统浏览器打开'
if ($AllowMinimize) {
    $min = Btn '最小化窗口'
    $min.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
}
$tip = New-Object System.Windows.Controls.TextBlock
$tip.Text = '先网页登录进入课程。自动开始：'+$(if($AutoStart){'开'}else{'关'})+'；自动下一节：'+$(if($AutoNext){'开'}else{'关'})+'。'
$tip.FontSize=12; $tip.VerticalAlignment='Center'; $tip.Foreground=[System.Windows.Media.Brushes]::SlateGray
[void]$controls.Children.Add($tip)
$status = New-Object System.Windows.Controls.TextBlock
$status.Text = '正在打开官方课程门户。WebView2 与 ZHS 扫码会话相互独立，请在网页内登录。'
$status.Foreground = [System.Windows.Media.Brushes]::SlateGray
$status.TextWrapping = 'Wrap'; $status.FontSize = 11
$status.Margin = [System.Windows.Thickness]::new(14,9,14,9)
[System.Windows.Controls.Grid]::SetRow($status,2)
[void]$grid.Children.Add($status)
$web = New-Object Microsoft.Web.WebView2.Wpf.WebView2
$web.Margin = [System.Windows.Thickness]::new(8,0,8,0)
$props = New-Object Microsoft.Web.WebView2.Wpf.CoreWebView2CreationProperties
$props.UserDataFolder = $data
$web.CreationProperties = $props
[System.Windows.Controls.Grid]::SetRow($web,1)
[void]$grid.Children.Add($web)
# Applies only to standard HTML5 video elements on zhihuishu.com official pages.
# It never calls platform progress APIs, starts fake playback, spoofs visibility, or reports study time.
$rate = [double]::Parse($Speed,[System.Globalization.CultureInfo]::InvariantCulture)
$rateString = $rate.ToString([System.Globalization.CultureInfo]::InvariantCulture)
# Load audited JS as a separate app resource: testable with Node without Windows.
$jsPath = Join-Path $root 'Official-MediaController.js'
if (-not (Test-Path -LiteralPath $jsPath -PathType Leaf)) {
    Message '缺少官方播放控制脚本，请重新安装。'
    exit 23
}
$script:js = [System.IO.File]::ReadAllText($jsPath,[System.Text.Encoding]::UTF8)
$script:js = $script:js.Replace('__RATE__',$rateString)
$script:js = $script:js.Replace('__AUTO_START__', $(if ($AutoStart) { 'true' } else { 'false' }))
$script:js = $script:js.Replace('__AUTO_NEXT__', $(if ($AutoNext) { 'true' } else { 'false' }))
$web.Add_CoreWebView2InitializationCompleted({
    param($sender,$eventArgs)
    if (-not $eventArgs.IsSuccess) {
        $status.Text = '播放器初始化失败。请使用“在系统浏览器打开”。'
        return
    }
    try {
        # Inject into future documents. The JS controller deliberately skips iframe documents to prevent multiple videos starting.
        [void]$web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync($script:js)
        # Messages only update local GUI status; they cannot alter progress/cookies.
        $web.CoreWebView2.Add_WebMessageReceived({
            param($sender,$args)
            try {
                $source = [Uri]::new([string]$args.Source)
                $hostName = $source.Host.ToLowerInvariant()
                if ($source.Scheme -ne 'https' -or -not ($hostName -eq 'zhihuishu.com' -or $hostName.EndsWith('.zhihuishu.com'))) { return }
                $message = $args.TryGetWebMessageAsString() | ConvertFrom-Json
                if ([string]$message.kind -eq 'playback-health') {
                    # Diagnostic readings are from the local video element, NOT
                    # confirmed learning time or server-side progress.
                    $event = [string]$message.event
                    if ($event -notin @('observing','advancing','stalled','paused','buffering','seeking','position-jump','sampling-gap','visibility-changed','ended')) { return }
                    $position = [Math]::Max(0,[Math]::Min(864000,[int]$message.positionSeconds))
                    $duration = [Math]::Max(0,[Math]::Min(864000,[int]$message.durationSeconds))
                    $elapsedText = ('{0:D2}:{1:D2}' -f [int][Math]::Floor($position / 60), [int]($position % 60))
                    $durationText = if ($duration -gt 0) { ('{0:D2}:{1:D2}' -f [int][Math]::Floor($duration / 60), [int]($duration % 60)) } else { '未知时长' }
                    $stateText = switch ($event) {
                        'observing' { '正在观测真实播放时间' }
                        'advancing' { '播放器时间正常前进' }
                        'stalled' { '播放时间持续未前进；请检查缓冲、网页提示或后台暂停' }
                        'paused' { '播放器已暂停' }
                        'buffering' { '播放器正在缓冲' }
                        'seeking' { '发生进度跳转，不能视作连续观看' }
                        'position-jump' { '视频位置发生明显跳变，不能视作连续观看' }
                        'sampling-gap' { '采样间隔过长（可能后台限时或系统休眠），已重设观测基线' }
                        'visibility-changed' { '页面前后台状态改变，已重新检查播放状态' }
                        'ended' { '本地视频已结束' }
                    }
                    Write-OfficialPlaybackObservation $event $position $duration ([bool]$message.pageVisible)
                    $backgroundText = if ($message.pageVisible -eq $false) { ' · 当前窗口/页面不在前台' } else { '' }
                    $status.Text = ('本地播放诊断：'+$stateText+' · '+$elapsedText+' / '+$durationText+$backgroundText+'。服务器学习进度需单独核验。')
                    return
                }
                if ([string]$message.kind -eq 'player-action') {
                    $actionText = switch ([string]$message.event) {
                        'autoplay-started' { '已发起正常自动播放；请检查画面和服务器进度。' }
                        'autoplay-blocked' { '浏览器或官网阻止自动播放，请手动点击画面中的播放按钮。' }
                        'autoplay-requested' { '已请求官方主视频播放，等待播放器响应。' }
                        'autoplay-retry-available' { '视频暂未就绪或播放请求中断；播放器就绪后会有限重试。' }
                        'autoplay-retry-exhausted' { '自动播放重试次数已用完，请使用网页中的官方播放按钮。' }
                        'primary-selected' { '已识别一个官方主视频；仅控制该视频。' }
                        'multiple-videos-visible' { '页面检测到多个视频元素；已选择显示面积最大的主视频，不会启动其他视频。' }
                        'secondary-video-playing' { '检测到页面中的其他视频正在播放；本工具未启动或控制该视频。' }
                        'iframe-not-controlled' { '检测到嵌入式视频框架。为避免多个框架同时播放，自动控制仅作用于顶层页面；请使用官方播放器控件。' }
                        'no-primary-video' { '当前页面尚未检测到可见的主视频。请进入课程视频页或手动使用官方播放器。' }
                        'monitor-not-course-page' { '当前不是课程视频播放页。请先从官方课程列表进入视频。' }
                        'monitor-no-video' { '当前课程页面没有可观测的 HTML5 视频，可能在内嵌框架内；请检查网页播放状态。' }
                        'next-clicked' { '已在课程主内容区域识别并点击“下一节”控件，等待新课时加载。' }
                        'next-not-found' { '本节视频已结束，但课程主内容区域没有可安全确认的“下一节”按钮；请手动切换。' }
                        'media-error' { '官方视频组件报告播放错误，请检查网页提示。' }
                        'speed-unavailable' { '网页不允许自动修改倍速，请使用官方播放器菜单。' }
                        'speed-not-applied' { '主视频未接受目标倍速；请在官方播放器菜单中手动选择。' }
                        default { '' }
                    }
                    if ($actionText) { $status.Text = $actionText }
                    return
                }
                if ([string]$message.kind -ne 'media-status') { return }
                $actualRate = [double]$message.rate
                if ($actualRate -le 0 -or $actualRate -gt 16) { return }
                $displayRate = $actualRate.ToString('0.##',[System.Globalization.CultureInfo]::InvariantCulture)
                $state = if ([string]$message.event -eq 'ended') { '已结束' } elseif ([string]$message.event -eq 'waiting') { '缓冲中' } elseif ([bool]$message.paused) { '暂停' } else { '播放中' }
                $status.Text = '已检测到官方 HTML5 视频 · 实际倍速 '+$displayRate+'× · '+$state+'。学习进度以官方服务器为准。'
            } catch { }
        })
        $status.Text = 'WebView2 已就绪。请在官方门户登录，打开“我的课程/我的学堂”，点击该课程“去学习”。目标倍速 '+$Speed+'×。'
    } catch { $status.Text = '已加载官方页面；倍速自动设置不可用，请手动选择。' }
})
$web.Add_NavigationStarting({
    param($sender,$eventArgs)
    try {
        $dest = [Uri]::new([string]$eventArgs.Uri)
        if (-not (Test-OfficialUrl $dest.AbsoluteUri)) {
            $status.Text = '页面正在跳转到非智慧树站点；请核实页面来源，必要时使用系统浏览器。'
        } elseif ($dest.Host -eq 'passport.zhihuishu.com' -or $dest.AbsolutePath -match '(?i)(login|signIn)') {
            $status.Text = '检测到官方登录页面：请先在网页内完成登录，再从门户进入课程。'
        } else {
            $status.Text = '正在加载官方页面：' + $dest.Host
        }
    } catch { $status.Text = '网页正在导航，请留意是否要求重新登录。' }
})
$web.Add_NavigationCompleted({
    param($sender,$eventArgs)
    if ($eventArgs.IsSuccess) {
        try { [void]$web.ExecuteScriptAsync($script:js) } catch { }
        $current = ''
        try { $current = [string]$web.Source.Host } catch { }
        if ($current -eq 'passport.zhihuishu.com') {
            $status.Text = '已进入官方登录页：完成登录后请从官方课程门户选择课程。'
        } elseif ($current -eq 'ai.zhihuishu.com' -or $current -eq 'www.zhihuishu.com') {
            $status.Text = '官方课程门户已加载。请打开“我的课程/我的学堂”，点击课程卡片上的“去学习”；必要时点击“直达选中课程”。'
        } else {
            $status.Text = '官方页面已加载（' + $current + '）。等待检测视频；'+$Speed+'× 仍是目标值，只有检测到实际倍速才算生效。'
        }
    } else {
        $errName = 'Unknown'
        try { $errName = [string]$eventArgs.WebErrorStatus } catch { }
        $status.Text = '网页加载失败 ['+$errName+']。检查网络和官方网页登录；可使用“官方课程门户”或“在系统浏览器打开”。'
    }
})
$apply.Add_Click({
    if ($null -ne $web.CoreWebView2) {
        try { [void]$web.ExecuteScriptAsync('(() => { const c=window.__zhidaoOfficialController; return c ? c.applyRate() : null; })()'); $status.Text = '已请求对识别到的主视频应用 '+$Speed+'×；请以状态栏检测到的实际倍速为准。' }
        catch { $status.Text = '无法自动设置倍速，请使用官方播放器倍速菜单。' }
    }
})
$playNow.Add_Click({
    if ($null -ne $web.CoreWebView2) {
        try {
            # Use the controller's primary-video selection; never query and start an arbitrary video element.
            [void]$web.ExecuteScriptAsync('(() => { const c=window.__zhidaoOfficialController; return c ? c.playPrimaryFromUserGesture() : null; })()')
            $status.Text = '已请求播放识别到的主视频；若浏览器策略阻止，请直接点击网页内的官方播放按钮。'
        } catch { $status.Text = '无法启动当前主视频，请使用网页中的官方播放按钮。' }
    }
})
$checkPlayback.Add_Click({
    if ($null -eq $web.CoreWebView2) {
        $status.Text = '播放器尚未初始化，无法检查播放状态。'
        return
    }
    try {
        [void]$web.ExecuteScriptAsync('(() => { const c=window.__zhidaoOfficialController; return c ? (c.scan(), c.monitorNow(true)) : "controller-unavailable"; })()')
        $status.Text = '正在读取官方播放器的本地状态；没有修改任何服务器学习记录。'
    } catch { $status.Text = '无法获取 HTML5 播放状态；可能使用了嵌入式播放器，请查看官网播放器状态。' }
})
$refresh.Add_Click({ if ($null -ne $web.CoreWebView2) { $web.Reload() } })
$portal.Add_Click({
    $web.Source = [Uri]::new($portalUri)
    $status.Text = '正在返回官方课程门户；请在网页内登录并从课程卡片进入。'
})
$goCourse.Add_Click({
    $web.Source = [Uri]::new($directUri)
    $status.Text = '正在尝试课程直达地址。若仍停留在登录页或空白页，请从官方课程门户进入。'
})
$paste.Add_Click({
    try {
        $candidate = [System.Windows.Clipboard]::GetText().Trim()
        if (-not (Test-OfficialUrl $candidate)) {
            Message '剪贴板中没有安全有效的智慧树 HTTPS 地址。请在官方网页打开本课程后，复制浏览器地址栏的完整链接。'
            return
        }
        if ($CourseType -eq 'ai' -and $candidate -notmatch [regex]::Escape($CourseId)) {
            $res = [System.Windows.MessageBox]::Show('所粘贴的官方地址中未发现当前课程 ID，可能不是已选课程。是否继续打开？','核对课程链接', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }
        $web.Source = [Uri]::new($candidate)
        $status.Text = '正在打开剪贴板中的官方智慧树链接。请核对课程名称是否正确。'
    } catch { Message '读取剪贴板或打开链接失败。请重新复制官方课程页面地址。' }
})
$browser.Add_Click({
    $openUrl = $portalUri
    try { if ($null -ne $web.Source -and (Test-OfficialUrl $web.Source.AbsoluteUri)) { $openUrl = $web.Source.AbsoluteUri } } catch { }
    Start-Process -FilePath $openUrl
})
$window.Add_StateChanged({
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $status.Text = '窗口已最小化。系统或官方网页可能暂停后台播放；恢复后查看真实倍速与进度。'
    } elseif ($null -ne $web.CoreWebView2) {
        $status.Text = '已恢复播放器窗口。请检查画面是否仍在播放，之后核验服务器进度。'
    }
})
$window.Add_Closed({
    try { $web.Dispose() } catch { }
    if ($script:monitorStatusFile) {
        Remove-Item -LiteralPath $script:monitorStatusFile -Force -ErrorAction SilentlyContinue
    }
})
try {
    # Setting Source initializes CoreWebView2 asynchronously, without waiting on the UI thread.
    $web.Source = [Uri]::new($portalUri)
    [void]$window.ShowDialog()
} catch {
    External-Browser '官方播放器窗口启动失败，请检查 WebView2 安装。'
}
