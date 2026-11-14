# Offline contract test of the pending verification queue on Windows PowerShell 5.1.
# No WPF, real account, course server, or ZHS heartbeat calls.
$ErrorActionPreference = 'Stop'
$gui = Join-Path $PSScriptRoot 'payload\Zhidao-GUI.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($gui, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'GUI PowerShell parse failed' }
$required = @('Get-SessionFingerprint', 'Valid-CourseArgs', 'Save-PendingVerify', 'Load-PendingVerify', 'Queue-PendingVerify', 'Check-PendingVerify')
$definitions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $required -contains $node.Name
}, $true))
if ($definitions.Count -ne $required.Count) { throw 'Missing or duplicate verification function' }
foreach ($f in $definitions) { Invoke-Expression $f.Extent.Text }
$script:statusText = [pscustomobject]@{ Text = '' }
function Control([string]$name) { return $script:statusText }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('zhs-verify-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $script:dataDir = $root
    $script:cookiePath = Join-Path $root 'cookies.json'
    $script:pendingVerifyPath = Join-Path $root 'pending-verify.json'
    $script:pendingVerifyCourse = $null
    $script:pendingVerifySessionFingerprint = ''
    [System.IO.File]::WriteAllBytes((Join-Path $root 'zhidao-cache-salt.bin'), [byte[]](0..31))
    [System.IO.File]::WriteAllText($script:cookiePath, 'fake-cookie-one')
    $course = [pscustomobject]@{ courseType = 'ai'; courseId = '70'; classId = '4' }
    $fp = Get-SessionFingerprint
    if ($fp -notmatch '^[0-9a-f]{64}$') { throw 'Missing HMAC fingerprint' }
    if (-not (Queue-PendingVerify $course $fp)) { throw 'Did not queue valid course' }
    if (-not (Test-Path $script:pendingVerifyPath)) { throw 'Did not persist queue' }
    if (Queue-PendingVerify $course $fp) { throw 'Accepted second queued course' }

    $script:pendingVerifyCourse = $null
    $script:pendingVerifySessionFingerprint = ''
    Load-PendingVerify
    if ([string]$script:pendingVerifyCourse.courseId -ne '70') { throw 'Did not load bound course' }
    if ($script:pendingVerifySessionFingerprint -ne $fp) { throw 'Did not restore bound fingerprint' }

    [System.IO.File]::WriteAllText($script:cookiePath, 'fake-cookie-two')
    Check-PendingVerify
    if ($null -ne $script:pendingVerifyCourse) { throw 'Cross-account queue was not cleared' }
    if (Test-Path $script:pendingVerifyPath) { throw 'Cross-account queue file remains' }

    [System.IO.File]::WriteAllText($script:pendingVerifyPath, '{"courseType":"ai","courseId":"71","classId":"4"}')
    Load-PendingVerify
    if ($null -ne $script:pendingVerifyCourse) { throw 'Legacy unbound queue was trusted' }
    if (Test-Path $script:pendingVerifyPath) { throw 'Legacy queue was not removed' }
    if (Queue-PendingVerify $course $fp) { throw 'Accepted stale session fingerprint' }

    Write-Host 'Pending verification queue is session-bound; offline tests passed.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
