$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
# Download progress must remain visible on first-time installs.
$env:UV_HTTP_TIMEOUT = '90'
$env:UV_HTTP_RETRIES = '2'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Join-Path $env:LOCALAPPDATA 'ZHSDesktop'
$venv = Join-Path $root '.venv'
$uv = Join-Path $root 'uv.exe'
$zhs = Join-Path $venv 'Scripts\zhs.exe'
Write-Host '== Zhidao Assistant V5.2.8 Hotfix10 Login Diagnostics Installer ==' -ForegroundColor Cyan
Write-Host 'Uses official pjm314159/zhs version 0.1.5; reads Zhidao shared courses and AI smart courses.'
if (-not [Environment]::Is64BitOperatingSystem) { throw 'Windows 10/11 x64 is required.' }
New-Item -ItemType Directory -Path $root -Force | Out-Null
# Automatically close only process instances that belong to this exact per-user install.
# Do not run an old Uninstall.ps1 here: it may remove login/runtime data or registry state.
. (Join-Path $sourceDir 'AppLifecycle.ps1')
Stop-ZhidaoAppProcesses -InstallRoot $root
function Assert-LauncherAvailable {
    $targetExe = Join-Path $root 'ZhidaoAssistant.exe'
    if (-not (Test-Path -LiteralPath $targetExe -PathType Leaf)) { return }
    try {
        $handle = [System.IO.File]::Open($targetExe, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $handle.Dispose()
    } catch [System.IO.IOException] {
        throw '旧版启动器仍被占用，不能安全替换。请检查是否有其他进程正在使用该文件；旧版程序和用户数据保持不变。'
    }
}
Assert-LauncherAvailable

# If a valid ZHS 0.1.5 environment already exists, preserve it on upgrades.
$python = Join-Path $venv 'Scripts\python.exe'
$ready = $false
if ((Test-Path -LiteralPath $python) -and (Test-Path -LiteralPath $zhs)) {
    & $python (Join-Path $sourceDir 'Verify-Environment.py')
    $ready = ($LASTEXITCODE -eq 0)
}
if ($ready) {
    Write-Host '[1/4 - 3/4] Existing ZHS 0.1.5 environment is healthy; keep existing Python and login data.'
} else {
    if (-not (Test-Path -LiteralPath $uv)) {
        Write-Host '[1/4] Getting verified uv for Windows x64: TUNA mirror -> PyPI -> GitHub.'
        # Official PyPI SHA256 for uv 0.13.7 Windows x64, independently pinned at build time.
        # Source: https://pypi.org/project/uv/0.13.7/
        $uvWheel = 'uv-0.13.7-py3-none-win_amd64.whl'
        $uvSha = '2835e2ab397d0db86323b9975dce75ecd76aa9cfa0d6a2aea84734aae7f8c9b3'
        $downloadedUv = $false
        $failures = @()
        $wheelUrl = $null
        try {
            Write-Host '    [mirror] Querying Tsinghua PyPI mirror (HTTPS)...'
            $indexUri = [Uri]'https://pypi.tuna.tsinghua.edu.cn/simple/uv/'
            $html = (Invoke-WebRequest -Uri $indexUri.AbsoluteUri -UseBasicParsing -TimeoutSec 20).Content
            foreach ($m in [regex]::Matches([string]$html, 'href\s*=\s*["'']([^"'']+)["'']')) {
                $href = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
                $candidate = [Uri]::new($indexUri, $href)
                if ($candidate.Scheme -eq 'https' -and
                    ($candidate.Host -eq 'pypi.tuna.tsinghua.edu.cn' -or $candidate.Host -eq 'mirrors.tuna.tsinghua.edu.cn') -and
                    $candidate.AbsolutePath.EndsWith('/' + $uvWheel, [StringComparison]::OrdinalIgnoreCase)) {
                    $wheelUrl = $candidate.GetLeftPart([UriPartial]::Path)
                    break
                }
            }
            if (-not $wheelUrl) { throw 'Exact pinned uv wheel not found in mirror index.' }
        } catch { $failures += ('TUNA metadata: ' + $_.Exception.Message) }

        $wheelSources = @()
        if ($wheelUrl) { $wheelSources += [pscustomobject]@{ Name='Tsinghua mirror'; Url=$wheelUrl } }
        try {
            Write-Host '    [fallback] Looking up pinned uv wheel on official PyPI...'
            $meta = Invoke-RestMethod -Uri 'https://pypi.org/pypi/uv/0.13.7/json' -TimeoutSec 20
            $entry = @($meta.urls | Where-Object { $_.filename -eq $uvWheel }) | Select-Object -First 1
            if ($null -eq $entry -or [string]$entry.digests.sha256 -ine $uvSha -or
                ([Uri]$entry.url).Host -ne 'files.pythonhosted.org') { throw 'Unexpected official PyPI wheel metadata.' }
            $wheelSources += [pscustomobject]@{ Name='PyPI official'; Url=[string]$entry.url }
        } catch { $failures += ('PyPI metadata: ' + $_.Exception.Message) }

        foreach ($src in $wheelSources) {
            $tmp = Join-Path $env:TEMP ('zhidao-uv-' + [Guid]::NewGuid().ToString('N') + '.whl')
            $unpack = Join-Path $env:TEMP ('zhidao-uv-' + [Guid]::NewGuid().ToString('N'))
            try {
                Write-Host ('    [' + $src.Name + '] Downloading uv 0.13.7 (about 15 MB)...')
                Invoke-WebRequest -Uri $src.Url -OutFile $tmp -UseBasicParsing -TimeoutSec 150
                if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ine $uvSha) {
                    throw 'SHA256 mismatch; untrusted or incomplete wheel refused.'
                }
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory($tmp, $unpack)
                $binary = Get-ChildItem -Path $unpack -Filter 'uv.exe' -File -Recurse | Select-Object -First 1
                if ($null -eq $binary) { throw 'uv.exe not found in pinned wheel.' }
                Copy-Item -LiteralPath $binary.FullName -Destination $uv -Force
                $versionText = (& $uv --version | Out-String).Trim()
                if ($LASTEXITCODE -ne 0 -or $versionText -ne 'uv 0.13.7') { throw 'uv binary version verification failed.' }
                Write-Host ('    Verified ' + $versionText + ' using official SHA256.') -ForegroundColor Green
                $downloadedUv = $true
                break
            } catch {
                $failures += ($src.Name + ' download: ' + $_.Exception.Message)
                Remove-Item -LiteralPath $uv -Force -ErrorAction SilentlyContinue
                Write-Warning ('    ' + $src.Name + ' failed; trying the next trusted source.')
            } finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $unpack -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $downloadedUv) {
            # Final fallback: original official GitHub release, with its own SHA256 digest.
            $tmp = Join-Path $env:TEMP ('zhidao-uv-' + [Guid]::NewGuid().ToString('N') + '.zip')
            $unpack = Join-Path $env:TEMP ('zhidao-uv-' + [Guid]::NewGuid().ToString('N'))
            try {
                Write-Host '    [fallback] Attempting GitHub pinned uv 0.13.7 release...'
                $headers = @{ 'User-Agent'='ZhidaoDesktopInstaller/5.2.3'; 'Accept'='application/vnd.github+json' }
                $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/astral-sh/uv/releases/tags/0.13.7' -Headers $headers -TimeoutSec 20
                $asset = @($release.assets | Where-Object { $_.name -eq 'uv-x86_64-pc-windows-msvc.zip' }) | Select-Object -First 1
                if ($null -eq $asset -or $asset.browser_download_url -notlike 'https://github.com/astral-sh/uv/releases/download/*') { throw 'Pinned GitHub asset missing.' }
                $shaMatch = [regex]::Match([string]$asset.digest, '^sha256:([0-9a-fA-F]{64})$')
                if (-not $shaMatch.Success) { throw 'Pinned GitHub archive digest missing.' }
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -TimeoutSec 150
                if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ine $shaMatch.Groups[1].Value) { throw 'GitHub archive SHA256 mismatch.' }
                Expand-Archive -LiteralPath $tmp -DestinationPath $unpack -Force
                $binary = Get-ChildItem -Path $unpack -Filter 'uv.exe' -File -Recurse | Select-Object -First 1
                if ($null -eq $binary) { throw 'uv.exe missing in GitHub archive.' }
                Copy-Item -LiteralPath $binary.FullName -Destination $uv -Force
                $versionText = (& $uv --version | Out-String).Trim()
                if ($LASTEXITCODE -ne 0 -or $versionText -ne 'uv 0.13.7') { throw 'uv binary version verification failed.' }
                $downloadedUv = $true
                Write-Host '    GitHub verified uv 0.13.7 downloaded.' -ForegroundColor Green
            } catch {
                $failures += ('GitHub: ' + $_.Exception.Message)
                throw ('[1/4] Unable to obtain uv from any verified source. Details: ' + ($failures -join ' | '))
            } finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $unpack -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-Host '[1/4] Reusing existing app-local uv; no uv download needed.'
    }

    Write-Host '[2/4] Finding Python 3.13 / 3.14, avoiding unnecessary downloads.'
    Write-Host '    Your default system Python will not be replaced.'
    $pythonSource = $null
    foreach ($minor in @('3.13', '3.14')) {
        try {
            $found = (& $uv python find --no-python-downloads $minor 2>$null | Select-Object -First 1)
            if ($LASTEXITCODE -eq 0 -and $found -and (Test-Path -LiteralPath $found -PathType Leaf)) {
                $pythonSource = [string]$found
                Write-Host ('    Reusing existing Python: ' + $pythonSource)
                break
            }
        } catch { }
    }
    if (-not $pythonSource) {
        Write-Host '    No compatible Python found. Downloading managed Python 3.13...'
        if ($env:UV_PYTHON_INSTALL_MIRROR) {
            Write-Host '    Using user-configured UV_PYTHON_INSTALL_MIRROR for CPython download.'
        } else {
            Write-Host '    Python is downloaded from uv-managed upstream. If blocked, a trusted Python mirror or fully offline installer is required.'
        }
        & $uv --verbose python install 3.13
        if ($LASTEXITCODE -ne 0) {
            throw '[2/4] Python download failed. PyPI mirrors cannot replace Python runtime downloads. Use a trusted UV_PYTHON_INSTALL_MIRROR or offline runtime package.'
        }
        $pythonSource = '3.13'
    }
    Write-Host '[3/4] Creating app environment and installing pinned ZHS 0.1.5.'
    & $uv venv --python $pythonSource $venv
    if ($LASTEXITCODE -ne 0) { throw 'Creating app environment failed.' }
    $installed = $false
    foreach ($index in @('https://pypi.tuna.tsinghua.edu.cn/simple', 'https://pypi.org/simple')) {
        Write-Host ('    Python package index: ' + $index)
        & $uv pip install --python $python --index-url $index 'zhs==0.1.5'
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $zhs -PathType Leaf)) {
            $installed = $true
            break
        }
        Write-Warning '    Package index did not succeed. Trying another trusted index.'
    }
    if (-not $installed) { throw '[3/4] ZHS installation failed on both PyPI sources.' }
    & $python (Join-Path $sourceDir 'Verify-Environment.py')
    if ($LASTEXITCODE -ne 0) { throw 'Installed ZHS 0.1.5 verification failed.' }
}
# Validate and repair the installed ZHS 0.1.5 version before enabling the app.
# Exact-file fingerprints, backup and rollback are mandatory; no heartbeat protocol changes.
Write-Host '[3.5/4] Verifying ZHS 0.1.5 reliability fixes.'
& $python (Join-Path $sourceDir 'Patch-ZHS-0.1.5.py') --apply
if ($LASTEXITCODE -ne 0) { throw 'ZHS source patch refused or failed; no user login data was removed.' }
& $python (Join-Path $sourceDir 'Patch-ZHS-0.1.5.py') --check
if ($LASTEXITCODE -ne 0) { throw 'ZHS patched source verification failed.' }
Write-Host '[4/4] Initializing application and copying launcher; Python packages are already installed.'
# ZHS uses a directory RELATIVE to the process's working directory.
# Keep CLI login and Python read-only helper in one stable user-profile directory.
Push-Location $env:USERPROFILE
try {
    $zhsData = Join-Path $env:USERPROFILE '.zhs'
    if (-not (Test-Path (Join-Path $zhsData 'config.toml'))) {
        & $zhs init
        if ($LASTEXITCODE -ne 0) { throw 'ZHS init failed.' }
    }
} finally { Pop-Location }
# A single allowlist is shared by build.py and the installed app; no duplicate list.
$manifestFile = Join-Path $sourceDir 'install-files.json'
$files = @(Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json)
if ($files.Count -lt 2 -or $files -notcontains 'ZhidaoAssistant.exe' -or
    $files -notcontains 'install-files.json') { throw 'Invalid installer resource manifest.' }
$seenNames = @{}
foreach ($name in $files) {
    if ($name -isnot [string] -or -not $name -or
        $name -eq '.' -or $name -eq '..' -or
        $name -notmatch '^[^\\/:*?"<>|]+
# Validate every payload file before modifying the previous installation.
# The Python/ZHS virtual environment and shared ~/.zhs user data are never staged/removed here.
$stageDir = Join-Path $env:TEMP ('zhidao-app-stage-' + [Guid]::NewGuid().ToString('N'))
$backupDir = Join-Path $env:TEMP ('zhidao-app-backup-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stageDir,$backupDir -Force | Out-Null
$applied = New-Object System.Collections.Generic.List[string]
$rollbackFailed = $false
try {
    foreach ($name in $files) {
        $src = Join-Path $sourceDir $name
        $staged = Join-Path $stageDir $name
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing setup file: $name" }
        Copy-Item -LiteralPath $src -Destination $staged -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash) {
            throw "Staging integrity failure: $name"
        }
        $existing = Join-Path $root $name
        if (Test-Path -LiteralPath $existing -PathType Leaf) {
            Copy-Item -LiteralPath $existing -Destination (Join-Path $backupDir $name) -Force -ErrorAction Stop
        }
    }
    foreach ($name in $files) {
        $dest = Join-Path $root $name
        if ($name -eq 'ZhidaoAssistant.exe') { Assert-LauncherAvailable }
        # Append BEFORE copy so a partial copy is included in rollback.
        [void]$applied.Add($name)
        Copy-Item -LiteralPath (Join-Path $stageDir $name) -Destination $dest -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath (Join-Path $stageDir $name) -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash) {
            throw "Installed file integrity mismatch: $name"
        }
    }
} catch {
    $cause = $_
    for ($i = $applied.Count - 1; $i -ge 0; $i--) {
        $name = $applied[$i]
        $prior = Join-Path $backupDir $name
        $dest = Join-Path $root $name
        try {
            if (Test-Path -LiteralPath $prior -PathType Leaf) {
                Copy-Item -LiteralPath $prior -Destination $dest -Force -ErrorAction Stop
            } elseif (Test-Path -LiteralPath $dest -PathType Leaf) {
                Remove-Item -LiteralPath $dest -Force -ErrorAction Stop
            }
        } catch {
            $rollbackFailed = $true
            Write-Warning "Could not restore application file: $name"
        }
    }
    if ($rollbackFailed) {
        Write-Warning ('Rollback not fully successful; recover files from ' + $backupDir)
    }
    throw $cause
} finally {
    Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $rollbackFailed) { Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue }
}
# Player dependencies are optional: lack of NuGet access triggers an explicit external browser fallback.
try {
    & (Join-Path $root 'Install-WebView2.ps1')
} catch {
    Write-Warning ('WebView2 SDK installation failed; official browser fallback remains available. ' + $_.Exception.Message)
}
# Remove only known obsolete application launchers from prior in-place versions.
# The currently installed application files were replaced with rollback above.
# Retain .venv, uv.exe, cookies, cache, and any unknown user-owned files.
foreach ($oldName in @('ZHS-CLI.cmd','ZHS-GUI.ps1')) {
    $legacy = Join-Path $root $oldName
    if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force }
}
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop '知到学习助手.lnk'))
$shortcut.TargetPath = Join-Path $root 'ZhidaoAssistant.exe'
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $env:USERPROFILE
$shortcut.Description = '知到 App 官方 WebView2 播放工具 V5.2.8（WPF）'
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,70"
$shortcut.Save()
# Register per-user uninstall entry in Windows Apps & Features (no administrator rights).
$regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ZhidaoAssistant'
New-Item -Path $regKey -Force | Out-Null
New-ItemProperty -Path $regKey -Name DisplayName -Value '知到学习助手' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name DisplayVersion -Value '5.2.8' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name Publisher -Value 'Zhidao Assistant community (unofficial)' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name InstallLocation -Value $root -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name DisplayIcon -Value (Join-Path $root 'ZhidaoAssistant.exe') -PropertyType String -Force | Out-Null
$uninstallLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'Uninstall.ps1') + '"'
New-ItemProperty -Path $regKey -Name UninstallString -Value $uninstallLine -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $regKey -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
Write-Host 'SUCCESS. Desktop shortcut: 知到学习助手 V5.2.8 (Windows test build)' -ForegroundColor Green
Write-Host 'ZHS data directory:' (Join-Path $env:USERPROFILE '.zhs')
Write-Host 'Login cookies stay in %USERPROFILE%\.zhs. The new privacy notice must be accepted at first launch.'
 -or $seenNames.ContainsKey($name)) {
        throw 'Invalid or duplicated installer resource name.'
    }
    $seenNames[$name] = $true
}

# Validate every payload file before modifying the previous installation.
# The Python/ZHS virtual environment and shared ~/.zhs user data are never staged/removed here.
$stageDir = Join-Path $env:TEMP ('zhidao-app-stage-' + [Guid]::NewGuid().ToString('N'))
$backupDir = Join-Path $env:TEMP ('zhidao-app-backup-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stageDir,$backupDir -Force | Out-Null
$applied = New-Object System.Collections.Generic.List[string]
$rollbackFailed = $false
try {
    foreach ($name in $files) {
        $src = Join-Path $sourceDir $name
        $staged = Join-Path $stageDir $name
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing setup file: $name" }
        Copy-Item -LiteralPath $src -Destination $staged -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash) {
            throw "Staging integrity failure: $name"
        }
        $existing = Join-Path $root $name
        if (Test-Path -LiteralPath $existing -PathType Leaf) {
            Copy-Item -LiteralPath $existing -Destination (Join-Path $backupDir $name) -Force -ErrorAction Stop
        }
    }
    foreach ($name in $files) {
        $dest = Join-Path $root $name
        if ($name -eq 'ZhidaoAssistant.exe') { Assert-LauncherAvailable }
        # Append BEFORE copy so a partial copy is included in rollback.
        [void]$applied.Add($name)
        Copy-Item -LiteralPath (Join-Path $stageDir $name) -Destination $dest -Force -ErrorAction Stop
        if ((Get-FileHash -LiteralPath (Join-Path $stageDir $name) -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash) {
            throw "Installed file integrity mismatch: $name"
        }
    }
} catch {
    $cause = $_
    for ($i = $applied.Count - 1; $i -ge 0; $i--) {
        $name = $applied[$i]
        $prior = Join-Path $backupDir $name
        $dest = Join-Path $root $name
        try {
            if (Test-Path -LiteralPath $prior -PathType Leaf) {
                Copy-Item -LiteralPath $prior -Destination $dest -Force -ErrorAction Stop
            } elseif (Test-Path -LiteralPath $dest -PathType Leaf) {
                Remove-Item -LiteralPath $dest -Force -ErrorAction Stop
            }
        } catch {
            $rollbackFailed = $true
            Write-Warning "Could not restore application file: $name"
        }
    }
    if ($rollbackFailed) {
        Write-Warning ('Rollback not fully successful; recover files from ' + $backupDir)
    }
    throw $cause
} finally {
    Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $rollbackFailed) { Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue }
}
# Player dependencies are optional: lack of NuGet access triggers an explicit external browser fallback.
try {
    & (Join-Path $root 'Install-WebView2.ps1')
} catch {
    Write-Warning ('WebView2 SDK installation failed; official browser fallback remains available. ' + $_.Exception.Message)
}
# Remove only known obsolete application launchers from prior in-place versions.
# The currently installed application files were replaced with rollback above.
# Retain .venv, uv.exe, cookies, cache, and any unknown user-owned files.
foreach ($oldName in @('ZHS-CLI.cmd','ZHS-GUI.ps1')) {
    $legacy = Join-Path $root $oldName
    if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force }
}
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop '知到学习助手.lnk'))
$shortcut.TargetPath = Join-Path $root 'ZhidaoAssistant.exe'
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $env:USERPROFILE
$shortcut.Description = '知到 App 官方 WebView2 播放工具 V5.2.8（WPF）'
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,70"
$shortcut.Save()
# Register per-user uninstall entry in Windows Apps & Features (no administrator rights).
$regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ZhidaoAssistant'
New-Item -Path $regKey -Force | Out-Null
New-ItemProperty -Path $regKey -Name DisplayName -Value '知到学习助手' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name DisplayVersion -Value '5.2.8' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name Publisher -Value 'Zhidao Assistant community (unofficial)' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name InstallLocation -Value $root -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name DisplayIcon -Value (Join-Path $root 'ZhidaoAssistant.exe') -PropertyType String -Force | Out-Null
$uninstallLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'Uninstall.ps1') + '"'
New-ItemProperty -Path $regKey -Name UninstallString -Value $uninstallLine -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regKey -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $regKey -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
Write-Host 'SUCCESS. Desktop shortcut: 知到学习助手 V5.2.8 (Windows test build)' -ForegroundColor Green
Write-Host 'ZHS data directory:' (Join-Path $env:USERPROFILE '.zhs')
Write-Host 'Login cookies stay in %USERPROFILE%\.zhs. The new privacy notice must be accepted at first launch.'
