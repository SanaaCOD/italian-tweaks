$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

Write-Host "=== Kojo - BUILD AND OPEN DEV ===" -ForegroundColor Cyan
Write-Host "Projet: $root" -ForegroundColor DarkGray

Write-Host "Fermeture des instances Kojo / Electron..." -ForegroundColor Yellow
Get-CimInstance Win32_Process | Where-Object {
    $_.Name -like "*Kojo*" -or
    $_.Name -like "*electron*" -or
    $_.CommandLine -match "italian-tweaks|kojo"
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 2

$nodeCandidates = @(
    "$root\tools\node-v22.16.0-win-x64",
    "$root\tools\node-v22.17.0-win-x64",
    "$root\tools\node-v22.18.0-win-x64",
    "C:\Program Files\nodejs"
)

$nodeDir = $null
foreach ($candidate in $nodeCandidates) {
    if ((Test-Path "$candidate\node.exe") -and (Test-Path "$candidate\npm.cmd")) {
        $nodeDir = $candidate
        break
    }
}

if (-not $nodeDir -and (Test-Path "$root\tools")) {
    $npmFound = Get-ChildItem "$root\tools" -Filter "npm.cmd" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($npmFound) {
        $nodeDir = Split-Path $npmFound.FullName
    }
}

if (-not $nodeDir) {
    Write-Host "ERREUR : npm introuvable." -ForegroundColor Red
    exit 1
}

$npm = "$nodeDir\npm.cmd"
$env:Path = "$nodeDir;$env:Path"

if (!(Test-Path "$root\node_modules")) {
    Write-Host "node_modules absent, installation npm..." -ForegroundColor Yellow
    & $npm install
}

Write-Host "Suppression ancien build..." -ForegroundColor Yellow
Remove-Item "$root\build\win-unpacked" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Build build:dir..." -ForegroundColor Yellow
& $npm run build:dir

$exe = "$root\build\win-unpacked\Kojo.exe"

if (!(Test-Path $exe)) {
    Write-Host "EXE introuvable après build : $exe" -ForegroundColor Red
    Get-ChildItem "$root\build" -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object FullName
    exit 1
}

$desktopPaths = @(
    [Environment]::GetFolderPath("Desktop"),
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\OneDrive\Bureau",
    "$env:USERPROFILE\OneDrive\Desktop"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

foreach ($desk in $desktopPaths) {
    Get-ChildItem $desk -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "ITALIAN|Italian|TWEAKS|Tweaks|OUVRIR ITALIAN"
    } | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

$mainDesktop = [Environment]::GetFolderPath("Desktop")
$shortcut = "$mainDesktop\Ouvrir Kojo.lnk"

$wsh = New-Object -ComObject WScript.Shell
$s = $wsh.CreateShortcut($shortcut)
$s.TargetPath = $exe
$s.WorkingDirectory = "$root\build\win-unpacked"
$s.IconLocation = "$exe,0"
$s.Description = "Lancer Kojo"
$s.Save()

Write-Host "Raccourci créé : $shortcut" -ForegroundColor Green
Start-Process -FilePath $exe -WorkingDirectory "$root\build\win-unpacked"
Write-Host "Application lancée : $exe" -ForegroundColor Green
