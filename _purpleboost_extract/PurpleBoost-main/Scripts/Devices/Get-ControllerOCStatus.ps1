#Requires -Version 5.1
<#
.SYNOPSIS
  Read current Controller OC polling status from HIDUSBF registry (no writes).
  Confirmed rate comes from LowerFilters + PatchUSBXHCI only — not from last apply JSON.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$OutputPath = '',
    [string]$DeviceInstanceId = '',
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

function Write-StatusLog {
    param([string]$Line)
    if (-not $script:StatusLogPath) { return }
    Write-DeviceLog ("[DEVICE] " + $Line) $script:StatusLogPath
}

function Test-LowerFilterHidusbf {
    param([string]$RegPath)
    if (-not $RegPath -or -not (Test-Path -LiteralPath $RegPath)) { return $false }
    try {
        $prop = Get-ItemProperty -LiteralPath $RegPath -Name LowerFilters -ErrorAction Stop
        return ($null -ne $prop.LowerFilters -and @($prop.LowerFilters) -contains 'hidusbf')
    } catch {
        return $false
    }
}

function Get-HidusbfPatchValues {
    $port = $null
    $xhci = $null
    foreach ($keyPath in @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\hidusbf\Parameters',
        'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF'
    )) {
        if (-not (Test-Path -LiteralPath $keyPath)) { continue }
        try {
            if ($null -eq $port) {
                $port = (Get-ItemProperty -LiteralPath $keyPath -Name PatchUSBPort -ErrorAction SilentlyContinue).PatchUSBPort
            }
            if ($null -eq $xhci) {
                $xhci = (Get-ItemProperty -LiteralPath $keyPath -Name PatchUSBXHCI -ErrorAction SilentlyContinue).PatchUSBXHCI
            }
        } catch {}
    }
    return [ordered]@{
        PatchUSBPort  = $port
        PatchUSBXHCI  = $xhci
    }
}

function Get-ResponseTimeMsForRate {
    param([int]$RateHz)
    switch ($RateHz) {
        1000 { return 1.0 }
        8000 { return 0.125 }
        default { return 8.0 }
    }
}

function Get-DeviceBadgeLabel {
    param([string]$Vid, [string]$DevicePid, [string]$TypeLabel)
    $vidU = ($Vid + '').ToUpperInvariant()
    $pidU = ($DevicePid + '').ToUpperInvariant()
    if ($vidU -eq '054C' -and $pidU -match '^(0CE6|0DF2|0E5F)$') { return 'PS5 DualSense' }
    if ($vidU -eq '054C' -and $pidU -match '^(05C4|0BA0)$') { return 'PS4 DualShock' }
    if ($vidU -eq '045E') { return 'Xbox Controller' }
    if ($TypeLabel) { return $TypeLabel }
    return 'Manette USB/HID'
}

function Write-StatusJson {
    param([hashtable]$Payload, [string]$OutputPath)
    if (-not $OutputPath) { return }
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Payload | ConvertTo-Json -Depth 6 -Compress:$false
    [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Build-StatusPayload {
    param(
        [bool]$Success,
        [int]$ConfirmedRate,
        [string]$Status,
        [string]$Badge,
        [bool]$Optimized,
        [double]$ResponseTimeMs,
        [string]$Color,
        [string]$Message,
        [hashtable]$Extra = @{}
    )
    $p = [ordered]@{
        Success        = $Success
        ConfirmedRate  = $ConfirmedRate
        ConfiguredRate = $ConfirmedRate
        Status         = $Status
        Badge          = $Badge
        Optimized      = $Optimized
        Verified       = $Optimized
        ResponseTimeMs = $ResponseTimeMs
        Color          = $Color
        Message        = $Message
        DeviceFound    = $true
        Present        = $true
    }
    foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
    return $p
}

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) {
    $fail = Build-StatusPayload -Success $false -ConfirmedRate 0 -Status 'Unknown' -Badge 'INCONNU' `
        -Optimized $false -ResponseTimeMs 8.0 -Color 'orange' -Message 'Impossible de determiner le polling actuel'
    Write-StatusJson -Payload $fail -OutputPath $OutputPath
    exit 1
}

if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }
if (-not $OutputPath) { $OutputPath = Join-Path $app 'logs\controller-overclocker-status.json' }
$script:StatusLogPath = $LogPath

Write-StatusLog 'Reading OC status'

if (-not $DeviceInstanceId) {
    $empty = Build-StatusPayload -Success $false -ConfirmedRate 0 -Status 'Unknown' -Badge 'INCONNU' `
        -Optimized $false -ResponseTimeMs 8.0 -Color 'orange' -Message 'Aucun peripherique selectionne'
    $empty.DeviceFound = $false
    $empty.Present = $false
    Write-StatusJson -Payload $empty -OutputPath $OutputPath
    exit 0
}

Write-StatusLog ("Selected controller=" + $DeviceInstanceId)

if (-not $Vid -or -not $DevicePid) {
    $vp = Get-VidPidFromInstanceId $DeviceInstanceId
    if (-not $Vid) { $Vid = $vp.Vid }
    if (-not $DevicePid) { $DevicePid = $vp.Pid }
}

$compositeTarget = Resolve-HidusbfCompositeTarget `
    -DeviceInstanceId $DeviceInstanceId `
    -Vid $Vid `
    -DevicePid $DevicePid `
    -HintUsbParentId $UsbParentDeviceId `
    -LogFile $script:StatusLogPath

$compositeId = [string]$compositeTarget.TargetHidusbfDeviceId
if (-not $compositeId) {
    $nf = Build-StatusPayload -Success $false -ConfirmedRate 0 -Status 'Unknown' -Badge 'INCONNU' `
        -Optimized $false -ResponseTimeMs 8.0 -Color 'orange' -Message 'Parent USB composite introuvable' `
        -Extra @{
            DeviceInstanceId      = $DeviceInstanceId
            UsbCompositeParentId  = ''
            TargetHidusbfDeviceId = ''
        }
    Write-StatusJson -Payload $nf -OutputPath $OutputPath
    exit 0
}

if ($compositeId -match '(?i)&MI_\d+') {
    $mi = Build-StatusPayload -Success $false -ConfirmedRate 0 -Status 'Unknown' -Badge 'INCONNU' `
        -Optimized $false -ResponseTimeMs 8.0 -Color 'orange' -Message 'Cible USB composite invalide (MI_)'
    Write-StatusJson -Payload $mi -OutputPath $OutputPath
    exit 0
}

$usbKey = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $compositeId
Write-StatusLog ("UsbParentDeviceId=" + $compositeId)

$filterActive = Test-LowerFilterHidusbf -RegPath $usbKey
$patch = Get-HidusbfPatchValues
$patchPort = $patch.PatchUSBPort
$patchXhci = $patch.PatchUSBXHCI

Write-StatusLog ("LowerFilters hidusbf=" + $filterActive.ToString().ToLowerInvariant())
Write-StatusLog ("PatchUSBPort=" + $patchPort + " PatchUSBXHCI=" + $patchXhci)

$bInterval = $null
$classKey = ''
try {
    $drv = (Get-ItemProperty -LiteralPath $usbKey -Name Driver -ErrorAction SilentlyContinue).Driver
    if ($drv) {
        $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $drv
        if (Test-Path -LiteralPath $classKey) {
            $bInterval = (Get-ItemProperty -LiteralPath $classKey -Name bInterval -ErrorAction SilentlyContinue).bInterval
            Write-StatusLog ("bInterval=" + $bInterval)
        }
    }
} catch {}

$typeLabel = 'HID Controller'
if ($Vid -eq '054C' -and $DevicePid -match '^(0CE6|0DF2|0E5F)$') { $typeLabel = 'DualSense' }
$deviceBadge = Get-DeviceBadgeLabel -Vid $Vid -DevicePid $DevicePid -TypeLabel $typeLabel

$extraCommon = @{
    DeviceInstanceId      = $DeviceInstanceId
    Vid                   = $Vid
    Pid                   = $DevicePid
    UsbCompositeParentId  = $compositeId
    TargetHidusbfDeviceId = $compositeId
    UsbParentDeviceId     = $compositeId
    DeviceBadge           = $deviceBadge
    HidusbfFilterPresent  = $filterActive
    PatchUSBPort          = $patchPort
    PatchUSBXHCI          = $patchXhci
    BInterval             = $bInterval
    DriverClassKey        = $classKey
}

if (-not $filterActive) {
    Write-StatusLog 'ConfirmedRate=125'
    Write-StatusLog 'Status=Default'
    $payload = Build-StatusPayload -Success $true -ConfirmedRate 125 -Status 'Default' -Badge 'DEFAULT' `
        -Optimized $false -ResponseTimeMs 8.0 -Color 'orange' -Message 'Default detecte' -Extra $extraCommon
    $payload.PotentialLabel = '0.13 ms'
    Write-StatusJson -Payload $payload -OutputPath $OutputPath
    exit 0
}

$xhciInt = if ($null -ne $patchXhci) { [int]$patchXhci } else { -1 }

if ($xhciInt -eq 3) {
    Write-StatusLog 'ConfirmedRate=8000'
    Write-StatusLog 'Status=Optimized8000'
    $payload = Build-StatusPayload -Success $true -ConfirmedRate 8000 -Status 'Optimized8000' -Badge 'OPTIMISE' `
        -Optimized $true -ResponseTimeMs 0.125 -Color 'green' -Message 'Optimise 8000 Hz confirme' -Extra $extraCommon
    $payload.PotentialLabel = 'maximum'
    Write-StatusJson -Payload $payload -OutputPath $OutputPath
    exit 0
}

if ($xhciInt -eq 1) {
    Write-StatusLog 'ConfirmedRate=1000'
    Write-StatusLog 'Status=Optimized1000'
    $payload = Build-StatusPayload -Success $true -ConfirmedRate 1000 -Status 'Optimized1000' -Badge 'OPTIMISE' `
        -Optimized $true -ResponseTimeMs 1.0 -Color 'green' -Message 'Optimise 1000 Hz confirme' -Extra $extraCommon
    $payload.PotentialLabel = '0.13 ms'
    Write-StatusJson -Payload $payload -OutputPath $OutputPath
    exit 0
}

Write-StatusLog 'ConfirmedRate=0 Status=Unknown'
$unknown = Build-StatusPayload -Success $false -ConfirmedRate 0 -Status 'Unknown' -Badge 'INCONNU' `
    -Optimized $false -ResponseTimeMs 8.0 -Color 'orange' -Message 'HIDUSBF actif mais rate non determine' -Extra $extraCommon
Write-StatusJson -Payload $unknown -OutputPath $OutputPath
exit 0
