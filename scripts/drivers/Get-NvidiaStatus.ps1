#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')

$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
$libScript = Join-Path $root 'scripts\lib\nvidia\Get-NvidiaDriverStatus.ps1'
$cachePath = Join-Path $root 'logs\nvidia-driver-status.json'

if (-not (Test-Path -LiteralPath $libScript)) {
    Write-ItalianTweaksJson -Ok $true -Status 'mock' -Action 'GetNvidiaStatus' -Message 'Script NVIDIA absent' -Data @{}
}

$stdout = & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $libScript -AppRoot $root -CachePath $cachePath 2>&1
$data = @{}
try {
    $line = ($stdout | Out-String).Trim().Split("`n")[-1]
    $data = $line | ConvertFrom-Json
} catch {
    if (Test-Path $cachePath) { $data = Get-Content $cachePath -Raw | ConvertFrom-Json }
}

Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'GetNvidiaStatus' -Message 'Statut pilote NVIDIA' -Data $data
