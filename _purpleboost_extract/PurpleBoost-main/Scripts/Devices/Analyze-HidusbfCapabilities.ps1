#Requires -Version 5.1
<#
.SYNOPSIS
  Probes HIDUSBF Setup for CLI capabilities (non-destructive).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) {
    Write-DeviceLog '[DEVICE] Result: error app_root_unresolved' $LogPath
    exit 9
}

if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }

$setupExe = Find-HidusbfSetupExe -AppRoot $app -LogFile $LogPath
if (-not $setupExe) {
    Write-DeviceLog '[DEVICE] Result: error setup_exe_missing' $LogPath
    exit 12
}

$hasCli = Analyze-HidusbfCapabilities -SetupExePath $setupExe -LogFile $LogPath
if ($hasCli) {
    Write-DeviceLog '[DEVICE] Result: cli_probe_complete' $LogPath
    exit 0
}

Write-DeviceLog '[DEVICE] Result: cli_probe_manual_only' $LogPath
exit 10
