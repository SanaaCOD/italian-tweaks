#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'SilentlyContinue'
$files = @('s.1.0.cod25.txt0', 's.1.0.cod25.txt1')
$embed = Join-Path $AppRoot 'assets\game\warzone'
$searchRoots = @(
    (Join-Path $env:USERPROFILE 'Documents\Call of Duty\players'),
    (Join-Path $env:USERPROFILE 'OneDrive\Documents\Call of Duty\players'),
    (Join-Path $env:LOCALAPPDATA 'Activision\Call of Duty\players'),
    (Join-Path $env:USERPROFILE 'Documents\Call of Duty HQ\players')
)

$foundDir = $null
foreach ($root in $searchRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object {
        if ($foundDir) { return }
        $ok = $true
        foreach ($f in $files) {
            if (-not (Test-Path -LiteralPath (Join-Path $_.FullName $f))) { $ok = $false; break }
        }
        if ($ok) { $foundDir = $_.FullName }
    }
}

$embeddedOk = $true
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $embed $f))) { $embeddedOk = $false }
}

$out = [ordered]@{
    installed = [bool]$foundDir
    playersDir = $foundDir
    embeddedReady = $embeddedOk
    embeddedPath = $embed
    searchRoots = $searchRoots
}
Write-Output ($out | ConvertTo-Json -Depth 4 -Compress)
exit 0
