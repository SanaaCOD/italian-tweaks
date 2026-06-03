#Requires -Version 5.1
param(
    [string]$AppRoot = '',
    [string]$LogDir = '',
    [string]$InstanceId = '',
    [string]$DeviceInstanceId = '',
    [string]$ControllerId = '',
    [string]$Type = '',
    [int]$TargetHz = 0,
    [int]$Rate = 0,
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
$rate = if ($TargetHz -gt 0) { $TargetHz } elseif ($Rate -gt 0) { $Rate } else { 1000 }

$typeNorm = ($Type + '').Trim()
if ($typeNorm -eq 'PS5') {
    if ($rate -ne 8000) { $rate = 8000 }
}
else {
    if ($rate -gt 1000) { $rate = 1000 }
    if ($rate -eq 8000) { $rate = 1000 }
}
if ($rate -notin 1000, 8000) { $rate = 1000 }

$hidusbfInf = Join-Path $root 'tools\hidusbf\HIDUSBFU.INF'
if (-not (Test-Path -LiteralPath $hidusbfInf)) {
    Write-CtrlLog $LogDir "APPLY_FAIL hidusbf missing rate=$rate id=$inst"
    Write-ItalianTweaksJson -Ok $false -Status 'error' -Action 'ApplyControllerPolling' `
        -Message 'Outil HIDUSBF manquant (tools/hidusbf)' -Data @{
            controllerId = $ControllerId
            targetHz     = $rate
            verifiedHz   = $null
        }
}

$presence = Test-ControllerDevicePresent -DeviceInstanceId $inst -Vid $Vid -DevicePid $Pid
if (-not $presence.Present) {
    Write-CtrlLog $LogDir "APPLY_FAIL not present id=$inst"
    Write-ItalianTweaksJson -Ok $false -Status 'error' -Action 'ApplyControllerPolling' `
        -Message 'Manette non connectée (scan PnP)' -Data @{ controllerId = $ControllerId; targetHz = $rate }
}

$libScript = Join-Path $root 'scripts\lib\devices\Apply-ControllerPollingRate.ps1'
$logFile = Join-Path $LogDir 'controller-overclocker.log'

Write-CtrlLog $LogDir "APPLY_START id=$inst type=$typeNorm targetHz=$rate vid=$Vid pid=$Pid"

$code = 0
if (Test-Path -LiteralPath $libScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
        -File $libScript -AppRoot $root -LogPath $logFile -DeviceInstanceId $inst -Vid $Vid -DevicePid $Pid -Rate $rate | Out-Null
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
Write-CtrlLog $LogDir "APPLY_END exit=$code verifiedHz=$verifiedHz parent=$usbParent"

$ok = ($code -eq 0)
Write-ItalianTweaksJson -Ok $ok -Status $(if ($ok) { 'success' } else { 'error' }) -Action 'ApplyControllerPolling' `
    -Message $(if ($ok) { "Polling $rate Hz appliqué (vérifié $verifiedHz Hz)" } else { 'Échec automation HIDUSBF' }) `
    -Data @{
        controllerId   = if ($ControllerId) { $ControllerId } else { $inst }
        targetHz       = $rate
        verifiedHz     = $verifiedHz
        deviceInstanceId = $inst
        exitCode       = $code
    }
