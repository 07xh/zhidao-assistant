# Visual-only Windows PowerShell 5.1 smoke test; no ZHS login or network.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
$script:root = Join-Path ([IO.Path]::GetTempPath()) ('zhidao-appearance-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:root -Force | Out-Null
try {
    $script:window = [System.Windows.Markup.XamlReader]::Parse(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload\Zhidao-UI.xaml') -Raw -Encoding UTF8))
    function Control([string]$name) {
        $found = $script:window.FindName($name)
        if ($null -eq $found) { throw ('Missing control ' + $name) }
        return $found
    }
    . (Join-Path $PSScriptRoot 'payload\UiAppearance.ps1')
    Initialize-UiAppearance
    if ($script:uiThemeMode -ne 'light') { throw 'Default appearance must be light' }
    $lightColor = [string](Get-UiBrush 'UiBackground_FFFFFF').Color
    Apply-UiTheme 'dark'
    $darkColor = [string](Get-UiBrush 'UiBackground_FFFFFF').Color
    if ($lightColor -eq $darkColor -or $script:uiThemeMode -ne 'dark') { throw 'Dark theme did not change WPF brush' }
    if ((Control 'BtnThemeToggle').Content -ne '切换浅色模式') { throw 'Theme switch button not updated' }
    [IO.File]::WriteAllText($script:uiThemePath,'dark',[Text.UTF8Encoding]::new($false))
    Apply-UiTheme 'light'
    Initialize-UiAppearance
    if ($script:uiThemeMode -ne 'dark') { throw 'Saved theme was not restored' }
    if ((Control 'HomeCourseCards') -isnot [System.Windows.Controls.WrapPanel]) { throw 'Course list must be responsive WrapPanel' }
    $script:window.Width = 850
    Update-UiLayout
    $rootGrid = [System.Windows.Controls.Grid]$script:window.Content
    if ([int]$rootGrid.ColumnDefinitions[0].Width.Value -ne 78) { throw 'Compact sidebar not enabled' }
    if ((Control 'SidebarBrandText').Visibility -ne 'Collapsed' -or
        (Control 'NavHome').Content -ne '▣') { throw 'Compact navigation is not accessible' }
    $script:window.Width = 1180
    Update-UiLayout
    if ([int]$rootGrid.ColumnDefinitions[0].Width.Value -ne 236) { throw 'Full sidebar did not restore' }
    if ((Control 'SidebarBrandText').Visibility -ne 'Visible' -or
        (Control 'NavHome').Content -notmatch '我的课程') { throw 'Full navigation was not restored' }
    Apply-UiTheme 'light'
    if ([string](Get-UiBrush 'UiBackground_FFFFFF').Color -ne $lightColor) { throw 'Light palette not restored' }
    Write-Host 'PASS: WPF appearance, saved theme and responsive sidebar'
} finally {
    Remove-Item -LiteralPath $script:root -Force -Recurse -ErrorAction SilentlyContinue
}
