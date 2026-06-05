#Requires -Version 5.1
<#
.SYNOPSIS
  Real PnP presence for one controller (not registry Enum phantom keys).
#>
param(
    [string]$AppRoot = '',
    [string]$OutputPath = '',
    [string]$DeviceInstanceId = '',
    [string]$UsbParentDeviceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = ''
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Controller-Presence-Common.ps1')

$app = $AppRoot
if (-not $app -or -not (Test-Path -LiteralPath $app)) {
    $here = $PSScriptRoot
    if ($here) {
        $c = Split-Path -Parent (Split-Path -Parent $here)
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'Unreal.hta'))) { $app = $c }
    }
}
if (-not $OutputPath -and $app) {
    $OutputPath = Join-Path $app 'logs\controller-present-check.json'
}

$result = Test-ControllerDevicePresent -DeviceInstanceId $DeviceInstanceId `
    -UsbParentDeviceId $UsbParentDeviceId -Vid $Vid -DevicePid $DevicePid

if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, ($result | ConvertTo-Json -Depth 4 -Compress), [System.Text.UTF8Encoding]::new($false))
}

if ($result.Present) { exit 0 }
exit 1
