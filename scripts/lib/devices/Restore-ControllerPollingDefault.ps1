#Requires -Version 5.1
<#
.SYNOPSIS
  Restore default polling via HIDUSBF Setup UI automation.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$ParamFile = '',
    [string]$ResultPath = '',
    [string]$DeviceInstanceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = ''
)

$autoScript = Join-Path $PSScriptRoot 'Hidusbf-Setup-Automation.ps1'
if (-not (Test-Path -LiteralPath $autoScript)) {
    Write-Error 'Hidusbf-Setup-Automation.ps1 introuvable'
    exit 127
}

$argList = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $autoScript,
    '-Mode', 'Restore'
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
