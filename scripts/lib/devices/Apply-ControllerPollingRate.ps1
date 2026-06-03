#Requires -Version 5.1
<#
.SYNOPSIS
  Apply polling rate via HIDUSBF Setup UI automation (no registry writes).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$ParamFile = '',
    [string]$ResultPath = '',
    [string]$DeviceInstanceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = '',
    [ValidateSet(1000, 8000)]
    [int]$Rate = 1000
)

$autoScript = Join-Path $PSScriptRoot 'Hidusbf-Setup-Automation.ps1'
if (-not (Test-Path -LiteralPath $autoScript)) {
    Write-Error 'Hidusbf-Setup-Automation.ps1 introuvable'
    exit 127
}

$argList = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $autoScript,
    '-Mode', 'Apply',
    '-Rate', $Rate
)
if ($AppRoot) { $argList += @('-AppRoot', $AppRoot) }
if ($LogPath) { $argList += @('-LogPath', $LogPath) }
if ($ParamFile) { $argList += @('-ParamFile', $ParamFile) }
if ($ResultPath) { $argList += @('-ResultPath', $ResultPath) }
if ($DeviceInstanceId) { $argList += @('-DeviceInstanceId', $DeviceInstanceId) }
if ($Vid) { $argList += @('-Vid', $Vid) }
if ($DevicePid) { $argList += @('-Pid', $DevicePid) }

& powershell.exe @argList
exit $LASTEXITCODE
