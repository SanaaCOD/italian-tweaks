#Requires -Version 5.1
param(
    [string]$AppRoot = '',
    [string]$LogDir = '',
    [string]$InstanceId = '',
    [string]$DeviceInstanceId = '',
    [string]$ControllerId = '',
    [string]$Type = '',
    [string]$Vid = '',
    [string]$controllerProductId = ''
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
. (Join-Path $PSScriptRoot '..\lib\devices\Controller-Hidusbf-Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\devices\Controller-Presence-Common.ps1')
. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Bridge.ps1')

function Write-CtrlLog {
    param([string]$LogDir, [string]$Line)
    if (-not $LogDir) { return }
    Write-ItalianTweaksLog -LogDir $LogDir -Name 'controllers' -Line $Line
}

$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
if (-not $LogDir) { $LogDir = Join-Path $root 'logs' }

$inst = if ($InstanceId) { $InstanceId } else { $DeviceInstanceId }
$productId = [string]$controllerProductId
$typeNorm = ($Type + '').Trim()
if ($typeNorm -eq 'DualSense') { $typeNorm = 'PS5' }

Write-CtrlLog $LogDir "RESTORE_START instance=$inst type=$typeNorm vid=$Vid productId=$productId controllerId=$ControllerId"

$bundle = Test-HidusbfBundleReady -Root $root
if (-not $bundle.Ready) {
    $miss = ($bundle.Missing -join ', ')
    Write-ControllerActionErrorJson -Action 'RestoreControllerPolling' `
        -Message ('HIDUSBF incomplet dans tools/hidusbf — fichiers manquants: ' + $miss) `
        -Data @{
            type = $typeNorm; vendorId = $Vid; productId = $productId; targetHz = 125
            hidusbfTool = [string]$bundle.Root; command = 'Test-HidusbfBundleReady'; exitCode = 12
        } -LogDir $LogDir
}

$target = Resolve-ControllerActionTarget -Root $root -LogDir $LogDir -InstanceId $inst `
    -ControllerId $ControllerId -Vid $Vid -ProductId $productId
if (-not $target.ok) {
    Write-ControllerActionErrorJson -Action 'RestoreControllerPolling' -Message $target.message `
        -Data @{
            type = $typeNorm; vendorId = $Vid; productId = $productId; targetHz = 125
            errorDetails = $target.message; ocCode = $target.code; exitCode = 31
        } -LogDir $LogDir
}

$run = Invoke-ControllerOcEngine -Root $root -LogDir $LogDir `
    -DeviceInstanceId $target.deviceInstanceId `
    -UsbParentDeviceId $target.usbParentId `
    -Vid $Vid -ProductId $productId -ControllerType $typeNorm -RestoreMode

$oc = $run.result
$ocOk = ($oc -and $oc.Success -eq $true)
$exitCode = [int]$run.exitCode
if ($ocOk) { $exitCode = 0 }

$verifiedHz = Get-VerifiedHzFromTarget -UsbParentId $target.usbParentId -Vid $Vid -ProductId $productId
if ($oc -and $oc.ConfirmedRate -ge 0) { $verifiedHz = [int]$oc.ConfirmedRate }

Write-CtrlLog $LogDir ("RESTORE_END exit=$exitCode verifiedHz=$verifiedHz ocCode=" + [string]$oc.Code)

if ($exitCode -eq 0 -and $ocOk) {
    Write-ControllerActionSuccessJson -Action 'RestoreControllerPolling' `
        -Message 'Polling restauré à 125 Hz' -Data @{
            type                    = $typeNorm
            vendorId                = $Vid
            productId               = $productId
            targetHz                = 125
            verifiedHz              = $verifiedHz
            hidusbfTool             = [string]$bundle.Root
            hidusbfTargetInstanceId = $target.usbParentId
            deviceInstanceId        = $target.deviceInstanceId
            driverVariant           = [string]$oc.DriverVariant
            ocCode                  = [string]$oc.Code
            needsReconnect          = [bool]$oc.NeedsReconnect
        }
}

$errMsg = if ($oc -and $oc.Message) { [string]$oc.Message } else { 'Échec restauration HIDUSBF (Apply-ControllerOC -Uninstall)' }
Write-ControllerActionErrorJson -Action 'RestoreControllerPolling' -Message $errMsg -Data @{
    type                    = $typeNorm
    vendorId                = $Vid
    productId               = $productId
    targetHz                = 125
    verifiedHz              = $verifiedHz
    hidusbfTool             = [string]$bundle.Root
    hidusbfTargetInstanceId = $target.usbParentId
    command                 = $run.command
    exitCode                = $exitCode
    stderr                  = [string]$run.stderr
    ocCode                  = if ($oc) { [string]$oc.Code } else { '' }
    ocMessage               = if ($oc) { [string]$oc.Message } else { '' }
} -LogDir $LogDir
