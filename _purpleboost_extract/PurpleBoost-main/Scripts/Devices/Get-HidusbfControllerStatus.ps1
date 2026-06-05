#Requires -Version 5.1
<#
.SYNOPSIS
  Fast HIDUSBF status read from registry only (no WMI, no composite resolve when parent known).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$OutputPath = '',
    [string]$UsbParentDeviceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

function Write-StatusOut {
    param([hashtable]$Payload, [string]$OutFile)
    if (-not $OutFile) { return }
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutFile, ($Payload | ConvertTo-Json -Depth 6 -Compress:$false), [System.Text.UTF8Encoding]::new($false))
}

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) { exit 9 }
$script:LogFile = if ($LogPath) { $LogPath } else { Join-Path $app 'logs\controller-overclocker.log' }
if (-not $OutputPath) { $OutputPath = Join-Path $app 'logs\controller-hidusbf-status.json' }

$payload = Get-HidusbfConfirmedStatusForParent -UsbParentDeviceId $UsbParentDeviceId -Vid $Vid -DevicePid $DevicePid
if ($script:LogFile -and -not $Quiet) {
    $cr = $payload.ConfirmedRate
    $st = $payload.Status
    Write-DeviceLog ("[HIDUSBF-STATUS] ConfirmedRate=$cr Status=$st") $script:LogFile
}
Write-StatusOut -Payload $payload -OutFile $OutputPath
exit 0
