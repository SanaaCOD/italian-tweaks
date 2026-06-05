# Crée un raccourci Bureau vers l'EXE dans dist (ne copie pas l'EXE sur le Bureau).
param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

$iconPath = Join-Path $ProjectRoot "assets\images\icon.ico"
if (-not (Test-Path -LiteralPath $iconPath)) {
    $iconPath = Join-Path $ProjectRoot "assets\images\unreal.ico"
}

$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "Unreal Gaming Optimizer.lnk"

$mshtaExe = Join-Path $ProjectRoot "dist\Unreal Gaming Optimizer.exe"
$electronExe = Join-Path $ProjectRoot "dist\win-unpacked\Unreal Gaming Optimizer.exe"

$targetExe = $null
$workDir = $null

if (Test-Path -LiteralPath $mshtaExe) {
    $targetExe = $mshtaExe
    $workDir = $ProjectRoot
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "Unreal.hta"))) {
        Write-Warning "Unreal.hta absent de la racine ; le lanceur remontera les dossiers parents."
    }
}
elseif (Test-Path -LiteralPath $electronExe) {
    $targetExe = $electronExe
    $appDir = Join-Path $ProjectRoot "dist\win-unpacked\resources\app"
    if (Test-Path -LiteralPath (Join-Path $appDir "Unreal.hta")) {
        $workDir = $appDir
    }
    else {
        $workDir = Join-Path $ProjectRoot "dist\win-unpacked"
    }
}
else {
    Write-Error @"
Aucun EXE trouvé. Compilez d'abord :
  build-exe.bat
ou la build Electron (dist\win-unpacked).

Chemins attendus :
  $mshtaExe
  $electronExe
"@
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetExe
$shortcut.WorkingDirectory = $workDir
$shortcut.Description = "Unreal Gaming Optimizer"
if (Test-Path -LiteralPath $iconPath) {
    $shortcut.IconLocation = "$iconPath,0"
}
$shortcut.Save()

Write-Host ""
Write-Host "========================================"
Write-Host " Raccourci Bureau cree"
Write-Host "========================================"
Write-Host " Raccourci : $shortcutPath"
Write-Host " EXE       : $targetExe"
Write-Host " WorkDir   : $workDir"
if (Test-Path -LiteralPath $iconPath) {
    Write-Host " Icone     : $iconPath"
}
Write-Host ""
Write-Host " Ne copiez PAS l'EXE seul sur le Bureau."
Write-Host " Double-cliquez sur le raccourci ci-dessus."
Write-Host "========================================"
