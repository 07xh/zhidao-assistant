# Dynamic course card smoke tests with fake user data; no backend calls or heartbeats.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
$script:root = Join-Path ([IO.Path]::GetTempPath()) ('zhidao-cards-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:root -Force | Out-Null
try {
    $script:window = [System.Windows.Markup.XamlReader]::Parse(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload\Zhidao-UI.xaml') -Raw -Encoding UTF8))
    function Control([string]$name) {
        return $script:window.FindName($name)
    }
    function Find-Progress($course) { return $script:sampleProgress }
    function Add-Text($parent,[string]$value,[int]$fontSize,[string]$color='#192A42',[bool]$semibold=$false) {
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = $value; $t.FontSize = $fontSize
        $t.TextWrapping = 'Wrap'
        $t.Foreground = Get-UiTextBrush $color
        if ($semibold) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
        [void]$parent.Children.Add($t)
        return $t
    }
    . (Join-Path $PSScriptRoot 'payload\UiAppearance.ps1')
    . (Join-Path $PSScriptRoot 'payload\UiCourseCards.ps1')
    Initialize-UiAppearance
    $course = [pscustomobject]@{ courseType='ai';name='虚构测试课程';courseId='101';classId='201';stale=$false }
    $script:sampleProgress = $null
    $card = New-CourseCard $course 0
    if ($card.Child.Children[0].Children[1].Child.Text -ne '未核验') { throw 'No progress was incorrectly verified' }
    if (@($card.Child.Children | Where-Object { $_ -is [System.Windows.Controls.ProgressBar] }).Count -ne 0) {
        throw 'No progress should not render fabricated percentage'
    }
    $script:sampleProgress = [pscustomobject]@{
        courseType='ai';courseId='101';classId='201';stale=$true;
        lastVerifiedAt='2026-01-01T00:00:00Z';knowledgePointCount=4;fullProgressPoints=2
    }
    $card = New-CourseCard $course 1
    if ($card.Child.Children[0].Children[1].Child.Text -ne '历史缓存') { throw 'Stale progress was not labeled' }
    if (@($card.Child.Children | Where-Object { $_ -is [System.Windows.Controls.ProgressBar] }).Count -ne 0) {
        throw 'Stale progress must not present a current percentage'
    }
    $script:sampleProgress.stale = $false
    $card = New-CourseCard $course 2
    $bars = @($card.Child.Children | Where-Object { $_ -is [System.Windows.Controls.ProgressBar] })
    if ($card.Child.Children[0].Children[1].Child.Text -ne '上次已核验' -or $bars.Count -ne 1 -or $bars[0].Value -ne 50) {
        throw 'Last verified course count did not render as an item ratio'
    }
    $script:sampleProgress.lastVerifiedAt = $null
    $card = New-CourseCard $course 3
    if (@($card.Child.Children | Where-Object { $_ -is [System.Windows.Controls.ProgressBar] }).Count -ne 0) {
        throw 'Unverified data must not expose a percent bar'
    }
    Apply-UiTheme 'dark'
    $card = New-CourseCard $course 4
    if ([string]$card.Background.Color -eq '#FFFFFFFF') { throw 'Dynamic cards did not adopt dark palette' }
    Write-Host 'PASS: WPF course cards preserve no-data, stale, verified and dark states'
} finally {
    Remove-Item -LiteralPath $script:root -Force -Recurse -ErrorAction SilentlyContinue
}
