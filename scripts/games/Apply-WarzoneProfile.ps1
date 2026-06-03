#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
. (Join-Path $PSScriptRoot '_Detect-WarzonePathCore.ps1')
$det = Get-WarzoneDetection -AppRoot $root
$target = $det.playersDir
if (-not $target) {
    Write-ItalianTweaksJson -Ok $false -Status 'error' -Action 'ApplyWarzoneProfile' -Message 'Dossier joueur introuvable' -Data $det
}
$files = @('s.1.0.cod25.txt0', 's.1.0.cod25.txt1')
$copied = @()
foreach ($f in $files) {
    $src = Join-Path $det.embeddedPath $f
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $target $f) -Force
        $copied += $f
    }
}
Write-ItalianTweaksLog -LogDir $LogDir -Name 'games' -Line "Warzone copied to $target"
Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'ApplyWarzoneProfile' -Message 'Profil Warzone copié' -Data @{ playersDir = $target; copied = $copied }
