#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
$lib = Join-Path $root 'scripts\lib\optimisation\ModeJeu\enable.ps1'
if (-not (Test-Path $lib)) { Write-ItalianTweaksStub -Action 'ApplyGameMode' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $lib 2>&1 | Out-Null
Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'ApplyGameMode' -Message 'Mode jeu activé' -Data @{}
