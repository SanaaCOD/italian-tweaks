#Requires -Version 5.1
<#
.SYNOPSIS
  Read-only polling status for a selected controller (no registry writes).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$OutputPath = '',
    [string]$DeviceInstanceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

function Get-PollingResponseTimeMs {
    param([int]$RateHz)
    switch ($RateHz) {
        125 { return 8.0 }
        250 { return 4.0 }
        500 { return 2.0 }
        1000 { return 1.0 }
        2000 { return 0.5 }
        4000 { return 0.25 }
        8000 { return 0.125 }
        default {
            if ($RateHz -gt 0) { return [math]::Round(1000.0 / $RateHz, 3) }
            return 8.0
        }
    }
}

function Get-PollingRateLabel {
    param([int]$RateHz)
    if ($RateHz -le 0) { return 'Inconnu' }
    if ($RateHz -eq 125) { return 'Default / 125 Hz' }
    return ($RateHz.ToString() + ' Hz')
}

function Get-ControllerDeviceBadge {
    param([string]$Vid, [string]$DevicePid, [string]$TypeLabel)
    $vidU = ($Vid + '').ToUpperInvariant()
    $pidU = ($DevicePid + '').ToUpperInvariant()
    if ($vidU -eq '054C' -and $pidU -match '^(0CE6|0DF2|0E5F)$') { return 'PS5 DualSense' }
    if ($vidU -eq '054C' -and $pidU -match '^(05C4|0BA0)$') { return 'PS4 DualShock' }
    if ($vidU -eq '045E') { return 'Xbox Controller' }
    if ($TypeLabel) { return $TypeLabel }
    return 'Manette USB/HID'
}

function Get-PotentialLabel {
    param([int]$ConfiguredRate)
    if ($ConfiguredRate -ge 8000) { return 'deja au maximum' }
    return 'potentiel 0.125 ms a 8000 Hz'
}

function Test-LowerFilterPresent {
    param([string]$RegPath)
    if (-not $RegPath -or -not (Test-Path -LiteralPath $RegPath)) { return $false }
    try {
        $prop = Get-ItemProperty -LiteralPath $RegPath -Name LowerFilters -ErrorAction Stop
        return ($null -ne $prop.LowerFilters -and @($prop.LowerFilters) -contains 'hidusbf')
    } catch {
        return $false
    }
}

function Get-LowerFiltersText {
    param([string]$RegPath)
    if (-not $RegPath -or -not (Test-Path -LiteralPath $RegPath)) { return '(missing)' }
    try {
        $prop = Get-ItemProperty -LiteralPath $RegPath -Name LowerFilters -ErrorAction SilentlyContinue
        if ($null -eq $prop -or $null -eq $prop.LowerFilters) { return '(none)' }
        return '[' + (@($prop.LowerFilters) -join ', ') + ']'
    } catch {
        return '(error)'
    }
}

function Read-DeviceParametersSnapshot {
    param([string[]]$RegPaths)
    $out = [ordered]@{}
    foreach ($regPath in @($RegPaths | Where-Object { $_ } | Select-Object -Unique)) {
        $paramPath = Join-Path $regPath 'Device Parameters'
        if (-not (Test-Path -LiteralPath $paramPath)) { continue }
        try {
            $props = Get-ItemProperty -LiteralPath $paramPath -ErrorAction Stop
            foreach ($name in $props.PSObject.Properties.Name) {
                if ($name -match '^PS') { continue }
                $out[$name] = $props.$name
            }
        } catch {}
    }
    return $out
}

function Get-ActiveHidusbfVariantRate {
    param([string]$AppRoot)
    $bundle = Resolve-HidusbfBundle $AppRoot
    if (-not $bundle.Found) { return $null }

    $activeCandidates = @(
        (Join-Path $bundle.DriverDir 'AMD64_AS\hidusbf.sys'),
        (Join-Path $bundle.Root 'AMD64_AS\hidusbf.sys')
    )
    $activeSys = $activeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $activeSys) { return $null }

    try {
        $activeHash = (Get-FileHash -LiteralPath $activeSys -Algorithm SHA256).Hash
        foreach ($rate in @(1000, 8000)) {
            $variant = Get-HidusbfVariantSysPath -Bundle $bundle -Rate $rate
            if (-not $variant -or -not (Test-Path -LiteralPath $variant)) { continue }
            $variantHash = (Get-FileHash -LiteralPath $variant -Algorithm SHA256).Hash
            if ($variantHash -eq $activeHash) { return $rate }
        }
        $activeSize = (Get-Item -LiteralPath $activeSys).Length
        foreach ($rate in @(1000, 8000)) {
            $variant = Get-HidusbfVariantSysPath -Bundle $bundle -Rate $rate
            if (-not $variant -or -not (Test-Path -LiteralPath $variant)) { continue }
            if ((Get-Item -LiteralPath $variant).Length -eq $activeSize) { return $rate }
        }
    } catch {}
    return $null
}

function Get-HidusbfPatchHintRate {
    try {
        foreach ($keyPath in @(
            'HKLM:\SYSTEM\CurrentControlSet\Services\HIDUSBF\Parameters',
            'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF'
        )) {
            if (-not (Test-Path -LiteralPath $keyPath)) { continue }
            $patch = (Get-ItemProperty -LiteralPath $keyPath -Name PatchUSBXHCI -ErrorAction SilentlyContinue).PatchUSBXHCI
            if ($null -eq $patch) { continue }
            if ([int]$patch -eq 3) { return 8000 }
            if ([int]$patch -eq 1) { return 1000 }
        }
    } catch {}
    return $null
}

function Read-AutomationConfirmedStatus {
    param(
        [string]$AppRoot,
        [string]$DeviceInstanceId,
        [string]$Vid,
        [string]$DevicePid
    )
    $path = Join-Path $AppRoot 'logs\controller-oc-result.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $json = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
        if ($json.Verified -ne $true -or $json.Success -ne $true) { return $null }
        $same = $true
        if ($json.DeviceInstanceId -and $DeviceInstanceId) {
            $same = ([string]$json.DeviceInstanceId).ToUpperInvariant() -eq $DeviceInstanceId.ToUpperInvariant()
        }
        if ($same -and $json.Vid -and $Vid) {
            $same = ([string]$json.Vid).ToUpperInvariant() -eq $Vid.ToUpperInvariant()
        }
        if ($same -and $json.Pid -and $DevicePid) {
            $same = ([string]$json.Pid).ToUpperInvariant() -eq $DevicePid.ToUpperInvariant()
        }
        if (-not $same) { return $null }
        return $json
    } catch {}
    return $null
}

function Read-RequestedRateFromParams {
    param(
        [string]$AppRoot,
        [string]$DeviceInstanceId,
        [string]$Vid,
        [string]$DevicePid
    )
    $paramsPath = Join-Path $AppRoot 'logs\controller-overclocker-params.json'
    if (-not (Test-Path -LiteralPath $paramsPath)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($paramsPath)
        $json = $raw | ConvertFrom-Json
        $sameDevice = $true
        if ($json.DeviceInstanceId -and $DeviceInstanceId) {
            $sameDevice = ([string]$json.DeviceInstanceId).ToUpperInvariant() -eq $DeviceInstanceId.ToUpperInvariant()
        }
        if ($sameDevice -and $json.Vid -and $Vid) {
            $sameDevice = ([string]$json.Vid).ToUpperInvariant() -eq $Vid.ToUpperInvariant()
        }
        if ($sameDevice -and $json.Pid -and $DevicePid) {
            $sameDevice = ([string]$json.Pid).ToUpperInvariant() -eq $DevicePid.ToUpperInvariant()
        }
        if ($sameDevice -and $json.Rate) {
            return [int]$json.Rate
        }
    } catch {}
    return $null
}

function Write-StatusJson {
    param(
        [hashtable]$Payload,
        [string]$OutputPath
    )
    if (-not $OutputPath) { return }
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Payload | ConvertTo-Json -Depth 6 -Compress:$false
    [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))
}

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) {
    $fail = [ordered]@{
        Success = $false
        Status  = 'Unknown'
        Message = 'Impossible de lire le polling rate'
    }
    Write-StatusJson -Payload $fail -OutputPath $OutputPath
    exit 1
}

function Write-StatusLog {
    param([string]$Line)
    if (-not $script:StatusLogPath) { return }
    Write-DeviceLog ("[DEVICE-STATUS] " + $Line) $script:StatusLogPath
}

if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }
if (-not $OutputPath) { $OutputPath = Join-Path $app 'logs\controller-overclocker-status.json' }
$script:StatusLogPath = $LogPath

Write-StatusLog 'Polling status refresh started'
Write-StatusLog ("DeviceInstanceId=" + $DeviceInstanceId)

if (-not $DeviceInstanceId) {
    $empty = [ordered]@{
        Success    = $true
        DeviceFound = $false
        Status     = 'Unknown'
        Message    = 'Aucun peripherique selectionne'
    }
    Write-StatusLog 'Status result: no_device_selected'
    Write-StatusJson -Payload $empty -OutputPath $OutputPath
    exit 0
}

Write-StatusLog ("VID/PID=" + $Vid + '/' + $DevicePid)
Write-StatusLog 'Reading HIDUSBF registry state'

$pnpMatch = $null
$targetId = ($DeviceInstanceId + '').ToUpperInvariant()
$mi = ''
if ($DeviceInstanceId -match '(?i)MI_(\d+)') { $mi = $Matches[1] }
try {
    foreach ($dev in (Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)) {
        $id = [string]$dev.DeviceID
        if ($targetId -and $id.ToUpperInvariant() -eq $targetId) { $pnpMatch = $dev; break }
        if (-not $Vid -or -not $DevicePid) { continue }
        if ($id -notmatch ('(?i)VID_' + [regex]::Escape($Vid))) { continue }
        if ($id -notmatch ('(?i)PID_' + [regex]::Escape($DevicePid))) { continue }
        if ($mi -and $id -notmatch ('(?i)MI_' + [regex]::Escape($mi))) { continue }
        if ($id -match '(?i)^(HID|USB)\\') { $pnpMatch = $dev; break }
    }
} catch {
    Write-StatusLog ("Device lookup failed: " + $_.Exception.Message)
}

if (-not $pnpMatch) {
    $missing = [ordered]@{
        Success          = $true
        DeviceFound      = $false
        DeviceInstanceId = $DeviceInstanceId
        Vid              = $Vid
        Pid              = $DevicePid
        Status           = 'Unknown'
        Message          = 'Peripherique deconnecte ou introuvable'
        Present          = $false
    }
    Write-StatusLog 'Device disconnected'
    Write-StatusLog 'Status result: device_not_found'
    Write-StatusJson -Payload $missing -OutputPath $OutputPath
    exit 0
}

$name = [string]$pnpMatch.Name
if (-not $name) { $name = [string]$pnpMatch.Caption }
$typeLabel = 'HID Controller'
if ($name -match '(?i)dualsense|ps5') { $typeLabel = 'DualSense' }
elseif ($Vid -eq '054C' -and $DevicePid -match '^(0CE6|0DF2|0E5F)$') { $typeLabel = 'DualSense' }
elseif ($name -match '(?i)xbox') { $typeLabel = 'Xbox' }

$compositeTarget = Resolve-HidusbfCompositeTarget `
    -DeviceInstanceId $DeviceInstanceId `
    -Vid $Vid `
    -DevicePid $DevicePid `
    -LogFile $script:StatusLogPath
$compositeId = [string]$compositeTarget.TargetHidusbfDeviceId
$compositeRegPath = ''
if ($compositeId) { $compositeRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $compositeId }

$filterComposite = $false
$bIntervalComposite = $null
$classKeyComposite = ''
if ($compositeRegPath -and (Test-Path -LiteralPath $compositeRegPath)) {
    $filterComposite = Test-LowerFilterPresent -RegPath $compositeRegPath
    Write-StatusLog ("Composite parent key=" + $compositeRegPath)
    Write-StatusLog ("LowerFilters=" + (Get-LowerFiltersText -RegPath $compositeRegPath))
    try {
        $drv = (Get-ItemProperty -LiteralPath $compositeRegPath -Name Driver -ErrorAction SilentlyContinue).Driver
        if ($drv) {
            $classKeyComposite = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $drv
            if (Test-Path -LiteralPath $classKeyComposite) {
                $bIntervalComposite = (Get-ItemProperty -LiteralPath $classKeyComposite -Name bInterval -ErrorAction SilentlyContinue).bInterval
                Write-StatusLog ("Composite class key=" + $classKeyComposite + " bInterval=" + $bIntervalComposite)
            }
        }
    } catch {}
}
$hidusbfFilterPresent = $filterComposite

foreach ($keyPath in @(
    'HKLM:\SYSTEM\CurrentControlSet\Services\HIDUSBF\Parameters',
    'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF'
)) {
    if (-not (Test-Path -LiteralPath $keyPath)) { continue }
    try {
        $patch = (Get-ItemProperty -LiteralPath $keyPath -Name PatchUSBXHCI -ErrorAction SilentlyContinue).PatchUSBXHCI
        $port = (Get-ItemProperty -LiteralPath $keyPath -Name PatchUSBPort -ErrorAction SilentlyContinue).PatchUSBPort
        Write-StatusLog ("HIDUSBF parameters=" + $keyPath + " PatchUSBXHCI=" + $patch + " PatchUSBPort=" + $port)
    } catch {}
}

Write-StatusLog ("HIDUSBF filter present=" + ($hidusbfFilterPresent.ToString().ToLowerInvariant()))

$deviceParams = @{}
if ($compositeRegPath) { $deviceParams = Read-DeviceParametersSnapshot -RegPaths @($compositeRegPath) }
$lastApply = $null
try {
    $applyPath = Join-Path $app 'logs\controller-oc-result.json'
    if (Test-Path -LiteralPath $applyPath) {
        $lastApply = [System.IO.File]::ReadAllText($applyPath) | ConvertFrom-Json
    }
} catch {}

$requestedRate = $null
if ($lastApply -and $null -ne $lastApply.RequestedRate -and [int]$lastApply.RequestedRate -in @(1000, 8000)) {
    $requestedRate = [int]$lastApply.RequestedRate
}

$bundleForStatus = Resolve-HidusbfToolPath -AppRoot $app -LogFile $script:StatusLogPath
$bundleHtStatus = @{}
if ($bundleForStatus.Resolved) {
    foreach ($k in $bundleForStatus.Keys) { $bundleHtStatus[$k] = $bundleForStatus[$k] }
}

$configuredRate = 125
$status = 'Default'
$verified = $false
$source = 'ControllerOC'
$message = 'Aucun reglage HIDUSBF confirme (Default)'

$activeVariantRate = $null
if ($bundleHtStatus.Count -gt 0) {
    $activeVariantRate = Get-ActiveHidusbfVariantRateFromBundle -Bundle $bundleHtStatus
}
$patchRate = Get-HidusbfPatchHintRate
$confirmedRate = 125
if ($activeVariantRate -in @(1000, 8000)) {
    $confirmedRate = [int]$activeVariantRate
} elseif ($patchRate -in @(1000, 8000)) {
    $confirmedRate = [int]$patchRate
}

if ($filterComposite -and $bIntervalComposite -eq 1 -and $confirmedRate -ge 1000) {
  if ($confirmedRate -ge 8000) {
        $configuredRate = 8000
        $status = 'Optimized8000'
        $verified = $true
        $message = 'Optimise 8000 Hz confirme'
    } else {
        $configuredRate = 1000
        $status = 'Optimized1000'
        $verified = $true
        $message = 'Optimise 1000 Hz confirme'
    }
    if ($requestedRate -eq 1000 -and $configuredRate -eq 8000) {
        $verified = $false
        $status = 'Mismatch'
        $message = '1000 Hz demande — 8000 Hz detecte'
    } elseif ($requestedRate -eq 8000 -and $configuredRate -ne 8000) {
        $verified = $false
        $status = 'Mismatch'
        $message = ('8000 Hz demande — ' + $configuredRate + ' Hz detecte')
    } elseif ($requestedRate -eq 1000 -and $configuredRate -eq 1000) {
        $verified = $true
        $status = 'Optimized1000'
        $message = 'Optimise 1000 Hz confirme'
    } elseif ($requestedRate -eq 8000 -and $configuredRate -eq 8000) {
        $verified = $true
        $status = 'Optimized8000'
        $message = 'Optimise 8000 Hz confirme'
    }
    Write-StatusLog ("Composite registry confirmed rate=" + $configuredRate)
} elseif ($lastApply -and $lastApply.Code -eq 'PREPARED_NEEDS_RECONNECT' -and $filterComposite) {
    $configuredRate = if ($requestedRate) { [int]$requestedRate } else { 125 }
    $status = 'Prepared'
    $verified = $false
    $message = 'Reglage ' + $configuredRate + ' Hz prepare — rebranche la manette pour confirmation'
    Write-StatusLog 'Composite prepared but not fully confirmed'
}

$responseMs = Get-PollingResponseTimeMs -RateHz $configuredRate
$rateLabel = Get-PollingRateLabel -RateHz $configuredRate
$badge = Get-ControllerDeviceBadge -Vid $Vid -DevicePid $DevicePid -TypeLabel $typeLabel

$needsReconnect = $false
if ($lastApply -and $lastApply.Code -eq 'PREPARED_NEEDS_RECONNECT') { $needsReconnect = $true }
if ($filterComposite -and -not $verified) { $needsReconnect = $true }
if ($requestedRate -and $status -match '^Optimized' -and $configuredRate -ne $requestedRate) { $needsReconnect = $true }

$statusLabel = switch ($status) {
    'Default' {
        if ($requestedRate -and -not $verified) { 'Non confirme / Default detecte' } else { 'Default' }
    }
    'Prepared' { 'Prepare — rebranche la manette' }
    'Optimized1000' { 'Optimise 1000 Hz (confirme)' }
    'Optimized8000' { 'Optimise 8000 Hz (confirme)' }
    default { 'Inconnu' }
}

$upToDate = $verified
$statusBadge = if ($verified) { 'Confirme' } elseif ($requestedRate) { 'Non confirme' } else { 'Default' }

Write-StatusLog ("ConfiguredRate=" + $configuredRate)
Write-StatusLog ("Status=" + $status)
Write-StatusLog ("Verified=" + ($verified.ToString().ToLowerInvariant()))
if ($requestedRate) { Write-StatusLog ("RequestedRate=" + $requestedRate) }

$result = [ordered]@{
    Success               = $true
    DeviceFound           = $true
    Name                  = $name
    DeviceInstanceId      = $DeviceInstanceId
    UsbCompositeParentId  = $compositeId
    TargetHidusbfDeviceId = $compositeId
    Vid                   = $Vid
    Pid                   = $DevicePid
    TypeLabel             = $typeLabel
    DeviceBadge           = $badge
    HidusbfFilterPresent  = $hidusbfFilterPresent
    ConfiguredRate        = $configuredRate
    ConfiguredRateLabel   = $rateLabel
    RequestedRate         = if ($requestedRate) { [int]$requestedRate } else { $null }
    ConfirmedRate         = $configuredRate
    RequestedRateLabel    = if ($requestedRate) { (Get-PollingRateLabel -RateHz $requestedRate) } else { $null }
    Verified              = $verified
    Status                = $status
    StatusLabel           = $statusLabel
    ResponseTimeMs        = $responseMs
    ResponseTimeLabel     = (($responseMs.ToString('0.###')) + ' ms')
    PotentialLabel        = Get-PotentialLabel -ConfiguredRate $configuredRate
    NeedsReconnect        = $needsReconnect
    UpToDate              = $upToDate
    StatusBadge           = $statusBadge
    Source                = $source
    Message               = $message
    DeviceParameters      = $deviceParams
    Present               = $true
}

Write-StatusJson -Payload $result -OutputPath $OutputPath
exit 0
