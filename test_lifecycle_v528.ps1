# Windows PowerShell 5.1 integration-style mocked discovery test, no processes killed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'payload\AppLifecycle.ps1')
$testRoot = 'C:\Users\Student\AppData\Local\ZHSDesktop'
$script:fakeProcesses = @(
    [pscustomobject]@{Name='ZhidaoAssistant.exe';ExecutablePath="$testRoot\ZhidaoAssistant.exe";CommandLine='';ProcessId=501;ParentProcessId=1;CreationDate=[datetime]'2026-01-01'},
    [pscustomobject]@{Name='powershell.exe';ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';CommandLine="powershell -File `"$testRoot\Zhidao-GUI.ps1`"";ProcessId=502;ParentProcessId=501;CreationDate=[datetime]'2026-01-01'},
    [pscustomobject]@{Name='cmd.exe';ExecutablePath='C:\Windows\System32\cmd.exe';CommandLine="cmd /c `"$testRoot\Zhidao-Task.cmd`" login";ProcessId=503;ParentProcessId=502;CreationDate=[datetime]'2026-01-01'},
    [pscustomobject]@{Name='zhs.exe';ExecutablePath="$testRoot\.venv\Scripts\zhs.exe";CommandLine='zhs login';ProcessId=504;ParentProcessId=503;CreationDate=[datetime]'2026-01-01'},
    [pscustomobject]@{Name='python.exe';ExecutablePath='C:\Python313\python.exe';CommandLine='python unrelated.py';ProcessId=505;ParentProcessId=503;CreationDate=[datetime]'2026-01-01'},
    [pscustomobject]@{Name='powershell.exe';ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';CommandLine='powershell -File "C:\Other\Zhidao-GUI.ps1"';ProcessId=506;ParentProcessId=1;CreationDate=[datetime]'2026-01-01'},
    [pscustomobject]@{Name='ZhidaoAssistant.exe';ExecutablePath='C:\Other\ZhidaoAssistant.exe';CommandLine='';ProcessId=507;ParentProcessId=1;CreationDate=[datetime]'2026-01-01'},
    [pscustomobject]@{Name='cmd.exe';ExecutablePath='C:\Windows\System32\cmd.exe';CommandLine="cmd /c `"$testRoot\Zhidao-Task.cmd.backup`"";ProcessId=508;ParentProcessId=1;CreationDate=[datetime]'2026-01-01'}
)
function Get-CimInstance { param([string]$ClassName, [string]$ErrorAction) return $script:fakeProcesses }
$ids = @(Get-ZhidaoAppProcesses -InstallRoot $testRoot | ForEach-Object { [int]$_.ProcessId } | Sort-Object)
$expected = @(501,502,503,504)
if (($ids -join ',') -ne ($expected -join ',')) { throw "App-owned process match failed: $ids" }
Write-Host 'PASS: precise matching of app launcher, hosts and private child; other processes not matched.'
