#Requires -Version 5.1
<#
.SYNOPSIS
  Read HIDUSBF status for all controllers in one PowerShell process (registry only).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$DevicesPath = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) { exit 9 }
if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }
if (-not $DevicesPath) { $DevicesPath = Join-Path $app 'logs\controller-overclocker-detect.json' }
if (-not $OutputPath) { $OutputPath = Join-Path $app 'logs\controller-hidusbf-status-all.json' }

$devices = @()
if (Test-Path -LiteralPath $DevicesPath) {
    try {
        $raw = [System.IO.File]::ReadAllText($DevicesPath, [System.Text.UTF8Encoding]::new($false))
        $parsed = $raw | ConvertFrom-Json
        if ($parsed) { $devices = @($parsed) }
    } catch {}
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($dev in $devices) {
    $usbParent = [string]$dev.UsbParentDeviceId
    if (-not $usbParent) { $usbParent = [string]$dev.TargetHidusbfDeviceId }
    $vid = [string]$dev.Vid
    $pid = [string]$dev.Pid
    $cardKey = if ($usbParent) { $usbParent } else { ([string]$dev.DeviceInstanceId) }
    $st = Get-HidusbfConfirmedStatusForParent -UsbParentDeviceId $usbParent -Vid $vid -DevicePid $pid
    $results.Add([ordered]@{
        CardKey           = $cardKey
        DeviceInstanceId  = [string]$dev.DeviceInstanceId
        UsbParentDeviceId = $usbParent
        Vid               = $vid
        Pid               = $pid
        Status            = $st
    }) | Out-Null
}

$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
[System.IO.File]::WriteAllText($OutputPath, ($results | ConvertTo-Json -Depth 8 -Compress:$false), [System.Text.UTF8Encoding]::new($false))
exit 0
