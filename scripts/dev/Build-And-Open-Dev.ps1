$ErrorActionPreference = "Stop"

$root = "C:\Users\Sanaa\Projects\italian-tweaks"
Set-Location $root

Write-Host "=== ITALIAN TWEAKS - BUILD AND OPEN DEV ===" -ForegroundColor Cyan
Write-Host "Projet: $root" -ForegroundColor DarkGray

# Fermer toutes les instances
Write-Host "Fermeture des instances ITALIAN TWEAKS / Electron..." -ForegroundColor Yellow
Get-CimInstance Win32_Process | Where-Object {
    $_.Name -like "*ITALIAN*TWEAKS*" -or
    $_.Name -like "*electron*" -or
    $_.CommandLine -match "italian-tweaks"
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 2

# Trouver Node/npm
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
    Write-Host "Installe Node.js LTS ou remets Node portable dans tools/." -ForegroundColor Yellow
    exit 1
}

$npm = "$nodeDir\npm.cmd"
$node = "$nodeDir\node.exe"
$env:Path = "$nodeDir;$env:Path"

Write-Host "Node: $node" -ForegroundColor Green
Write-Host "npm : $npm" -ForegroundColor Green

# Vérifier dépendances
if (!(Test-Path "$root\node_modules")) {
    Write-Host "node_modules absent, installation npm..." -ForegroundColor Yellow
    & $npm install
}

# Nettoyer ancien build
Write-Host "Suppression ancien build..." -ForegroundColor Yellow
Remove-Item "$root\build\win-unpacked" -Recurse -Force -ErrorAction SilentlyContinue

# Build
Write-Host "Build build:dir..." -ForegroundColor Yellow
& $npm run build:dir

# Vérifier EXE
$exe = "$root\build\win-unpacked\ITALIAN TWEAKS.exe"

if (!(Test-Path $exe)) {
    Write-Host "EXE introuvable après build : $exe" -ForegroundColor Red
    Get-ChildItem "$root\build" -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object FullName
    exit 1
}

# Nettoyer TOUS les anciens raccourcis bureau
$desktopPaths = @(
    [Environment]::GetFolderPath("Desktop"),
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\OneDrive\Bureau",
    "$env:USERPROFILE\OneDrive\Desktop",
    "C:\Users\Public\Desktop",
    "C:\Users\Public\Bureau"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

foreach ($desk in $desktopPaths) {
    Get-ChildItem $desk -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "ITALIAN|Italian|TWEAKS|Tweaks|Lancer"
    } | ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

# Créer UN SEUL raccourci
$mainDesktop = [Environment]::GetFolderPath("Desktop")
$shortcut = "$mainDesktop\OUVRIR ITALIAN TWEAKS.lnk"

$wsh = New-Object -ComObject WScript.Shell
$s = $wsh.CreateShortcut($shortcut)
$s.TargetPath = $exe
$s.WorkingDirectory = "$root\build\win-unpacked"
$s.IconLocation = "$exe,0"
$s.Description = "Ouvrir la bonne version Italian Tweaks"
$s.Save()

Write-Host "Raccourci créé : $shortcut" -ForegroundColor Green

# Lancer
Start-Process -FilePath $exe -WorkingDirectory "$root\build\win-unpacked"

Write-Host "Application lancée depuis : $exe" -ForegroundColor Green
Write-Host "À utiliser uniquement : OUVRIR ITALIAN TWEAKS" -ForegroundColor Cyan
