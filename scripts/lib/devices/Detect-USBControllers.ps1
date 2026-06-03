#Requires -Version 5.1
<#
.SYNOPSIS
  Active controller detection — PnP present devices only, one card per physical controller.
  HIDUSBF/registry used for configuredRate display only, never for presence.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$OutputPath = '',
    [string]$PresentPath = '',
    [string]$FinalPath = '',
    [string]$SignaturePath = '',
    [string]$Reason = 'initial'
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')
. (Join-Path $PSScriptRoot 'Controller-Presence-Common.ps1')

function Resolve-UnrealAppRootLocal([string]$root) {
    if ($root -and (Test-Path -LiteralPath $root)) { return (Resolve-Path -LiteralPath $root).Path }
    $here = $PSScriptRoot
    if ($here) {
        $c = Split-Path -Parent (Split-Path -Parent $here)
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'Unreal.hta'))) { return $c }
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}

function Write-DetectLog([string]$line, [string]$logFile) {
    if (-not $logFile) { return }
    $dir = Split-Path -Parent $logFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $logFile -Value "[$ts] $line" -Encoding UTF8
}

function Test-IsInputDeviceExcluded([string]$text) {
    if (-not $text) { return $false }
    if (Test-IsControllerChildName $text) { return $false }
    return ($text -match '(?i)keyboard|clavier|mouse|souris|touchpad|trackpad|digitizer|consumer\s+control|vendor-defined|bluetooth\s+le\s+generic|sensor|biometric|headset|receiver|dongle')
}

function Test-IsGameControllerName([string]$text) {
    if (-not $text) { return $false }
    if (Test-IsInputDeviceExcluded $text) { return $false }
    return ($text -match '(?i)DualSense|DualShock|DUALSHOCK|Wireless\s+Controller|PS4|PS5|Xbox|XInput|Controller|Game\s+Controller|HID-compliant\s+game|Contr.leur de jeu|P.riph.rique de jeu|entr.e\s+USB|USB\s+Input|composite|manette|gamepad|joystick')
}

function Test-IsControllerPnpNode {
    param([object]$Dev, [string]$InstanceId, [string]$FriendlyName)
    $deviceId = if ($InstanceId) { $InstanceId } else { [string]$Dev.InstanceId }
    if (-not $deviceId -or $deviceId -notmatch 'VID_[0-9A-Fa-f]{4}') { return $false }
    $blob = ($deviceId + ' ' + $FriendlyName)
    $vp = Get-VidPidFromInstanceId $deviceId
    if ($vp.Vid -eq '054C' -and $vp.Pid) { return $true }
    if ($vp.Vid -eq '045E' -and (Test-IsGameControllerName $blob)) { return $true }
    if ($deviceId -match '(?i)MI_03' -and $vp.Vid -match '^(054C|045E)$') { return $true }
    if ($blob -match '(?i)DualSense|DualShock|DUALSHOCK|Wireless\s+Controller|HID-compliant\s+game|game\s+controller|Contr.leur de jeu|Xbox|XInput|gamepad|joystick') {
        if (-not (Test-IsInputDeviceExcluded $blob)) { return $true }
    }
    return $false
}

function Get-UsbRootParentId {
    param([string]$InstanceId)
    $id = Normalize-DeviceInstanceId $InstanceId
    if (-not $id) { return '' }
    if ($id -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}\\[^&]+') {
        return $Matches[0]
    }
    if ($id -match '(?i)^USB\\') {
        $parts = $id -split '\\'
        if ($parts.Count -ge 3 -and $parts[1] -match 'VID_' -and $parts[2] -notmatch 'MI_') {
            return ('USB\' + $parts[1] + '\' + $parts[2])
        }
    }
    return ''
}

function Get-NameDisplayRank([string]$name) {
    if ($name -match '(?i)DualSense|DualShock|Wireless\s+Controller') { return 100 }
    if ($name -match '(?i)Contr.leur de jeu|HID-compliant\s+game|game\s+controller') { return 70 }
    if ($name -match '(?i)entr.e\s+USB|USB\s+Input') { return 40 }
    if ($name -match '(?i)composite|USB\s+composite') { return 20 }
    return 10
}

function Get-InstanceRank([string]$instanceId) {
    if ($instanceId -match '(?i)^HID\\' -and $instanceId -match '(?i)MI_03') { return 90 }
    if ($instanceId -match '(?i)^HID\\') { return 60 }
    if ($instanceId -match '(?i)^USB\\' -and $instanceId -match '(?i)MI_') { return 50 }
    if ($instanceId -match '(?i)^USB\\' -and $instanceId -notmatch '(?i)MI_') { return 80 }
    return 10
}

function New-RawMember {
    param([string]$InstanceId, [string]$FriendlyName, [string]$PnpClass, [string]$Status)
    $vp = Get-VidPidFromInstanceId $InstanceId
    $reg = Get-EnumDeviceRegistryInfo -InstanceId $InstanceId
    return [PSCustomObject]@{
        InstanceId    = $InstanceId
        FriendlyName  = $FriendlyName
        Name          = $FriendlyName
        PNPClass      = $PnpClass
        PnpStatus     = $Status
        Vid           = $vp.Vid
        ProductId     = $vp.Pid
        ContainerId   = [string]$reg.ContainerId
        UsbRootParent = (Get-UsbRootParentId $InstanceId)
    }
}

function Get-PhysicalGroupKey {
    param($Member)
    if ($Member.ContainerId) {
        return ('CID:' + $Member.ContainerId.ToUpperInvariant())
    }
    if ($Member.UsbRootParent) {
        return ('USB:' + $Member.UsbRootParent.ToUpperInvariant())
    }
    return ('RAW:' + $Member.InstanceId.ToUpperInvariant())
}

$app = Resolve-UnrealAppRootLocal $AppRoot
if (-not $app) { $app = Resolve-UnrealAppRoot '' }
if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }
if (-not $OutputPath) { $OutputPath = Join-Path $app 'logs\controller-overclocker-detect.json' }
if (-not $PresentPath) { $PresentPath = Join-Path $app 'logs\controller-devices-present.json' }
if (-not $FinalPath) { $FinalPath = Join-Path $app 'logs\controller-devices-final.json' }
if (-not $SignaturePath) { $SignaturePath = Join-Path $app 'logs\controller-device-signature.json' }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-DetectLog ("[DEVICE-DETECT] start reason=" + $Reason) $LogPath

$presentSet = @{}
$rawMembers = New-Object System.Collections.Generic.List[object]
$pnpPresentCount = 0

if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
    foreach ($pd in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
        $instId = Normalize-DeviceInstanceId ([string]$pd.InstanceId)
        if (-not $instId) { continue }
        if (-not (Test-PnpStatusPresent ([string]$pd.Status))) { continue }
        $fname = [string]$pd.FriendlyName
        if (-not (Test-IsControllerPnpNode -InstanceId $instId -FriendlyName $fname)) { continue }
        $pnpPresentCount++
        $presentSet[$instId.ToUpperInvariant()] = $true
        $rawMembers.Add((New-RawMember -InstanceId $instId -FriendlyName $fname -PnpClass ([string]$pd.Class) -Status ([string]$pd.Status))) | Out-Null
    }
}

if (-not $rawMembers.Count) {
    try {
        foreach ($ent in @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)) {
            if ([int]$ent.ConfigManagerErrorCode -ne 0) { continue }
            $instId = Normalize-DeviceInstanceId ([string]$ent.PNPDeviceID)
            if (-not $instId) { continue }
            $fname = [string]$ent.Name
            if (-not $fname) { $fname = [string]$ent.Description }
            if (-not (Test-IsControllerPnpNode -InstanceId $instId -FriendlyName $fname)) { continue }
            if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
                $chk = Test-ControllerDevicePresent -DeviceInstanceId $instId
                if (-not $chk.Present) { continue }
            }
            $pnpPresentCount++
            $presentSet[$instId.ToUpperInvariant()] = $true
            $rawMembers.Add((New-RawMember -InstanceId $instId -FriendlyName $fname -PnpClass 'PnPEntity' -Status 'OK')) | Out-Null
        }
    } catch {
        Write-DetectLog ('[DEVICE-DETECT] WMI fallback error: ' + $_.Exception.Message) $LogPath
    }
}

$rawCount = $rawMembers.Count
Write-DetectLog ("[DEVICE-DETECT] pnp_present_count=" + $pnpPresentCount) $LogPath
Write-DetectLog ("[DEVICE-DETECT] raw_nodes_count=" + $rawCount) $LogPath

foreach ($member in @($rawMembers)) {
    if (-not $member.UsbRootParent) {
        try {
            $target = Resolve-HidusbfCompositeTarget -DeviceInstanceId $member.InstanceId `
                -Vid $member.Vid -DevicePid $member.ProductId -LogFile $LogPath
            if ($target -and $target.TargetHidusbfDeviceId) {
                $member.UsbRootParent = Normalize-DeviceInstanceId ([string]$target.TargetHidusbfDeviceId)
            }
        } catch {}
    }
    if (-not $member.ContainerId -and $member.UsbRootParent) {
        $member.ContainerId = [string](Get-EnumDeviceRegistryInfo -InstanceId $member.UsbRootParent).ContainerId
    }
}

$groups = @{}
foreach ($member in $rawMembers) {
    $gk = Get-PhysicalGroupKey $member
    if (-not $groups.ContainsKey($gk)) {
        $groups[$gk] = @()
    }
    $groups[$gk] = @($groups[$gk] + $member)
}

$cards = New-Object System.Collections.Generic.List[object]
$removedAbsent = 0

foreach ($gk in ($groups.Keys | Sort-Object)) {
    $members = @($groups[$gk])
    if ($members.Count -eq 1 -and $members[0] -is [System.Collections.Generic.List[object]]) {
        $members = @($members[0].ToArray())
    }
    if (-not $members -or $members.Count -lt 1) {
        $removedAbsent++
        continue
    }

    $bestMember = $null
    $bestScore = -1
    foreach ($m in $members) {
        $score = (Get-NameDisplayRank $m.FriendlyName) + (Get-InstanceRank $m.InstanceId)
        if ($score -gt $bestScore) { $bestScore = $score; $bestMember = $m }
    }
    if (-not $bestMember) { continue }

    $usbParent = ''
    foreach ($m in $members) {
        if ($m.UsbRootParent) { $usbParent = $m.UsbRootParent; break }
    }
    if (-not $usbParent) { $usbParent = $bestMember.UsbRootParent }

    $hidInstance = $bestMember.InstanceId
    foreach ($m in $members) {
        if ($m.InstanceId -match '(?i)^HID\\' -and $m.InstanceId -match '(?i)MI_03') {
            $hidInstance = $m.InstanceId
            break
        }
    }
    foreach ($m in $members) {
        if ($m.InstanceId -match '(?i)^HID\\' -and $hidInstance -notmatch '(?i)MI_03') {
            $hidInstance = $m.InstanceId
        }
    }

    $parentVid = $bestMember.Vid
    $parentProductId = $bestMember.ProductId
    if ($usbParent) {
        $pvp = Get-VidPidFromInstanceId $usbParent
        if ($pvp.Vid) { $parentVid = $pvp.Vid }
        if ($pvp.Pid) { $parentProductId = $pvp.Pid }
    }

    $nameBlob = (($members | ForEach-Object { $_.FriendlyName + ' ' + $_.InstanceId }) -join ' | ')
    $cap = Get-ControllerTypeAndCapability -Vid $parentVid -DevicePid $parentProductId -NameBlob $nameBlob

    $displayName = 'Controller'
    $bestNameScore = -1
    foreach ($m in $members) {
        $nr = Get-NameDisplayRank $m.FriendlyName
        if ($nr -gt $bestNameScore) {
            $bestNameScore = $nr
            if ($m.FriendlyName -match '(?i)DualSense') { $displayName = 'PS5 DualSense' }
            elseif ($m.FriendlyName -match '(?i)Wireless|DualShock') { $displayName = 'PS4 DualShock' }
            elseif ($m.FriendlyName) { $displayName = $m.FriendlyName }
        }
    }
    if ([string]$cap.Type -eq 'DualSense') { $displayName = 'PS5 DualSense' }
    elseif ([string]$cap.Type -eq 'PS4') { $displayName = 'PS4 DualShock' }

    $maxHz = [int]$cap.MaxRateHz
    if ($maxHz -le 0) { $maxHz = 1000 }
    if ($parentVid -eq '054C' -and $parentProductId -eq '0CE6') { $maxHz = 8000 }
    elseif ($parentVid -eq '054C' -and $parentProductId -match '^(05C4|09CC|0BA0)$') { $maxHz = 1000 }

    $hidusbfParent = $usbParent
    try {
        $composite = Resolve-HidusbfCompositeTarget -DeviceInstanceId $hidInstance -Vid $parentVid -DevicePid $parentProductId `
            -HintUsbParentId $usbParent -LogFile $LogPath
        if ($composite -and $composite.TargetHidusbfDeviceId) {
            $hidusbfParent = Normalize-DeviceInstanceId ([string]$composite.TargetHidusbfDeviceId)
        }
    } catch {}

    $configuredRate = 125
    $currentRate = 125
    $hasFilter = $false
    $isBoosted = $false
    $isConfirmed = $false
    $buttonMode = 'boost'
    $statusSource = 'default'
    if ($hidusbfParent -and $hidusbfParent -notmatch '(?i)&MI_\d+') {
        $stH = Get-HidusbfConfirmedStatusForParent -UsbParentDeviceId $hidusbfParent -Vid $parentVid -DevicePid $parentProductId
        if ($stH) {
            $configuredRate = [int]$stH.ConfiguredRate
            if ($configuredRate -le 0) { $configuredRate = [int]$stH.ConfirmedRate }
            $currentRate = [int]$stH.ConfirmedRate
            if ($currentRate -le 0) { $currentRate = $configuredRate }
            if ($currentRate -le 0) { $currentRate = 125 }
            $hasFilter = ($stH.HidusbfFilterPresent -eq $true) -or ($configuredRate -gt 125) -or ($currentRate -gt 125)
            $isBoosted = $hasFilter -or ($currentRate -gt 125)
            $isConfirmed = $isBoosted -and ($hasFilter -or ($currentRate -gt 125))
            if ($isBoosted) { $buttonMode = 'restore' }
            $statusSource = 'hidusbf'
        }
    } elseif ($usbParent) {
        $configuredRate = [int](Get-UsbParentPollingRate -UsbParentDeviceId $usbParent)
        $currentRate = $configuredRate
        $hasFilter = $configuredRate -gt 125
        $isBoosted = $hasFilter
        $isConfirmed = $isBoosted
        if ($isBoosted) { $buttonMode = 'restore' }
        $statusSource = 'polling'
    }
    $usbParent = if ($hidusbfParent) { $hidusbfParent } else { $usbParent }

    $cards.Add([PSCustomObject]@{
        DisplayName           = $displayName
        ChildName             = $bestMember.FriendlyName
        Name                  = $displayName
        FriendlyName          = $displayName
        DeviceInstanceId      = $hidInstance
        InstanceId            = $hidInstance
        DeviceId              = $hidInstance
        UsbParentDeviceId     = $usbParent
        UsbCompositeParentId  = $usbParent
        TargetHidusbfDeviceId = $usbParent
        Vid                   = $parentVid
        Pid                   = $parentProductId
        Type                  = [string]$cap.Type
        Badge                 = [string]$cap.Badge
        MaxRateHz             = $maxHz
        CurrentRateHz         = $currentRate
        ConfiguredRate        = $configuredRate
        ConfiguredRateHz      = $configuredRate
        PollingRateHz         = $currentRate
        HasFilter             = $hasFilter
        HidusbfInstalled      = $hasFilter
        IsBoosted             = $isBoosted
        IsConfirmed           = $isConfirmed
        ButtonMode            = $buttonMode
        StatusSource          = $statusSource
        Present               = $true
        ParentResolved        = [bool]$usbParent
        FromCache             = $false
        CardId                = if ($usbParent) { $usbParent } else { $gk }
        ContainerId           = [string]$bestMember.ContainerId
    }) | Out-Null
}

$finalDedup = @{}
foreach ($c in $cards) {
    $dk = if ($c.ContainerId) { ('CID:' + $c.ContainerId).ToUpperInvariant() }
    elseif ($c.UsbParentDeviceId) { $c.UsbParentDeviceId.ToUpperInvariant() }
    elseif ($c.Vid -eq '054C' -and $c.Pid -eq '0CE6') { 'T:PS5' }
    elseif ($c.Vid -eq '054C') { 'T:PS4:' + $c.UsbParentDeviceId.ToUpperInvariant() }
    else { ($c.Vid + ':' + $c.Pid + ':' + $c.DeviceInstanceId).ToUpperInvariant() }
    if (-not $finalDedup.ContainsKey($dk)) {
        $finalDedup[$dk] = $c
    } else {
        Write-DetectLog ("[DEVICE-DETECT] removed_duplicate=" + $dk) $LogPath
    }
}

$list = @($finalDedup.Values | Sort-Object Type, DisplayName)
$groupCount = $groups.Count
$finalCount = $list.Count
$removedAbsent = [Math]::Max($removedAbsent, ($groupCount - $finalCount))

Write-DetectLog ("[DEVICE-DETECT] groups_count=" + $groupCount) $LogPath
Write-DetectLog ("[DEVICE-DETECT] removed_absent=" + $removedAbsent) $LogPath
Write-DetectLog ("[DEVICE-DETECT] final_cards_count=" + $finalCount) $LogPath

$sigParts = New-Object System.Collections.Generic.List[string]
foreach ($c in $list) {
    $sigParts.Add((
        ($c.Vid + ':' + $c.Pid + ':' + ($c.ContainerId -replace '\s', '') + ':' + $c.UsbParentDeviceId + ':' + $c.DeviceInstanceId)
    ).ToUpperInvariant()) | Out-Null
}
$signature = ($sigParts | Sort-Object) -join '|'

if (-not $list.Count) { $json = '[]' }
elseif ($list.Count -eq 1) { $json = '[' + (($list[0] | ConvertTo-Json -Depth 6 -Compress)) + ']' }
else { $json = $list | ConvertTo-Json -Depth 6 -Compress:$false }

function Write-OutFile([string]$path, [string]$content) {
    if (-not $path) { return }
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
}

Write-OutFile $PresentPath $json
Write-OutFile $FinalPath $json
Write-OutFile $OutputPath $json
Write-OutFile $SignaturePath (@{
    Success = $true; Signature = $signature; Count = $list.Count; Parents = @($list | ForEach-Object { $_.UsbParentDeviceId })
} | ConvertTo-Json -Compress)

if ($list.Count -gt 0) {
    $cachePath = Join-Path $app 'logs\controller-devices-cache.json'
    Write-OutFile $cachePath $json
}

$sw.Stop()
Write-DetectLog ("[DEVICE-DETECT] duration_ms=" + $sw.ElapsedMilliseconds) $LogPath
Write-DetectLog '[DEVICE-DETECT] signature_changed=n/a' $LogPath
Write-DetectLog 'PRESENT_SOURCE=PnPPresentOnly' $LogPath
Write-DetectLog 'CACHE_USED_AS_FINAL=false' $LogPath
Write-DetectLog 'REGISTRY_USED_AS_PRESENT=false' $LogPath
Write-DetectLog ("CONNECTED_CONTROLLERS_COUNT=" + $finalCount) $LogPath
exit 0
