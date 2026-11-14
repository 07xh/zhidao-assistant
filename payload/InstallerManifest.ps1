# Stable Windows PowerShell 5.1 installer manifest loader.
# Invoke with an explicit JSON array instead of a pipeline wrapped in @(...):
# older PowerShell editions may preserve a nested array as one pipeline value.
function Read-ZhidaoInstallerManifest([string]$manifestFile) {
    if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
        throw 'Installer resource manifest missing.'
    }
    $raw = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 -ErrorAction Stop
    $parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
    if ($parsed -isnot [System.Array]) {
        throw 'Installer resource manifest must be a JSON array.'
    }
    $names = New-Object 'System.Collections.Generic.List[string]'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($name in $parsed) {
        if ($name -isnot [string]) { throw 'Installer resource manifest contains a non-string entry.' }
        if ([string]::IsNullOrWhiteSpace($name) -or $name -in @('.','..') -or
            $name.IndexOfAny($invalid) -ge 0 -or
            $name -match '[\\/:*?"<>|]') {
            throw 'Installer resource manifest contains an invalid file name.'
        }
        if (-not $seen.Add($name)) { throw 'Installer resource manifest contains a duplicate name.' }
        [void]$names.Add($name)
    }
    if ($names.Count -lt 2 -or -not $seen.Contains('ZhidaoAssistant.exe') -or
        -not $seen.Contains('install-files.json') -or
        -not $seen.Contains('InstallerManifest.ps1')) {
        throw 'Invalid installer resource manifest.'
    }
    # Preserve the top-level array as exactly one pipeline value. Callers
    # assign directly: $files = Read-ZhidaoInstallerManifest $path (no @(...)).
    return ,($names.ToArray())
}
