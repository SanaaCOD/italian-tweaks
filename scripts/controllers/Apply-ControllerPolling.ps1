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

$rate = if ($TargetHz -gt 0) { $TargetHz } elseif ($Rate -gt 0) { $Rate } else { 1000 }
if ($typeNorm -eq 'PS5') {
    if ($rate -ne 8000) { $rate = 8000 }
} else {
    if ($rate -gt 1000) { $rate = 1000 }
    if ($rate -eq 8000) { $rate = 1000 }
}
if ($rate -notin 1000, 8000) { $rate = 1000 }

Write-CtrlLog $LogDir "APPLY_START instance=$inst type=$typeNorm targetHz=$rate vid=$Vid productId=$productId"

$bundle = Test-HidusbfBundleReady -Root $root
if (-not $bundle.Ready) {
    $miss = ($bundle.Missing -join ', ')
    Write-ControllerActionErrorJson -Action 'ApplyControllerPolling' `
        -Message ('HIDUSBF incomplet dans tools/hidusbf — fichiers manquants: ' + $miss) `
        -Data @{
            type = $typeNorm; vendorId = $Vid; productId = $productId; targetHz = $rate
            hidusbfTool = [string]$bundle.Root; command = 'Test-HidusbfBundleReady'; exitCode = 12
        } -LogDir $LogDir
}

$target = Resolve-ControllerActionTarget -Root $root -LogDir $LogDir -InstanceId $inst `
    -ControllerId $ControllerId -Vid $Vid -ProductId $productId
if (-not $target.ok) {
    Write-ControllerActionErrorJson -Action 'ApplyControllerPolling' -Message $target.message `
        -Data @{
            type = $typeNorm; vendorId = $Vid; productId = $productId; targetHz = $rate
            errorDetails = $target.message; ocCode = $target.code; exitCode = 31
        } -LogDir $LogDir
}

$run = Invoke-ControllerOcEngine -Root $root -LogDir $LogDir `
    -DeviceInstanceId $target.deviceInstanceId `
    -UsbParentDeviceId $target.usbParentId `
    -Vid $Vid -ProductId $productId -ControllerType $typeNorm -RateHz $rate

$oc = $run.result
$ocOk = ($oc -and $oc.Success -eq $true)
$exitCode = [int]$run.exitCode
if ($ocOk -and $oc.Verified -eq $true) { $exitCode = 0 }
elseif ($ocOk) { $exitCode = 0 }

$verifiedHz = Get-VerifiedHzFromTarget -UsbParentId $target.usbParentId -Vid $Vid -ProductId $productId
if ($oc -and $oc.ConfirmedRate -ge 0) { $verifiedHz = [int]$oc.ConfirmedRate }

Write-CtrlLog $LogDir ("APPLY_END exit=$exitCode verifiedHz=$verifiedHz ocCode=" + [string]$oc.Code)

if ($exitCode -eq 0 -and $ocOk) {
    Write-ControllerActionSuccessJson -Action 'ApplyControllerPolling' -Message 'Polling appliqué' -Data @{
        type                     = $typeNorm
        vendorId                 = $Vid
        productId                = $productId
        targetHz                 = $rate
        verifiedHz               = $verifiedHz
        hidusbfTool              = [string]$bundle.Root
        hidusbfTargetInstanceId  = $target.usbParentId
        deviceInstanceId         = $target.deviceInstanceId
        driverVariant            = [string]$oc.DriverVariant
        ocCode                   = [string]$oc.Code
        needsReconnect           = [bool]$oc.NeedsReconnect
    }
}

$errMsg = if ($oc -and $oc.Message) { [string]$oc.Message } else { 'Échec application HIDUSBF (Apply-ControllerOC)' }
Write-ControllerActionErrorJson -Action 'ApplyControllerPolling' -Message $errMsg -Data @{
    type                    = $typeNorm
    vendorId                = $Vid
    productId               = $productId
    targetHz                = $rate
    verifiedHz              = $verifiedHz
    hidusbfTool             = [string]$bundle.Root
    hidusbfTargetInstanceId = $target.usbParentId
    command                 = $run.command
    exitCode                = $exitCode
    stderr                  = [string]$run.stderr
    ocCode                  = if ($oc) { [string]$oc.Code } else { '' }
    ocMessage               = if ($oc) { [string]$oc.Message } else { '' }
} -LogDir $LogDir
