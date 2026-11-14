# WPF presentation-only light/dark palette and responsive layout. No network/auth/heartbeat code.
# Theme brushes are all defined in Zhidao-UI.xaml and referenced with DynamicResource.
$script:uiThemeMode = 'light'
$script:uiThemePath = Join-Path $script:root 'appearance-mode.txt'
$script:uiDarkColors = @{
    'UiBackground_13213A' = '#0D182A'
    'UiBackground_326FE5' = '#3E74D8'
    'UiBackground_344B6A' = '#243550'
    'UiBackground_3975E8' = '#426FCD'
    'UiBackground_E3EAF3' = '#35465E'
    'UiBackground_E9F0FB' = '#2A405F'
    'UiBackground_EDF3FC' = '#243A58'
    'UiBackground_F0E6D5' = '#433628'
    'UiBackground_F2F5FA' = '#0E1726'
    'UiBackground_F7FAFE' = '#1B2C45'
    'UiBackground_F7FCFA' = '#16372F'
    'UiBackground_F8FBFF' = '#172B46'
    'UiBackground_FFF0F1' = '#46303B'
    'UiBackground_FFFBF5' = '#382E22'
    'UiBackground_FFFFFF' = '#19283D'
    'UiBorderBrush_C9D6E9' = '#304560'
    'UiBorderBrush_D9E5F7' = '#355477'
    'UiBorderBrush_DCE6F3' = '#304560'
    'UiBorderBrush_DCE7F6' = '#304560'
    'UiBorderBrush_DCE9FA' = '#355477'
    'UiBorderBrush_DCEFE8' = '#2B5A49'
    'UiBorderBrush_DFE6F1' = '#304560'
    'UiBorderBrush_E1E8F3' = '#304560'
    'UiBorderBrush_F4E8D7' = '#614B33'
    'UiFill_8A9DB5' = '#9CB5D6'
    'UiForeground_1B3453' = '#E4EDFA'
    'UiForeground_1C2C43' = '#E4EDFA'
    'UiForeground_1D304C' = '#E4EDFA'
    'UiForeground_203047' = '#E4EDFA'
    'UiForeground_234F97' = '#A4C8FF'
    'UiForeground_246BC8' = '#A9BDD7'
    'UiForeground_2566B2' = '#A4C8FF'
    'UiForeground_2756A0' = '#A4C8FF'
    'UiForeground_277A68' = '#8ADBC0'
    'UiForeground_344E6E' = '#E4EDFA'
    'UiForeground_506987' = '#A9BDD7'
    'UiForeground_527F72' = '#8ADBC0'
    'UiForeground_566C87' = '#A9BDD7'
    'UiForeground_5C7596' = '#A9BDD7'
    'UiForeground_60758C' = '#A9BDD7'
    'UiForeground_62788E' = '#A9BDD7'
    'UiForeground_687B90' = '#A9BDD7'
    'UiForeground_6A7C92' = '#A9BDD7'
    'UiForeground_6F8097' = '#A9BDD7'
    'UiForeground_718096' = '#A9BDD7'
    'UiForeground_72849C' = '#BBCBE4'
    'UiForeground_75869B' = '#A9BDD7'
    'UiForeground_7795B7' = '#A9BDD7'
    'UiForeground_78869A' = '#A9BDD7'
    'UiForeground_7A899A' = '#A9BDD7'
    'UiForeground_7C8794' = '#A9BDD7'
    'UiForeground_7C8FA6' = '#A9BDD7'
    'UiForeground_8293AA' = '#A9BDD7'
    'UiForeground_87A99D' = '#8ADBC0'
    'UiForeground_8B97A9' = '#BBCBE4'
    'UiForeground_8BA0BA' = '#A9BDD7'
    'UiForeground_8EA7CB' = '#BBCBE4'
    'UiForeground_91A9CB' = '#BBCBE4'
    'UiForeground_98611A' = '#EDC38D'
    'UiForeground_98754D' = '#EDC38D'
    'UiForeground_A6B8D3' = '#BBCBE4'
    'UiForeground_AB763D' = '#EDC38D'
    'UiForeground_B24355' = '#FFAFBA'
    'UiForeground_B59D7E' = '#EDC38D'
    'UiForeground_C6D4EB' = '#D3E2F5'
    'UiForeground_CAD7EE' = '#D3E2F5'
    'UiForeground_D29433' = '#EDC38D'
}
$script:uiLightColors = @{
    'UiBackground_13213A' = '#13213A'
    'UiBackground_326FE5' = '#326FE5'
    'UiBackground_344B6A' = '#344B6A'
    'UiBackground_3975E8' = '#3975E8'
    'UiBackground_E3EAF3' = '#E3EAF3'
    'UiBackground_E9F0FB' = '#E9F0FB'
    'UiBackground_EDF3FC' = '#EDF3FC'
    'UiBackground_F0E6D5' = '#F0E6D5'
    'UiBackground_F2F5FA' = '#F2F5FA'
    'UiBackground_F7FAFE' = '#F7FAFE'
    'UiBackground_F7FCFA' = '#F7FCFA'
    'UiBackground_F8FBFF' = '#F8FBFF'
    'UiBackground_FFF0F1' = '#FFF0F1'
    'UiBackground_FFFBF5' = '#FFFBF5'
    'UiBackground_FFFFFF' = '#FFFFFF'
    'UiBorderBrush_C9D6E9' = '#C9D6E9'
    'UiBorderBrush_D9E5F7' = '#D9E5F7'
    'UiBorderBrush_DCE6F3' = '#DCE6F3'
    'UiBorderBrush_DCE7F6' = '#DCE7F6'
    'UiBorderBrush_DCE9FA' = '#DCE9FA'
    'UiBorderBrush_DCEFE8' = '#DCEFE8'
    'UiBorderBrush_DFE6F1' = '#DFE6F1'
    'UiBorderBrush_E1E8F3' = '#E1E8F3'
    'UiBorderBrush_F4E8D7' = '#F4E8D7'
    'UiFill_8A9DB5' = '#8A9DB5'
    'UiForeground_1B3453' = '#1B3453'
    'UiForeground_1C2C43' = '#1C2C43'
    'UiForeground_1D304C' = '#1D304C'
    'UiForeground_203047' = '#203047'
    'UiForeground_234F97' = '#234F97'
    'UiForeground_246BC8' = '#246BC8'
    'UiForeground_2566B2' = '#2566B2'
    'UiForeground_2756A0' = '#2756A0'
    'UiForeground_277A68' = '#277A68'
    'UiForeground_344E6E' = '#344E6E'
    'UiForeground_506987' = '#506987'
    'UiForeground_527F72' = '#527F72'
    'UiForeground_566C87' = '#566C87'
    'UiForeground_5C7596' = '#5C7596'
    'UiForeground_60758C' = '#60758C'
    'UiForeground_62788E' = '#62788E'
    'UiForeground_687B90' = '#687B90'
    'UiForeground_6A7C92' = '#6A7C92'
    'UiForeground_6F8097' = '#6F8097'
    'UiForeground_718096' = '#718096'
    'UiForeground_72849C' = '#72849C'
    'UiForeground_75869B' = '#75869B'
    'UiForeground_7795B7' = '#7795B7'
    'UiForeground_78869A' = '#78869A'
    'UiForeground_7A899A' = '#7A899A'
    'UiForeground_7C8794' = '#7C8794'
    'UiForeground_7C8FA6' = '#7C8FA6'
    'UiForeground_8293AA' = '#8293AA'
    'UiForeground_87A99D' = '#87A99D'
    'UiForeground_8B97A9' = '#8B97A9'
    'UiForeground_8BA0BA' = '#8BA0BA'
    'UiForeground_8EA7CB' = '#8EA7CB'
    'UiForeground_91A9CB' = '#91A9CB'
    'UiForeground_98611A' = '#98611A'
    'UiForeground_98754D' = '#98754D'
    'UiForeground_A6B8D3' = '#A6B8D3'
    'UiForeground_AB763D' = '#AB763D'
    'UiForeground_B24355' = '#B24355'
    'UiForeground_B59D7E' = '#B59D7E'
    'UiForeground_C6D4EB' = '#C6D4EB'
    'UiForeground_CAD7EE' = '#CAD7EE'
    'UiForeground_D29433' = '#D29433'
}
function Get-UiBrush([string]$key) {
    return $script:window.Resources[$key]
}
function Get-UiTextBrush([string]$hex) {
    if ($script:uiThemeMode -eq 'dark') {
        if ($hex -match '^#(?:[0-9a-fA-F]{6})$') {
            if ($hex -match '^#(?:2[0-9a-fA-F]{5}|1[0-9a-fA-F]{5}|3[0-9a-fA-F]{5})$') {
                return Get-UiBrush 'UiForeground_203047'
            }
            return Get-UiBrush 'UiForeground_78869A'
        }
    }
    return [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex)
}
function Apply-UiTheme([string]$mode) {
    if ($mode -notin @('light','dark')) { return }
    foreach ($key in @($script:uiDarkColors.Keys)) {
        $brush = $script:window.Resources[$key]
        if ($null -eq $brush) { throw ('Missing appearance brush: ' + $key) }
        $hex = if ($mode -eq 'dark') { $script:uiDarkColors[$key] } else { [string]$script:uiLightColors[$key] }
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        # Changing the existing brush keeps DynamicResource and runtime card references live.
        if ($brush.IsFrozen) {
            $script:window.Resources[$key] = [System.Windows.Media.SolidColorBrush]::new($color)
        } else {
            $brush.Color = $color
        }
    }
    $script:uiThemeMode = $mode
    (Control 'BtnThemeToggle').Content = if ($mode -eq 'dark') { '切换浅色模式' } else { '切换深色模式' }
    (Control 'ThemeModeText').Text = if ($mode -eq 'dark') { '当前：深色' } else { '当前：浅色' }
}
function Initialize-UiAppearance {
    $saved = 'light'
    try {
        if (Test-Path -LiteralPath $script:uiThemePath -PathType Leaf) {
            $value = (Get-Content -LiteralPath $script:uiThemePath -Raw -Encoding UTF8).Trim()
            if ($value -in @('light','dark')) { $saved = $value }
        }
    } catch { }
    Apply-UiTheme $saved
}
function Update-UiLayout {
    if ($null -eq $script:window) { return }
    $width = [double]$script:window.ActualWidth
    if ($width -lt 1) { $width = [double]$script:window.Width }
    $compact = $width -lt 980
    $sidebarWidth = if ($compact) { 78.0 } else { 236.0 }
    $root = [System.Windows.Controls.Grid]$script:window.Content
    $root.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new($sidebarWidth)
    (Control 'SidebarBrandText').Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
    (Control 'SidebarNavCaption').Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
    (Control 'SidebarFooter').Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
    foreach ($entry in @(@('NavHome','▣','▣   我的课程'),@('NavDetail','▤','▤   课程详情'),@('NavSettings','⚙','⚙   设置与隐私'))) {
        $btn = Control $entry[0]
        $btn.Content = if ($compact) { $entry[1] } else { $entry[2] }
        $btn.ToolTip = $entry[2]
    }
    # At high DPI the usable window width is measured in WPF device-independent pixels.
    $small = $width -lt 760
    (Control 'BtnLoginShortcut').Content = if ($small) { '账号' } else { '登录管理' }
    (Control 'LoginStateText').MaxWidth = if ($small) { 135 } else { 220 }
    $detail = Control 'PageDetail'
    $courseList = Control 'DetailCourseListBorder'
    $content = Control 'DetailContentBorder'
    if ($small) {
        # Keep the course picker visible above the details instead of clipping details.
        $detail.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(0)
        $detail.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(0)
        $detail.RowDefinitions[0].Height = [System.Windows.GridLength]::new(118)
        $detail.RowDefinitions[1].Height = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        [System.Windows.Controls.Grid]::SetRow($courseList,0)
        [System.Windows.Controls.Grid]::SetColumn($courseList,2)
        [System.Windows.Controls.Grid]::SetColumnSpan($courseList,1)
        [System.Windows.Controls.Grid]::SetRow($content,1)
        [System.Windows.Controls.Grid]::SetColumn($content,2)
    } else {
        $detail.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(230)
        $detail.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(14)
        $detail.RowDefinitions[0].Height = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $detail.RowDefinitions[1].Height = [System.Windows.GridLength]::new(0)
        [System.Windows.Controls.Grid]::SetRow($courseList,0)
        [System.Windows.Controls.Grid]::SetColumn($courseList,0)
        [System.Windows.Controls.Grid]::SetColumnSpan($courseList,1)
        [System.Windows.Controls.Grid]::SetRow($content,0)
        [System.Windows.Controls.Grid]::SetColumn($content,2)
    }
    $cards = Control 'HomeCourseCards'
    $available = [Math]::Max(300,$width - $sidebarWidth - 60)
    $columns = if ($available -ge 740) { 2 } else { 1 }
    $itemWidth = if ($columns -eq 2) { [Math]::Floor(($available - 30) / 2) } else { [Math]::Floor($available - 14) }
    foreach ($card in @($cards.Children)) {
        if ($card -is [System.Windows.Controls.Border]) { $card.Width = [Math]::Max(260,$itemWidth) }
    }
}
