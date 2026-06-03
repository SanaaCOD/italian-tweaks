#Requires -Version 5.1
param(
    [string]$AppRoot = '',
    [string]$LogDir = '',
    [string]$InstanceId = '',
    [string]$DeviceInstanceId = '',
    [string]$ControllerId = '',
    [string]$Type = '',
    [string]$Vid = '',
    [string]$Pid = ''
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
. (Join-Path $PSScriptRoot '..\lib\devices\Controller-Hidusbf-Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\devices\Controller-Presence-Common.ps1')

function Write-CtrlLog {
    param([string]$LogDir, [string]$Line)
    if (-not $LogDir) { return }
    Write-ItalianTweaksLog -LogDir $LogDir -Name 'controllers' -Line $Line
}

$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
if (-not $LogDir) { $LogDir = Join-Path $root 'logs' }

$inst = if ($InstanceId) { $InstanceId } else { $DeviceInstanceId }

$hidusbfInf = Join-Path $root 'tools\hidusbf\HIDUSBFU.INF'
if (-not (Test-Path -LiteralPath $hidusbfInf)) {
    Write-ItalianTweaksJson -Ok $false -Status 'error' -Action 'RestoreControllerPolling' `
        -Message 'Outil HIDUSBF manquant (tools/hidusbf)' -Data @{ controllerId = $ControllerId; targetHz = 125 }
}

$presence = Test-ControllerDevicePresent -DeviceInstanceId $inst -Vid $Vid -DevicePid $Pid
if (-not $presence.Present) {
    Write-CtrlLog $LogDir "RESTORE_FAIL not present id=$inst"
    Write-ItalianTweaksJson -Ok $false -Status 'error' -Action 'RestoreControllerPolling' `
        -Message 'Manette non connectée (scan PnP)' -Data @{ controllerId = $ControllerId }
}

$libScript = Join-Path $root 'scripts\lib\devices\Restore-ControllerPollingDefault.ps1'
$logFile = Join-Path $LogDir 'controller-overclocker.log'

Write-CtrlLog $LogDir "RESTORE_START id=$inst"

$code = 0
if (Test-Path -LiteralPath $libScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
        -File $libScript -AppRoot $root -LogPath $logFile -DeviceInstanceId $inst -Vid $Vid -DevicePid $Pid | Out-Null
    if ($null -ne $LASTEXITCODE) { $code = $LASTEXITCODE }
} else {
    $code = 127
}

$usbParent = ''
try {
    $t = Resolve-HidusbfCompositeTarget -DeviceInstanceId $inst -Vid $Vid -DevicePid $Pid -LogFile $logFile
    if ($t) { $usbParent = [string]$t.TargetHidusbfDeviceId }
} catch {}
if (-not $usbParent) { $usbParent = $ControllerId }

$verifiedHz = if ($usbParent) { [int](Get-UsbParentPollingRate -UsbParentDeviceId $usbParent) } else { 125 }
Write-CtrlLog $LogDir "RESTORE_END exit=$code verifiedHz=$verifiedHz"

$ok = ($code -eq 0)
Write-ItalianTweaksJson -Ok $ok -Status $(if ($ok) { 'success' } else { 'error' }) -Action 'RestoreControllerPolling' `
    -Message $(if ($ok) { "Restauré Default / 125 Hz (vérifié $verifiedHz Hz)" } else { 'Échec restauration HIDUSBF' }) `
    -Data @{
        controllerId     = if ($ControllerId) { $ControllerId } else { $inst }
        targetHz         = 125
        verifiedHz       = $verifiedHz
        deviceInstanceId = $inst
        exitCode         = $code
    }
