# 知到学习助手 V5.2.8 · 官方 WebView2 播放 + 双模式读取。
# 保留 ZHS 0.1.5 的登录和 V3 的 zhidao_only.py 数据读取适配器。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$script:root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'
$script:python = Join-Path $script:root '.venv\Scripts\python.exe'
$script:dataDir = Join-Path $env:USERPROFILE '.zhs'
$script:coursesPath = Join-Path $script:dataDir 'zhidao-courses.json'
$script:progressPath = Join-Path $script:dataDir 'zhidao-progress.json'
$script:qrPath = Join-Path $script:dataDir 'qrcode.png'
$script:cookiePath = Join-Path $script:dataDir 'cookies.json'
$script:acceptanceFlag = Join-Path $script:root 'privacy-accepted-v5.2.7.flag'
$script:termsPath = Join-Path $script:root '使用条款与第三方声明.txt'
$script:privacyPath = Join-Path $script:root '隐私政策与数据说明.txt'
$script:licensePath = Join-Path $script:root 'LICENSE-GPL-3.0.txt'
$script:runningTasks = @()
$script:activeTaskProcess = $null
$script:activeTaskAction = ''
$script:courses = @()
$script:progressCourses = @()
$script:selectedCourseIndex = -1
$script:previousSignature = ''
$script:window = $null
$script:monitorCourse = $null
$script:monitorProcess = $null
$script:monitorBusy = $false
$script:modePath = Join-Path $script:root 'play-mode.txt'
$script:playMode = 'official' # default official
$script:playerSettingsPath = Join-Path $script:root 'official-player-settings.json'
$script:playbackSpeed = '1.5'
$script:allowMinimize = $true
$script:autoStart = $true
$script:autoNext = $true
$script:playerProcess = $null
$script:playerCourse = $null
$script:playerOpenedAt = $null
$script:pendingVerifyCourse = $null
$script:pendingVerifyPath = Join-Path $script:root 'pending-verify.json'
$script:verifyOutputPath = $null
$script:verifyErrorPath = $null
$script:loginProbeState = ''
$script:loginProbeCookieDigest = ''
$script:loginProbeCheckedAt = $null


function Load-Xaml([string]$path) {
    $source = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    return [System.Windows.Markup.XamlReader]::Parse($source)
}
function Control([string]$name) { return $script:window.FindName($name) }
function Notice([string]$message, [string]$title = '知到学习助手') {
    [System.Windows.MessageBox]::Show($script:window, $message, $title, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
}
function Show-Document([string]$title, [string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Notice '文档不存在，请重新安装以修复。'
        return
    }
    $viewer = New-Object System.Windows.Window
    $viewer.Title = $title
    $viewer.Width = 830; $viewer.Height = 640
    $viewer.MinWidth = 620; $viewer.MinHeight = 450
    $viewer.WindowStartupLocation = 'CenterOwner'
    $viewer.Owner = $script:window
    $viewer.Background = [System.Windows.Media.Brushes]::White
    $viewer.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $body = New-Object System.Windows.Controls.TextBox
    $body.IsReadOnly = $true
    $body.AcceptsReturn = $true
    $body.TextWrapping = 'Wrap'
    $body.VerticalScrollBarVisibility = 'Auto'
    $body.FontSize = 13
    $body.BorderThickness = [System.Windows.Thickness]::new(0)
    $body.Padding = [System.Windows.Thickness]::new(22)
    $body.Text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $viewer.Content = $body
    [void]$viewer.ShowDialog()
}
function Ask-Consent {
    if (Test-Path -LiteralPath $script:acceptanceFlag -PathType Leaf) { return $true }
    foreach ($path in @($script:termsPath, $script:privacyPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            [System.Windows.MessageBox]::Show('缺少第三方声明或隐私说明文件。请重新安装。') | Out-Null
            return $false
        }
    }
    $consent = Load-Xaml (Join-Path $script:root 'Consent-UI.xaml')
    $consent.FindName('TermsText').Text = Get-Content -LiteralPath $script:termsPath -Raw -Encoding UTF8
    $consent.FindName('PrivacyText').Text = Get-Content -LiteralPath $script:privacyPath -Raw -Encoding UTF8
    $checkbox = $consent.FindName('ConsentCheck')
    $yes = $consent.FindName('AcceptButton')
    $no = $consent.FindName('RejectButton')
    $checkbox.Add_Checked({ $yes.IsEnabled = $true })
    $checkbox.Add_Unchecked({ $yes.IsEnabled = $false })
    $yes.Add_Click({ if ($checkbox.IsChecked -eq $true) { $consent.DialogResult = $true; $consent.Close() } })
    $no.Add_Click({ $consent.DialogResult = $false; $consent.Close() })
    $accepted = $consent.ShowDialog()
    if ($accepted -ne $true) { return $false }
    try {
        [System.IO.File]::WriteAllText($script:acceptanceFlag, ('V5.2.7 accepted at ' + (Get-Date -Format o)), [System.Text.Encoding]::UTF8)
        return $true
    } catch {
        [System.Windows.MessageBox]::Show('无法保存同意记录，应用不会继续运行。') | Out-Null
        return $false
    }
}
function Any-TaskActive {
    $alive = @()
    foreach ($p in @($script:runningTasks)) {
        try { $p.Refresh(); if (-not $p.HasExited) { $alive += $p } } catch { }
    }
    $script:runningTasks = @($alive)
    return ($script:runningTasks.Count -gt 0)
}
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
function Start-Task([string]$action) {
    if ($action -notin @('login','courses','progress','doctor')) { return }
    if (Any-TaskActive) {
        Notice '已有登录或同步任务窗口在执行。请先完成或关闭它，再开始下一项操作。'
        return
    }
    try {
        $taskPath = Join-Path $script:root 'Zhidao-Task.cmd'
        $proc = Start-Process -FilePath $taskPath -ArgumentList $action -WorkingDirectory $env:USERPROFILE -PassThru
        $script:runningTasks = @($proc)
        $script:activeTaskProcess = $proc
        $script:activeTaskAction = $action
        if ($action -in @('login','doctor')) {
            # Never carry forward a previous verification while logging in or probing.
            $script:loginProbeState = if ($action -eq 'doctor') { 'checking' } else { '' }
            $script:loginProbeCookieDigest = Get-CookieDigest
            $script:loginProbeCheckedAt = $null
            Update-LoginState
        }
        if ($action -eq 'doctor') {
            (Control 'SyncMessageText').Text = '正在只读检查知到课程接口：不上传播放时长、不改变课程进度。'
        } elseif ($action -eq 'login') {
            (Control 'SyncMessageText').Text = '已打开扫码登录窗口。二维码生成后可在设置页查看。'
            Notice '请在弹出的窗口中等待生成二维码，然后到“设置与隐私”查看二维码并用官方知到 App 扫码。'
        } elseif ($action -eq 'courses') {
            (Control 'SyncMessageText').Text = '正在同步本人课程。结果以服务器返回的数据为准。'
        } else {
            (Control 'SyncMessageText').Text = '正在同步服务器视频或知识点进度；读取失败时保留旧缓存。'
        }
    } catch { Notice '无法启动任务。请检查安装是否完整，或重新运行 V5.2.8 安装程序。' }
}
function Check-TaskExit {
    if ($null -eq $script:activeTaskProcess) { return }
    $autoCheckAfterLogin = $false
    try {
        $script:activeTaskProcess.Refresh()
        if (-not $script:activeTaskProcess.HasExited) { return }
        $code = [int]$script:activeTaskProcess.ExitCode
        $action = $script:activeTaskAction
        if ($action -eq 'login') {
            $autoCheckAfterLogin = ($code -eq 0)
            (Control 'SyncMessageText').Text = if ($code -eq 0) {
                '扫码登录命令已结束，正在自动检测服务端登录状态。'
            } else { '扫码登录未成功（退出码 '+$code+'）。请重新扫码，或检查网络和窗口中的提示。' }
        } elseif ($action -eq 'play-ai') {
            (Control 'SyncMessageText').Text = if ($code -eq 0) {
                'ZHS 原版任务已经结束（退出码 0）。这只能确认命令正常退出，不代表服务器已经计入学习记录；请查看只读进度核验。'
            } else {
                'ZHS 原版任务异常退出（退出码 '+$code+'）。本程序不会自动重试或补发心跳；可检查原命令窗口中的错误并运行连接诊断。'
            }
        } elseif ($action -eq 'doctor') {
            # A verified ZHS bootstrap is distinct from business endpoint health.
            $script:loginProbeCookieDigest = Get-CookieDigest
            $script:loginProbeCheckedAt = Get-Date
            $script:loginProbeState = switch ($code) {
                0 { 'confirmed' }
                7 { 'partial' }
                6 { 'course-failed' }
                4 { 'session-unconfirmed' }
                8 { 'local-invalid' }
                5 { 'environment-error' }
                default { '' }
            }
            Update-LoginState
            (Control 'SyncMessageText').Text = switch ($code) {
                0 { '服务器只读检测通过：共享课和智慧课程接口均已返回有效数据。可以同步课程。' }
                3 { '连接诊断：本机缺少扫码凭证。请先扫码登录。' }
                4 { '连接诊断：本地凭证存在，但服务器登录校验尚未通过；检查网络，必要时重新扫码。' }
                8 { '连接诊断：本地 Cookie 文件格式无效，尚未连接服务器；请重新扫码登录。' }
                5 { '连接诊断：服务器测试未完成。请检查本机运行环境。' }
                6 { '连接诊断：服务端登录已验证，但两类课程接口都失败。请查看命令窗口的安全错误代码。' }
                7 { '连接诊断：部分课程接口成功、部分失败。可以查看已获取的课程，但仍需修复失败来源。' }
                default { '连接诊断未完成（退出码 '+$code+'）。请检查命令窗口。' }
            }
        } elseif ($code -eq 0) {
            (Control 'SyncMessageText').Text = if ($action -eq 'courses') { '课程同步已结束。界面会刷新最新课程列表。' } else { '进度同步已结束。以服务器返回的记录为准。' }
        } elseif ($code -eq 3) {
            (Control 'SyncMessageText').Text = '当前没有本机登录凭证，请先扫码登录。'
        } else {
            (Control 'SyncMessageText').Text = '同步没有完全成功（退出码 '+$code+'）。可能是登录失效、网络异常或课程接口变化；请先进行连接诊断。'
        }
    } catch {
        (Control 'SyncMessageText').Text = '无法确认命令执行结果，请使用连接诊断或重新启动软件。'
    } finally {
        $script:activeTaskProcess = $null
        $script:activeTaskAction = ''
        $script:runningTasks = @()
    }
    if ($autoCheckAfterLogin) { Start-Task 'doctor' }
}
function Get-SessionFingerprint {
    $saltPath = Join-Path $script:dataDir 'zhidao-cache-salt.bin'
    if (-not (Test-Path -LiteralPath $script:cookiePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $saltPath -PathType Leaf)) { return '' }
    try {
        $salt = [System.IO.File]::ReadAllBytes($saltPath)
        if ($salt.Length -ne 32) { return '' }
        $cookieData = [System.IO.File]::ReadAllBytes($script:cookiePath)
        if ($cookieData.Length -eq 0) { return '' }
        $mac = [System.Security.Cryptography.HMACSHA256]::new($salt)
        try { $digest = $mac.ComputeHash($cookieData) }
        finally { $mac.Dispose() }
        return ([BitConverter]::ToString($digest)).Replace('-','').ToLowerInvariant()
    } catch { return '' }
}
function Save-PendingVerify {
    if ($null -eq $script:pendingVerifyCourse) { return }
    $valid = Valid-CourseArgs $script:pendingVerifyCourse
    if ($null -eq $valid) { return }
    $body = @{ courseType = $valid[0]; courseId = $valid[1]; classId = $valid[2] } | ConvertTo-Json -Compress
    try {
        $tmp = $script:pendingVerifyPath + '.tmp'
        [System.IO.File]::WriteAllText($tmp, $body, [System.Text.Encoding]::UTF8)
        Move-Item -LiteralPath $tmp -Destination $script:pendingVerifyPath -Force -ErrorAction Stop
    } catch { (Control 'SyncMessageText').Text = '自动核验队列暂时无法持久化，请稍后手动核验。' }
}
function Load-PendingVerify {
    if (-not (Test-Path -LiteralPath $script:pendingVerifyPath -PathType Leaf)) { return }
    try {
        $row = Get-Content -LiteralPath $script:pendingVerifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne (Valid-CourseArgs $row)) { $script:pendingVerifyCourse = $row }
    } catch { }
}
function Check-VerifyExit {
    if ($null -eq $script:monitorProcess) { return }
    try {
        $script:monitorProcess.Refresh()
        if (-not $script:monitorProcess.HasExited) { return }
    } catch { return }
    try {
        $exitCode = [int]$script:monitorProcess.ExitCode
        $message = if ($exitCode -eq 0) { '服务器只读核验成功，已刷新本地记录。' } else { '服务器核验失败；旧进度保持不变。' }
        if ($exitCode -ne 0 -and $script:verifyOutputPath -and (Test-Path -LiteralPath $script:verifyOutputPath)) {
            # Only display allowlisted diagnostic codes. Never copy raw stdout/stderr to UI.
            $output = Get-Content -LiteralPath $script:verifyOutputPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $found = [regex]::Match([string]$output, '\[(AUTH|TIMEOUT|NETWORK|API_SHAPE|SERVICE|HTTP_ERROR|UNKNOWN)\]')
            if ($found.Success) { $message = '服务器核验失败 [' + $found.Groups[1].Value + ']；可稍后重试。旧进度未改变。' }
        }
        (Control 'SyncMessageText').Text = $message
    } catch {
        (Control 'SyncMessageText').Text = '服务器核验任务已结束，但状态读取失败；可手动核验。'
    } finally {
        $script:monitorProcess = $null
        foreach ($f in @($script:verifyOutputPath, $script:verifyErrorPath)) {
            if ($f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        }
        $script:verifyOutputPath = $null
        $script:verifyErrorPath = $null
    }
}
function Current-Course {
    if ($script:selectedCourseIndex -lt 0 -or $script:selectedCourseIndex -ge $script:courses.Count) { return $null }
    return $script:courses[$script:selectedCourseIndex]
}
function Valid-CourseArgs($course) {
    if ($null -eq $course) { return $null }
    $kind = if ($course.courseType -eq 'ai') { 'ai' } else { 'shared' }
    $id = [string]$course.courseId
    $classId = if ($kind -eq 'ai') { [string]$course.classId } else { '0' }
    # Only numeric IDs are used on the command line; do not pass course titles or API-supplied URLs.
    if ($id -notmatch '^[0-9]{1,20}$' -or $classId -notmatch '^[0-9]{1,20}$') { return $null }
    if ($id -eq '0' -or ($kind -eq 'ai' -and $classId -eq '0')) { return $null }
    return @($kind, $id, $classId)
}
function Set-PlaybackMode([string]$newMode) {
    if ($newMode -notin @('official','zhs-original')) { return }
    $script:playMode = $newMode
    # Keep the user setting separate from installed source files and credentials.
    try { [System.IO.File]::WriteAllText($script:modePath, $newMode, [System.Text.Encoding]::UTF8) } catch { }
    Update-MonitorDisplay
}
function Launch-Original-ZHS {
    $c = Current-Course
    $validated = Valid-CourseArgs $c
    if ($null -eq $validated) { Notice '课程 ID 未读取成功。请先同步课程并选择一门课程。'; return }
    # In this version the shared-course `courseId` alone is NOT the original CLI's `rac_id`.
    # Passing it as a shared course could target a different course; prohibit that ambiguity.
    if ($validated[0] -ne 'ai') {
        Notice '当前仅能将智慧课程的 courseId/classId 正确映射给 ZHS 原版。普通共享课尚需确认 racId，未启用原版入口。'
        return
    }
    if (Any-TaskActive) { Notice '已有任务正在运行，请先完成或关闭该任务窗口。'; return }
    if ($null -ne $script:monitorCourse) { Stop-Monitor }
    $message = "这会调用未修改的 ZHS 0.1.5 原版 CLI，执行 AI 智慧课程的模拟播放与进度上报。`n`n" +
        "它不等于实际观看课程，原版还可能处理视频中的弹窗题目；可能在服务器端改变学习记录，也可能违反学校或平台的学习规定。`n" +
        "本软件不会保证学习记录被服务器接受或计入完成。`n`n" +
        "确认针对当前选中的智慧课程运行原版 ZHS 吗？"
    $result = [System.Windows.MessageBox]::Show($script:window,$message,'ZHS 原版模拟心跳 · 明确确认',
        [System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    try {
        $taskPath = Join-Path $script:root 'Zhidao-Task.cmd'
        # All passed parameters have been validated to be decimal-only IDs.
        $proc = Start-Process -FilePath $taskPath -ArgumentList @('play-ai', $validated[1], $validated[2]) -WorkingDirectory $env:USERPROFILE -PassThru
        $script:runningTasks = @($proc)
        $script:activeTaskProcess = $proc
        $script:activeTaskAction = 'play-ai'
        (Control 'SyncMessageText').Text = 'ZHS 原版命令已启动。结束后将显示退出状态；这不代表服务器已确认学习进度。'
    } catch { Notice '无法启动 ZHS 原版 CLI。请确认安装完成。' }
}
function Start-Selected-Mode {
    if ($script:playMode -eq 'zhs-original') { Launch-Original-ZHS }
    else { Open-Official-Course }
}
function Update-MonitorDisplay {
    if ($null -eq $script:window) { return }
    $course = Current-Course
    $info = if ($script:playMode -eq 'zhs-original') { '当前为 ZHS 0.1.5 原版模式：模拟播放并向服务器报告进度（不是实际观看）。' } else { ('官方 WebView2 播放，目标倍速 '+$script:playbackSpeed+'×；自动开始 '+$(if($script:autoStart){'开'}else{'关'})+'；自动下一节 '+$(if($script:autoNext){'开'}else{'关'})+'；以服务器数据为准。') }
    if ($null -ne $course) {
        $p = Find-Progress $course
        if ($null -ne $p -and $p.lastVerifiedAt) {
            $info += ' 服务器上次核验：' + (Format-Time ([string]$p.lastVerifiedAt)) + '。'
        } else { $info += ' 尚未核验该课程。' }
    }
    if ($null -ne $script:monitorCourse) { $info += ' 定时只读核验：开启（每120秒）。' }
    (Control 'HeartbeatStatusText').Text = $info
    (Control 'BtnOpenLearning').Content = if ($script:playMode -eq 'zhs-original') { '运行 ZHS 原版' } else { '打开官方播放窗口' }
    (Control 'BtnMonitorToggle').Content = if ($null -ne $script:monitorCourse) { '停止定时核验' } else { '开启定时核验' }
}
function Stop-Monitor {
    $script:monitorCourse = $null
    $script:monitorTimer.Stop()
    Update-MonitorDisplay
}
function Launch-Verify([bool]$silent, $courseOverride = $null) {
    $course = if ($null -ne $courseOverride) { $courseOverride } elseif ($null -ne $script:monitorCourse -and $silent) { $script:monitorCourse } else { Current-Course }
    $args = Valid-CourseArgs $course
    if ($null -eq $args) {
        if (-not $silent) { Notice '缺少有效的课程 ID 或班级 ID。请先重新同步课程。' }
        return $false
    }
    if (Any-TaskActive) {
        if (-not $silent) { Notice '正在执行其他登录或同步任务，请稍后重试。' }
        return $false
    }
    Check-VerifyExit
    if ($null -ne $script:monitorProcess) { return $false }
    try {
        $taskArgs = @('"' + (Join-Path $script:root 'zhidao_only.py') + '"', 'verify-one', $args[0], $args[1], $args[2])
        $logDir = Join-Path $script:root 'diagnostics'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $nonce = [Guid]::NewGuid().ToString('N')
        $out = Join-Path $logDir ('verify-' + $nonce + '.out')
        $err = Join-Path $logDir ('verify-' + $nonce + '.err')
        # Temporary diagnostic streams are never shown raw and are removed on exit.
        $proc = Start-Process -FilePath $script:python -ArgumentList $taskArgs -WorkingDirectory $env:USERPROFILE -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -ErrorAction Stop
        if ($null -eq $proc) { return $false }
        $script:monitorProcess = $proc
        $script:verifyOutputPath = $out
        $script:verifyErrorPath = $err
        (Control 'SyncMessageText').Text = if ($silent) { '正在核验服务器课程记录。' } else { '单课核验已启动，结束后显示成功或错误代码。' }
        return $true
    } catch {
        foreach ($f in @($out,$err)) { if ($f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
        if (-not $silent) { Notice '无法启动单课核验，请检查本机 Python 环境。' }
        return $false
    }
}
function Save-PlayerSettings {
    try {
        $settings = @{speed=$script:playbackSpeed;allowMinimize=[bool]$script:allowMinimize;autoStart=[bool]$script:autoStart;autoNext=[bool]$script:autoNext;mode='official'} | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($script:playerSettingsPath,$settings,[System.Text.Encoding]::UTF8)
    } catch { (Control 'SyncMessageText').Text = '播放设置暂未能保存；本次仍可使用。' }
    Update-MonitorDisplay
}
function Open-Official-Course {
    $course = Current-Course
    if ($null -eq $course) { Notice '请先选择一门课程。'; return }
    $validated = Valid-CourseArgs $course
    if ($null -eq $validated) { Notice '课程 ID 尚未读取成功，请先同步课程。'; return }
    if ($null -ne $script:playerProcess) {
        try {
            $script:playerProcess.Refresh()
            if (-not $script:playerProcess.HasExited) {
                Notice '官方学习窗口已经打开。如果已最小化，请从 Windows 任务栏恢复。为避免重复播放，请先关闭原窗口。'
                return
            }
        } catch { }
    }
    $playerScript = Join-Path $script:root 'Official-Player.ps1'
    if (-not (Test-Path -LiteralPath $playerScript -PathType Leaf)) { Notice '缺少官方播放器文件，请重新安装本版。'; return }
    $speed = if ($script:playbackSpeed -in @('1','1.25','1.5','2')) { $script:playbackSpeed } else { '1.5' }
    $cliArgs = @('-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"'+$playerScript+'"'),'-CourseType',$validated[0],'-CourseId',$validated[1],'-ClassId',$validated[2],'-Speed',$speed)
    if ($validated[0] -eq 'shared') {
        $route = [string]$course.recruitAndCourseId
        if ($route -notmatch '^[A-Za-z0-9_+./=:-]{1,512}$') {
            Notice '共享课缺少安全有效的官方课程路由参数。请先重新同步课程，再打开播放窗口。'
            return
        }
        $cliArgs += @('-RecruitAndCourseId', $route)
    }
    if ($script:allowMinimize) { $cliArgs += '-AllowMinimize' }
    if ($script:autoStart) { $cliArgs += '-AutoStart' }
    if ($script:autoNext) { $cliArgs += '-AutoNext' }
    try {
        $script:playerProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $cliArgs -WorkingDirectory $env:USERPROFILE -PassThru
        $script:playerCourse = $course
        $script:playerOpenedAt = Get-Date
        (Control 'SyncMessageText').Text = '已启动官方课程门户窗口；请在网页内登录后进入选中课程。目标倍速 '+$speed+'×。真实学习记录由官方播放器负责，按需核验。'
    } catch { Notice '官方学习窗口启动失败，请检查 Install-WebView2.ps1 与安装结果。' }
}


# On normal player closure, re-read SERVER state for precisely the opened course.
# If the user switched selections, the old course is still the verification target.
function Check-PlayerExit {
    if ($null -eq $script:playerProcess) { return }
    try {
        $script:playerProcess.Refresh()
        if (-not $script:playerProcess.HasExited) { return }
    } catch { return }
    $previousCourse = $script:playerCourse
    $exitCode = -1
    try { $exitCode = $script:playerProcess.ExitCode } catch { }
    $script:playerProcess = $null
    $script:playerCourse = $null
    $script:playerOpenedAt = $null
    if ($null -eq $previousCourse) { return }
    if ($exitCode -eq 22) {
        (Control 'SyncMessageText').Text = '已改用系统浏览器观看：外部浏览器关闭时间未知。观看完成后请手动点击“核验此课进度”。'
        return
    }
    # Do not discard short study sessions. Defer until existing read tasks exit.
    $script:pendingVerifyCourse = $previousCourse
    Save-PendingVerify
    (Control 'SyncMessageText').Text = '播放窗口已关闭。服务器只读核验已排队，其他同步任务结束后自动执行。'
}
function Check-PendingVerify {
    if ($null -eq $script:pendingVerifyCourse) { return }
    if (Any-TaskActive) { return }
    if ($null -ne $script:monitorProcess) {
        try {
            $script:monitorProcess.Refresh()
            if (-not $script:monitorProcess.HasExited) { return }
        } catch { return }
    }
    $target = $script:pendingVerifyCourse
    if (Launch-Verify $true $target) {
        $script:pendingVerifyCourse = $null
        Remove-Item -LiteralPath $script:pendingVerifyPath -Force -ErrorAction SilentlyContinue
    }
}
function Toggle-Monitor {
    if ($null -ne $script:monitorCourse) { Stop-Monitor; return }
    $c = Current-Course
    if ($null -eq (Valid-CourseArgs $c)) { Notice '请先同步并选择有有效课程 ID 的课程。'; return }
    $script:monitorCourse = $c
    $script:monitorTimer.Start()
    Launch-Verify $true
    Update-MonitorDisplay
}
function Delete-LocalFiles([string]$title, [string[]]$names, [string]$explanation) {
    if ($null -ne $script:monitorCourse) { Stop-Monitor }
    if (Any-TaskActive) { Notice '检测到任务仍在运行。为避免删除后重新写回，请先结束任务窗口。'; return }
    if ($null -ne $script:monitorProcess) {
        try {
            $script:monitorProcess.Refresh()
            if (-not $script:monitorProcess.HasExited) { Notice '服务器核验正在运行，请完成核验后再删除。'; return }
        } catch { Notice '无法确认核验任务状态，请稍后重试。'; return }
    }
    if ($null -ne $script:pendingVerifyCourse) {
        Notice '有一门课程的进度核验尚未完成。请等待核验结束后再清理数据。'
        return
    }
    $answer = [System.Windows.MessageBox]::Show($script:window, ($explanation + "`n`n仅处理 $script:dataDir 中列出的文件。操作不可撤销，确认继续？"), $title, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $count = 0; $failed = @()
    foreach ($name in $names) {
        $target = Join-Path $script:dataDir $name
        try {
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force -ErrorAction Stop
                $count++
            }
        } catch { $failed += $name }
    }
    if ($failed.Count -gt 0) { Notice ('以下文件删除失败，请检查权限：' + ($failed -join ', ')) }
    else { Notice "已删除 $count 个已存在的本地文件。" }
    Refresh-Cache -Force
}
function Format-Time([string]$timestamp) {
    if ([string]::IsNullOrWhiteSpace($timestamp)) { return '尚未同步' }
    try { return ([DateTimeOffset]::Parse($timestamp)).ToLocalTime().ToString('yyyy-MM-dd HH:mm') }
    catch { return '时间未知' }
}
function Find-Progress($course) {
    if ($null -eq $course) { return $null }
    foreach ($p in $script:progressCourses) {
        if ($null -eq $p -or [string]$course.courseType -ne [string]$p.courseType) { continue }
        if ($course.courseType -eq 'ai') {
            if ([string]$course.courseId -eq [string]$p.courseId -and [string]$course.classId -eq [string]$p.classId) { return $p }
        } else {
            $route = [string]$course.recruitAndCourseId
            if (-not [string]::IsNullOrWhiteSpace($route)) {
                if ($route -ceq [string]$p.recruitAndCourseId) { return $p }
            } elseif ([string]$course.courseId -ne '0' -and [string]$course.courseId -eq [string]$p.courseId) { return $p }
        }
    }
    return $null
}
function Add-Text($parent, [string]$value, [int]$fontSize, [string]$color = '#192A42', [bool]$semibold = $false) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $value; $t.FontSize = $fontSize
    $t.TextWrapping = 'Wrap'
    $t.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    if ($semibold) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    [void]$parent.Children.Add($t)
    return $t
}
function New-CourseCard($course, [int]$index) {
    $progress = Find-Progress $course
    $card = New-Object System.Windows.Controls.Border
    $card.Background = [System.Windows.Media.Brushes]::White
    $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E4EBF3')
    $card.BorderThickness = [System.Windows.Thickness]::new(1)
    $card.CornerRadius = [System.Windows.CornerRadius]::new(14)
    $card.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    $card.Padding = [System.Windows.Thickness]::new(18)
    $stack = New-Object System.Windows.Controls.StackPanel
    $card.Child = $stack
    $title = Add-Text $stack ([string]$course.name) 16 '#1A2B42' $true
    $title.Margin = [System.Windows.Thickness]::new(0,0,0,7)
    if ($null -eq $progress) {
        $description = if ($course.courseType -eq 'ai') { '智慧课程 · 暂无知识点进度' } else { '共享课 · 暂无视频进度' }
    } elseif ($course.courseType -eq 'ai') {
        $description = "智慧课程 · 已达满进度知识点 $($progress.fullProgressPoints) / $($progress.knowledgePointCount)（非整体掌握度）"
    } else {
        $description = "共享课 · 已完成视频 $($progress.completedVideos) / $($progress.videoCount)"
    }
    if (($null -ne $progress -and $progress.stale) -or $course.stale) { $description += ' · 历史缓存待确认' }
    $subtitle = Add-Text $stack $description 12 '#75869B'
    $subtitle.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    $partTotal = if ($course.courseType -eq 'ai') { [double]$progress.knowledgePointCount } else { [double]$progress.videoCount }
    $partDone = if ($course.courseType -eq 'ai') { [double]$progress.fullProgressPoints } else { [double]$progress.completedVideos }
    if ($null -ne $progress -and $partTotal -gt 0) {
        $bar = New-Object System.Windows.Controls.ProgressBar
        $bar.Height = 8; $bar.Minimum = 0; $bar.Maximum = 100
        $bar.Value = [Math]::Min(100,[Math]::Max(0, (100.0 * $partDone / $partTotal)))
        $bar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2369D9')
        $bar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E9EEF5')
        $bar.Margin = [System.Windows.Thickness]::new(0,0,0,12)
        [void]$stack.Children.Add($bar)
    }
    $button = New-Object System.Windows.Controls.Button
    $button.Content = if ($course.courseType -eq 'ai') { '查看知识点  ›' } else { '查看视频详情  ›' }
    $button.Tag = $index
    $button.HorizontalAlignment = 'Left'
    $button.Style = $script:window.Resources['SecondaryButton']
    $button.Margin = [System.Windows.Thickness]::new(0)
    $button.Add_Click({ param($sender,$eventArgs) Select-Course ([int]$sender.Tag); Show-Page 'detail' })
    [void]$stack.Children.Add($button)
    return $card
}
function Select-Course([int]$index) {
    if ($script:selectedCourseIndex -ne $index -and $null -ne $script:monitorCourse) { Stop-Monitor }
    $script:selectedCourseIndex = $index
    $p = Control 'VideoListPanel'; $p.Children.Clear()
    if ($index -lt 0 -or $index -ge $script:courses.Count) {
        (Control 'DetailTitleText').Text = '选择左侧课程查看学习项目'
        (Control 'DetailMetaText').Text = '只展示上次成功同步的服务器学习记录'
        return
    }
    $course = $script:courses[$index]
    (Control 'DetailTitleText').Text = [string]$course.name
    $progress = Find-Progress $course
    if ($null -eq $progress) {
        (Control 'DetailMetaText').Text = '暂无该课程的学习进度。先返回首页同步学习进度。'
        [void](Add-Text $p '没有可以展示的学习记录。' 13 '#7B879A')
        Update-MonitorDisplay
        return
    }
    if ($course.courseType -eq 'ai') {
        (Control 'DetailMetaText').Text = "智慧课程知识点：已达满进度 $($progress.fullProgressPoints) / $($progress.knowledgePointCount)。此数值不等于官方的课程总进度或掌握度。"
        if ($progress.stale -or $course.stale) { (Control 'DetailMetaText').Text += ' · 历史缓存，尚未重新核验。' }
        $points = @($progress.knowledgePoints) | Where-Object { $null -ne $_ }
        if ($points.Count -eq 0) { [void](Add-Text $p '暂未返回可展示的知识点。' 13 '#7B879A') }
        foreach ($point in $points) {
            $row = New-Object System.Windows.Controls.Border
            $row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F8FAFD')
            $row.CornerRadius = [System.Windows.CornerRadius]::new(10)
            $row.Margin = [System.Windows.Thickness]::new(0,0,0,9)
            $row.Padding = [System.Windows.Thickness]::new(13)
            $info = New-Object System.Windows.Controls.StackPanel
            $row.Child = $info
            [void](Add-Text $info ([string]$point.name) 13 '#192A42' $true)
            $desc = [string]$point.theme + ' · 知识点学习进度 ' + [string]$point.progressPercent + '%'
            [void](Add-Text $info $desc 11 '#74869D')
            [void]$p.Children.Add($row)
        }
        Update-MonitorDisplay
        return
    }
    (Control 'DetailMetaText').Text = "服务器上次记录：已完成 $($progress.completedVideos) / $($progress.videoCount) 个视频。只读缓存，不代表实时刷新。"
    if ($progress.stale -or $course.stale) { (Control 'DetailMetaText').Text += ' · 历史缓存，尚未重新核验。' }
    $videos = @($progress.videos) | Where-Object { $null -ne $_ }
    if ($videos.Count -eq 0) { [void](Add-Text $p '此课程没有返回可展示的视频。' 13 '#7B879A') }
    foreach ($video in $videos) {
        $row = New-Object System.Windows.Controls.Border
        $row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F8FAFD')
        $row.CornerRadius = [System.Windows.CornerRadius]::new(10)
        $row.Margin = [System.Windows.Thickness]::new(0,0,0,9)
        $row.Padding = [System.Windows.Thickness]::new(13)
        $info = New-Object System.Windows.Controls.StackPanel
        $row.Child = $info
        $vname = Add-Text $info ([string]$video.name) 13 '#192A42' $true
        $vname.Margin = [System.Windows.Thickness]::new(0,0,0,6)
        $status = if ($video.serverCompleted) { '服务器已完成' } else { '未完成 / 未确认' }
        $desc = $status + '  ·  已记录 ' + [string]$video.studiedSeconds + ' 秒 / 总 ' + [string]$video.durationSeconds + ' 秒'
        [void](Add-Text $info $desc 11 '#74869D')
        [void]$p.Children.Add($row)
    }
    Update-MonitorDisplay
}
function Render-Data {
    (Control 'CourseCountText').Text = if ($script:hasCourses) { [string]$script:courses.Count } else { '—' }
    $finished = 0; $total = 0; $confirmedRows = 0; $cachedRows = 0
    foreach ($c in $script:progressCourses) {
        if ($null -eq $c) { continue }
        # Do not aggregate a past snapshot as if it had just been verified.
        if ($c.stale) { $cachedRows++; continue }
        $confirmedRows++
        if ($c.courseType -eq 'ai') { $finished += [int]$c.fullProgressPoints; $total += [int]$c.knowledgePointCount }
        elseif ($c.courseType -eq 'shared') { $finished += [int]$c.completedVideos; $total += [int]$c.videoCount }
    }
    $showCounts = $script:hasProgress -and ($confirmedRows -gt 0 -or $script:progressCourses.Count -eq 0)
    (Control 'CompletedCountText').Text = if ($showCounts) { [string]$finished } else { '—' }
    (Control 'PendingCountText').Text = if ($showCounts) { [string]([Math]::Max(0,$total-$finished)) } else { '—' }
    (Control 'CourseSyncTimeText').Text = if ($script:hasCourses) { '课程同步：' + (Format-Time $script:coursesTimestamp) } else { '尚无课程缓存' }
    Update-LoginState
    $container = Control 'HomeCourseCards'; $container.Children.Clear()
    $left = Control 'CourseListPanel'; $left.Children.Clear()
    if ($script:courses.Count -eq 0) {
        $message = if ($script:hasCourses) { '当前账号没有返回共享课或智慧课程；如官方 App 有课程，请检查同步窗口中的错误。' } else { '还没有同步课程。进入设置扫码登录，再点击上方“同步课程”。' }
        $empty = New-Object System.Windows.Controls.Border
        $empty.Background = [System.Windows.Media.Brushes]::White
        $empty.CornerRadius = [System.Windows.CornerRadius]::new(12)
        $empty.Padding = [System.Windows.Thickness]::new(24)
        [void](Add-Text ($content = New-Object System.Windows.Controls.StackPanel) $message 13 '#77849A')
        $empty.Child = $content
        [void]$container.Children.Add($empty)
        [void](Add-Text $left '暂无课程数据' 12 '#77849A')
        Select-Course -1
    } else {
        for ($i = 0; $i -lt $script:courses.Count; $i++) {
            [void]$container.Children.Add((New-CourseCard $script:courses[$i] $i))
            $listBtn = New-Object System.Windows.Controls.Button
            $listBtn.Content = [string]$script:courses[$i].name
            $listBtn.Tag = $i
            $listBtn.Style = $script:window.Resources['SecondaryButton']
            $listBtn.HorizontalContentAlignment = 'Left'
            $listBtn.HorizontalAlignment = 'Stretch'
            $listBtn.Padding = [System.Windows.Thickness]::new(12)
            $listBtn.Margin = [System.Windows.Thickness]::new(0,0,0,8)
            $listBtn.Add_Click({ param($sender,$e) Select-Course ([int]$sender.Tag) })
            [void]$left.Children.Add($listBtn)
        }
        if ($script:selectedCourseIndex -ge 0 -and $script:selectedCourseIndex -lt $script:courses.Count) { Select-Course $script:selectedCourseIndex }
        else { Select-Course 0 }
    }
    if ($script:hasProgress) {
        (Control 'BottomStatusText').Text = 'V5.2.8 · 最近一次同步的进度：' + (Format-Time $script:progressTimestamp) + ' · 非官方双模式工具'
        if ($cachedRows -gt 0) { (Control 'BottomStatusText').Text += ' · ' + $cachedRows + ' 门历史缓存未计入汇总' }
    } else {
        (Control 'BottomStatusText').Text = 'V5.2.8 · 尚无进度缓存 · 非官方知到 App 工具'
    }
}
function Get-CacheSignature {
    $p = @($script:coursesPath, $script:progressPath, $script:cookiePath, (Join-Path $script:dataDir 'zhidao-cache-salt.bin'))
    return (($p | ForEach-Object { if (Test-Path -LiteralPath $_) { (Get-Item -LiteralPath $_).LastWriteTimeUtc.Ticks.ToString() } else { '0' } }) -join '|')
}
function Refresh-Cache([switch]$Force) {
    $signature = Get-CacheSignature
    if (-not $Force -and $signature -eq $script:previousSignature) { return }
    $script:previousSignature = $signature
    $script:courses = @(); $script:progressCourses = @(); $script:hasCourses = $false; $script:hasProgress = $false
    $script:coursesTimestamp = ''; $script:progressTimestamp = ''
    $currentFingerprint = Get-SessionFingerprint
    if (-not $currentFingerprint -and (Test-Path -LiteralPath $script:coursesPath)) {
        (Control 'SyncMessageText').Text = '当前没有可验证的登录会话；旧课程缓存已隐藏，请扫码登录后重新同步。'
    }
    if (Test-Path -LiteralPath $script:coursesPath) {
        try {
            $data = Get-Content -LiteralPath $script:coursesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data.source -eq 'zhidao' -and $currentFingerprint -and [string]$data.sessionFingerprint -ceq $currentFingerprint) {
                $script:courses = @(@($data.courses) | Where-Object { $null -ne $_ })
                $script:hasCourses = $true
                $script:coursesTimestamp = [string]$data.fetchedAt
                if ($null -ne $data.failedSources -and @($data.failedSources | Where-Object { $null -ne $_ }).Count -gt 0) {
                    $labels = @($data.failedSourceDetails | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_.source+' ['+[string]$_.code+']') })
                    (Control 'SyncMessageText').Text = '课程来源读取失败：'+($labels -join '、')+'；旧缓存保留。登录/网络或接口问题请看同步窗口。'
                } elseif ($null -ne $data.unconfirmedEmptySources -and @($data.unconfirmedEmptySources | Where-Object { $null -ne $_ }).Count -gt 0) {
                    (Control 'SyncMessageText').Text = '课程接口返回空列表，但之前保存过课程；显示历史缓存待确认，不代表同步成功。请核对官方课程并重新同步。'
                }
            } elseif ($data.source -eq 'zhidao') {
                (Control 'SyncMessageText').Text = '检测到旧版本或其他登录会话的课程缓存；已隐藏。请重新同步当前账号。'
            }
        } catch { (Control 'SyncMessageText').Text = '课程缓存读取失败；请重新同步课程。' }
    }
    if (Test-Path -LiteralPath $script:progressPath) {
        try {
            $data = Get-Content -LiteralPath $script:progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data.source -eq 'zhidao' -and $currentFingerprint -and [string]$data.sessionFingerprint -ceq $currentFingerprint) {
                $script:progressCourses = @(@($data.courses) | Where-Object { $null -ne $_ })
                $script:hasProgress = $true
                $script:progressTimestamp = [string]$data.fetchedAt
                if ($data.incomplete) { (Control 'SyncMessageText').Text = '进度核验尚未完整完成；部分内容可能来自历史缓存，请检查同步窗口。' }
            }
        } catch { (Control 'SyncMessageText').Text = '学习进度缓存读取失败；请重新同步进度。' }
    }
    Render-Data
}
function Show-Page([string]$page) {
    (Control 'PageHome').Visibility = if ($page -eq 'home') { 'Visible' } else { 'Collapsed' }
    (Control 'PageDetail').Visibility = if ($page -eq 'detail') { 'Visible' } else { 'Collapsed' }
    (Control 'PageSettings').Visibility = if ($page -eq 'settings') { 'Visible' } else { 'Collapsed' }
    switch ($page) {
        'home' { (Control 'PageHeading').Text = '我的课程'; (Control 'PageSubtitle').Text = '查看本人课程与服务器学习进度' }
        'detail' { (Control 'PageHeading').Text = '课程详情'; (Control 'PageSubtitle').Text = '共享课视频与智慧课程知识点进度' }
        'settings' { (Control 'PageHeading').Text = '设置与隐私'; (Control 'PageSubtitle').Text = '登录、数据管理和开源信息' }
    }
    foreach ($entry in @(@('NavHome','home'),@('NavDetail','detail'),@('NavSettings','settings'))) {
        $btn = Control $entry[0]
        if ($page -eq $entry[1]) {
            $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2F527A')
            $btn.Foreground = [System.Windows.Media.Brushes]::White
        } else {
            $btn.Background = [System.Windows.Media.Brushes]::Transparent
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C9D6E9')
        }
    }
}

if (-not (Test-Path -LiteralPath $script:python -PathType Leaf)) {
    [System.Windows.MessageBox]::Show('尚未完成安装。请先运行 V5.2.8 安装程序。') | Out-Null
    exit 1
}
if (-not (Ask-Consent)) { exit 0 }
$script:window = Load-Xaml (Join-Path $script:root 'Zhidao-UI.xaml')
# Only trusted fixed strings are accepted as a saved mode; never execute file contents.
try {
    if (Test-Path -LiteralPath $script:modePath -PathType Leaf) {
        $saved = (Get-Content -LiteralPath $script:modePath -Raw -Encoding UTF8).Trim()
        if ($saved -in @('official','zhs-original')) { $script:playMode = $saved }
    }
} catch { }


# Playback settings are separate from ZHS; preserve the original ZHS upstream package.
try {
    if (Test-Path -LiteralPath $script:playerSettingsPath -PathType Leaf) {
        $pref = Get-Content -LiteralPath $script:playerSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$pref.speed -in @('1','1.25','1.5','2')) { $script:playbackSpeed = [string]$pref.speed }
        if ($null -ne $pref.allowMinimize) { $script:allowMinimize = [bool]$pref.allowMinimize }
        if ($null -ne $pref.autoStart) { $script:autoStart = [bool]$pref.autoStart }
        if ($null -ne $pref.autoNext) { $script:autoNext = [bool]$pref.autoNext }
    }
} catch { }
$sp = Control 'PlaybackSpeedSelector'
$sp.SelectedIndex = switch ($script:playbackSpeed) { '1' {0} '1.25' {1} '1.5' {2} '2' {3} default {2} }
$sp.Add_SelectionChanged({
    $index = (Control 'PlaybackSpeedSelector').SelectedIndex
    if ($index -lt 0 -or $index -gt 3) { return }
    $script:playbackSpeed = @('1','1.25','1.5','2')[$index]
    Save-PlayerSettings
})
$minCheck = Control 'AllowMinimizeCheck'
$minCheck.IsChecked = $script:allowMinimize
$minCheck.Add_Checked({ $script:allowMinimize = $true; Save-PlayerSettings })
$minCheck.Add_Unchecked({ $script:allowMinimize = $false; Save-PlayerSettings })

$startCheck = Control 'AutoStartCheck'
$startCheck.IsChecked = $script:autoStart
$startCheck.Add_Checked({ $script:autoStart = $true; Save-PlayerSettings })
$startCheck.Add_Unchecked({ $script:autoStart = $false; Save-PlayerSettings })
$nextCheck = Control 'AutoNextCheck'
$nextCheck.IsChecked = $script:autoNext
$nextCheck.Add_Checked({ $script:autoNext = $true; Save-PlayerSettings })
$nextCheck.Add_Unchecked({ $script:autoNext = $false; Save-PlayerSettings })
$modeSelector = Control 'PlaybackModeSelector'
$modeSelector.SelectedIndex = if ($script:playMode -eq 'zhs-original') { 1 } else { 0 }
$modeSelector.Add_SelectionChanged({
    $selected = if ((Control 'PlaybackModeSelector').SelectedIndex -eq 1) { 'zhs-original' } else { 'official' }
    Set-PlaybackMode $selected
})
(Control 'NavHome').Add_Click({ Show-Page 'home' })
(Control 'NavDetail').Add_Click({ Show-Page 'detail' })
(Control 'NavSettings').Add_Click({ Show-Page 'settings' })
(Control 'BtnSyncCourses').Add_Click({ Start-Task 'courses' })
(Control 'BtnSyncProgress').Add_Click({ Start-Task 'progress' })
(Control 'BtnLogin').Add_Click({ Start-Task 'login' })
(Control 'BtnDiagnose').Add_Click({ Start-Task 'doctor' })
(Control 'BtnQR').Add_Click({
    if (Test-Path -LiteralPath $script:qrPath -PathType Leaf) { Start-Process -FilePath $script:qrPath }
    else { Notice '二维码尚未生成。请先点击扫码登录，等待命令窗口生成二维码。' }
})
(Control 'BtnDataFolder').Add_Click({
    if (-not (Test-Path -LiteralPath $script:dataDir)) { New-Item -ItemType Directory -Path $script:dataDir -Force | Out-Null }
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $script:dataDir + '"')
})
(Control 'BtnSignOut').Add_Click({
    Delete-LocalFiles '退出登录' @('cookies.json','qrcode.png') '删除本机 Cookie 和二维码；旧课程缓存会保留在磁盘但不再显示，重新登录后请同步。该操作不会撤销服务器端所有会话。'
})
(Control 'BtnClearWebLogin').Add_Click({
    if ($null -ne $script:playerProcess) {
        try {
            $script:playerProcess.Refresh()
            if (-not $script:playerProcess.HasExited) {
                Notice '请先关闭官方视频播放窗口，再清理网页登录状态。'
                return
            }
        } catch { }
    }
    $answer = [System.Windows.MessageBox]::Show($script:window,'这将删除本机内嵌官方浏览器的全部网页 Cookie、会话及缓存。不会删除 Python ZHS 的登录态。确认继续？',
        '清除官方浏览器登录数据',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning,[System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $folder = Join-Path $script:root 'official-webview-profile'
    try {
        if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop }
        Notice '本地官方浏览器登录数据已清除。'
    } catch { Notice '删除失败，请确认所有官方播放窗口均已关闭。' }
})
(Control 'BtnClearData').Add_Click({
    Delete-LocalFiles '清理知到学习数据' @('zhidao-courses.json','zhidao-progress.json') '仅删除本程序生成的课程和学习进度缓存，不会影响知到官方服务器，也不删除 Cookie。'
})
(Control 'BtnTerms').Add_Click({ Show-Document '第三方使用声明' $script:termsPath })
(Control 'BtnPrivacy').Add_Click({ Show-Document '隐私与数据说明' $script:privacyPath })
(Control 'BtnLicense').Add_Click({ Show-Document 'GNU GPL v3 许可全文' $script:licensePath })
(Control 'BtnOfficial').Add_Click({ Start-Process 'https://www.zhihuishu.com/' })
(Control 'BtnOpenLearning').Add_Click({ Start-Selected-Mode })
(Control 'BtnVerifyOne').Add_Click({ Launch-Verify $false })
(Control 'BtnMonitorToggle').Add_Click({ Toggle-Monitor })
$script:monitorTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:monitorTimer.Interval = [TimeSpan]::FromSeconds(120)
$script:monitorTimer.Add_Tick({ if ($null -ne $script:monitorCourse) { Launch-Verify $true } })
$script:timer = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromSeconds(3)
$script:timer.Add_Tick({
    try { Check-TaskExit; Check-PlayerExit; Check-VerifyExit; Check-PendingVerify; Refresh-Cache } catch { (Control 'SyncMessageText').Text = '刷新界面失败；可尝试重新启动应用。' }
})
$script:window.Add_Closed({ $script:timer.Stop(); $script:monitorTimer.Stop(); Save-PendingVerify })
Refresh-Cache -Force
Load-PendingVerify
Show-Page 'home'
$script:timer.Start()
[void]$script:window.ShowDialog()
