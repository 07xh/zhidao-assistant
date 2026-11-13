# SPDX-License-Identifier: GPL-3.0-only
# Same-user app-owned process discovery for safe upgrade / uninstall.
# Do not match merely by process name (powershell/python/cmd may belong to other apps).

function Get-ZhidaoAppProcesses {
    param([Parameter(Mandatory=$true)][string]$InstallRoot)

    $resolvedRoot = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $launcher = Join-Path $resolvedRoot 'ZhidaoAssistant.exe'
    $privateExecutables = @(
        (Join-Path $resolvedRoot '.venv\Scripts\zhs.exe'),
        (Join-Path $resolvedRoot '.venv\Scripts\python.exe'),
        (Join-Path $resolvedRoot '.venv\Scripts\pythonw.exe')
    )
    $scriptNames = @(
        'Zhidao-GUI.ps1', 'Official-Player.ps1', 'Zhidao-Task.cmd',
        'zhidao_only.py', 'ZHS-GUI.ps1', 'ZHS-CLI.cmd'
    )
    $hostNames = @('powershell.exe', 'pwsh.exe', 'cmd.exe', 'python.exe', 'pythonw.exe')
    $scriptPatterns = foreach ($file in $scriptNames) {
        $absolute = Join-Path $resolvedRoot $file
        # A full path passed as a command-line argument, not a coincidental substring.
        '(?i)(?<![A-Za-z0-9_\\])[''"\s]' + [regex]::Escape($absolute) + '(?=$|[''"\s])'
    }

    # If process enumeration cannot be trusted, fail closed; never guess and kill by name.
    try { $all = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop) }
    catch { throw '无法验证正在运行的旧版知到助手进程；升级已停止，未终止其他进程。' }

    $ownedIds = @{}
    foreach ($proc in $all) {
        $name = [string]$proc.Name
        $path = [string]$proc.ExecutablePath
        $cmdline = [string]$proc.CommandLine
        $owned = $false
        if ($name -ieq 'ZhidaoAssistant.exe' -and $path -ieq $launcher) {
            $owned = $true
        } elseif ($hostNames -icontains $name -and $cmdline.Length -gt 0) {
            foreach ($pattern in $scriptPatterns) {
                if ([regex]::IsMatch($cmdline, $pattern)) {
                    $owned = $true
                    break
                }
            }
        }
        if ($owned) { $ownedIds[[string]$proc.ProcessId] = $true }
    }

    # The app's own task script may spawn a ZHS CLI child that has no script
    # path in its arguments. Follow *only* direct children from the private venv.
    # Never stop arbitrary children, system Python, or other ZHS installations.
    do {
        $newChild = $false
        foreach ($proc in $all) {
            $id = [string]$proc.ProcessId
            if ($ownedIds.ContainsKey($id)) { continue }
            if (-not $ownedIds.ContainsKey([string]$proc.ParentProcessId)) { continue }
            $path = [string]$proc.ExecutablePath
            foreach ($privateExe in $privateExecutables) {
                if ($path -ieq $privateExe) {
                    $ownedIds[$id] = $true
                    $newChild = $true
                    break
                }
            }
        }
    } while ($newChild)
    foreach ($proc in $all) {
        if ($ownedIds.ContainsKey([string]$proc.ProcessId)) { $proc }
    }

}

function Stop-ZhidaoAppProcesses {
    param([Parameter(Mandatory=$true)][string]$InstallRoot)

    $active = @(Get-ZhidaoAppProcesses -InstallRoot $InstallRoot)
    if ($active.Count -eq 0) {
        Write-Host '[Upgrade] No running older Zhidao Assistant instance found.'
        return
    }

    Write-Host ('[Upgrade] Found ' + $active.Count + ' existing application process(es). Closing automatically...')
    foreach ($proc in $active) {
        try {
            $managed = Get-Process -Id ([int]$proc.ProcessId) -ErrorAction Stop
            if ($managed.MainWindowHandle -ne [IntPtr]::Zero) {
                [void]$managed.CloseMainWindow()
            }
        } catch [System.ArgumentException] {
            # Process may have exited before we could request a graceful close.
        } catch {
            Write-Verbose ('Could not request graceful close for PID ' + $proc.ProcessId + ': ' + $_.Exception.Message)
        }
    }

    Start-Sleep -Seconds 2
    $remaining = @(Get-ZhidaoAppProcesses -InstallRoot $InstallRoot)
    if ($remaining.Count -gt 0) {
        Write-Host ('[Upgrade] ' + $remaining.Count + ' app-owned process(es) still running; stopping them...')
        foreach ($proc in $remaining) {
            # Refresh discovery for each PID to avoid acting on a PID that has been reused.
            $verified = @(Get-ZhidaoAppProcesses -InstallRoot $InstallRoot | Where-Object {
                $_.ProcessId -eq $proc.ProcessId -and $_.CreationDate -eq $proc.CreationDate
            })
            if ($verified.Count -eq 0) { continue }
            try { Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction Stop }
            catch {
                # Fail closed below if it is still running; it may have already exited.
                Write-Warning ('Could not stop PID ' + $proc.ProcessId + ': ' + $_.Exception.Message)
            }
        }
    }

    Start-Sleep -Milliseconds 600
    $stillActive = @(Get-ZhidaoAppProcesses -InstallRoot $InstallRoot)
    if ($stillActive.Count -ne 0) {
        throw ('有 ' + $stillActive.Count + ' 个知到助手旧版进程无法安全结束；为保护安装文件，已停止升级/卸载。')
    }
    Write-Host '[Upgrade] Older Zhidao Assistant instances closed.'
}
