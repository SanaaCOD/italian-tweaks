#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\..\_common\ItalianTweaks.Json.ps1')

$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
$libScript = Join-Path $root 'scripts\lib\devices\Get-ControllerPresentDevices.ps1'
$outFile = Join-Path $root 'logs\controller-devices-present.json'
$logFile = Join-Path $root 'logs\controller-overclocker.log'

if (-not (Test-Path -LiteralPath $libScript)) {
    Write-ItalianTweaksJson -Ok $true -Status 'mock' -Action 'GetControllers' -Message 'Lib PurpleBoost absente — liste vide' -Data @{ controllers = @() }
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $libScript `
    -AppRoot $root -LogPath $logFile -OutputPath $outFile | Out-Null

$list = @()
if (Test-Path -LiteralPath $outFile) {
    try {
        $raw = [System.IO.File]::ReadAllText($outFile)
        $parsed = $raw | ConvertFrom-Json
        if ($parsed -is [Array]) { $list = $parsed } elseif ($parsed) { $list = @($parsed) }
    } catch {}
}

Write-ItalianTweaksLog -LogDir $LogDir -Name 'controllers' -Line ("Get-Controllers count=" + $list.Count)
Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'GetControllers' -Message ("$($list.Count) manette(s) PnP") -Data @{ controllers = $list }
