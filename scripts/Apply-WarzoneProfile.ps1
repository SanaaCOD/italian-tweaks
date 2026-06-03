#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'Stop'
$files = @('s.1.0.cod25.txt0', 's.1.0.cod25.txt1')
$embed = Join-Path $AppRoot 'assets\game\warzone'
$statusJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $AppRoot 'scripts\Get-WarzoneStatus.ps1') -AppRoot $AppRoot -LogDir $LogDir
$status = $statusJson | ConvertFrom-Json

$target = $status.playersDir
if (-not $target) {
    $searchRoots = @(
        (Join-Path $env:USERPROFILE 'Documents\Call of Duty\players'),
        (Join-Path $env:USERPROFILE 'Documents\Call of Duty HQ\players')
    )
    foreach ($root in $searchRoots) {
        if (Test-Path -LiteralPath $root) {
            $target = Get-ChildItem -LiteralPath $root -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
            if ($target) { break }
        }
    }
}

if (-not $target) {
    Write-Output (@{ ok = $false; error = 'Dossier joueur Call of Duty introuvable. Lancez le jeu une fois.' } | ConvertTo-Json -Compress)
    exit 1
}

$copied = @()
foreach ($f in $files) {
    $src = Join-Path $embed $f
    if (-not (Test-Path -LiteralPath $src)) { continue }
    Copy-Item -LiteralPath $src -Destination (Join-Path $target $f) -Force
    $copied += $f
}

$log = Join-Path $LogDir 'warzone.log'
Add-Content -LiteralPath $log -Value ("[{0}] Copied to {1}: {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $target, ($copied -join ',')) -Encoding UTF8

Write-Output (@{ ok = $true; playersDir = $target; copied = $copied } | ConvertTo-Json -Compress)
exit 0
