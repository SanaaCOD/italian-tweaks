#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
$lib = Join-Path $root 'scripts\lib\optimisation\Debloat\enable.ps1'
if (-not (Test-Path $lib)) { Write-ItalianTweaksStub -Action 'ApplyDebloat' }
$code = 0
& powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $lib 2>&1 | Out-Null
if ($null -ne $LASTEXITCODE) { $code = $LASTEXITCODE }
Write-ItalianTweaksJson -Ok ($code -eq 0) -Status $(if ($code -eq 0) { 'success' } else { 'error' }) -Action 'ApplyDebloat' -Message 'Debloat exécuté' -Data @{ exitCode = $code }
