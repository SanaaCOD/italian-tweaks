#Requires -Version 5.1
<#
.SYNOPSIS
  Fast controller detection via registry Enum (no heavy Win32_PnPEntity scan).
  Writes fast-only JSON; empty fast result does not touch cache (HTA runs full fallback).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$OutputPath = '',
    [string]$FastOutputPath = '',
    [string]$CachePath = ''
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

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

function Test-IsControllerNameBlob {
    param([string]$Blob)
    if (-not $Blob) { return $false }
    if ($Blob -match '(?i)keyboard|clavier|mouse|souris|touchpad|trackpad|digitizer|consumer\s+control|vendor-defined|bluetooth\s+le\s+generic') { return $false }
    return ($Blob -match '(?i)DualSense|DualShock|DUALSHOCK|Wireless\s+Controller|PS4|PS5|Xbox|XInput|Controller|Game\s+Controller|HID-compliant\s+game|Contr.leur de jeu|P.riph.rique de jeu|entr.e\s+USB|USB\s+Input|composite|manette|gamepad|joystick')
}

function Test-IsControllerUsbComposite {
    param([string]$InstanceId, [string]$FriendlyName)
    if (-not $InstanceId) { return $false }
    if ($InstanceId -notmatch '(?i)^USB\\') { return $false }
    if ($InstanceId -match '(?i)&MI_\d+') { return $false }
    $vp = Get-VidPidFromInstanceId $InstanceId
    if ($vp.Vid -eq '054C' -and $vp.Pid) { return $true }
    if ($vp.Vid -eq '045E' -and $vp.Pid) { return $true }
    $blob = ($InstanceId + ' ' + $FriendlyName)
    if (Test-IsControllerNameBlob $blob) { return $true }
    return $false
}

function Test-IsControllerHidInstance {
    param([string]$InstanceId, [string]$FriendlyName)
    if (-not $InstanceId) { return $false }
    if ($InstanceId -notmatch '(?i)^HID\\') { return $false }
    $vp = Get-VidPidFromInstanceId $InstanceId
    if ($vp.Vid -eq '054C' -and $vp.Pid) { return $true }
    if ($vp.Vid -eq '045E' -and $vp.Pid) { return $true }
    $blob = ($InstanceId + ' ' + $FriendlyName)
    if (Test-IsControllerNameBlob $blob) { return $true }
    if ($InstanceId -match '(?i)MI_03') { return $true }
    return $false
}

function Read-EnumFriendlyName {
    param([string]$InstanceId)
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $InstanceId
    if (-not (Test-Path -LiteralPath $regPath)) { return '' }
    try {
        $p = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
        if ($p.FriendlyName) { return [string]$p.FriendlyName }
        if ($p.DeviceDesc) { return [string]$p.DeviceDesc }
    } catch {}
    return ''
}

function Read-EnumContainerId {
    param([string]$InstanceId)
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $InstanceId
    if (-not (Test-Path -LiteralPath $regPath)) { return '' }
    try {
        $p = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
        if ($p.ContainerID) { return [string]$p.ContainerID }
    } catch {}
    return ''
}

function Get-HidInstanceForParent {
    param(
        [string]$UsbParentId,
        [string]$Vid,
        [string]$Pid,
        [hashtable]$HidByContainer,
        [hashtable]$HidByVidPid
    )
    $cid = Read-EnumContainerId -InstanceId $UsbParentId
    if ($cid) {
        $cu = $cid.ToUpperInvariant()
        if ($HidByContainer.ContainsKey($cu)) { return [string]$HidByContainer[$cu] }
    }
    $key = ($Vid + ':' + $Pid).ToUpperInvariant()
    if ($HidByVidPid.ContainsKey($key)) {
        $list = @($HidByVidPid[$key])
        foreach ($hid in $list) {
            if ($hid -match '(?i)MI_03') { return $hid }
        }
        return [string]$list[0]
    }
    return ''
}

function Write-JsonFile {
    param([string]$Path, [string]$Json)
    if (-not $Path) { return }
    $outDir = Split-Path -Parent $Path
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
}

$app = Resolve-UnrealAppRootLocal $AppRoot
if (-not $app) { $app = Resolve-UnrealAppRoot '' }
if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }
if (-not $FastOutputPath) { $FastOutputPath = Join-Path $app 'logs\controller-devices-fast.json' }
if (-not $OutputPath) { $OutputPath = $FastOutputPath }
if (-not $CachePath) { $CachePath = Join-Path $app 'logs\controller-devices-cache.json' }

Write-DetectLog '[DEVICE] Fast scan started (registry)' $LogPath

$enumRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
$usbParents = @{}
$hidByContainer = @{}
$hidByVidPid = @{}
$containerToUsbParent = @{}
$script:dedupeKeys = @{}

$usbRoot = Join-Path $enumRoot 'USB'
if (Test-Path -LiteralPath $usbRoot) {
    foreach ($vidPidKey in Get-ChildItem -LiteralPath $usbRoot -ErrorAction SilentlyContinue) {
        $vidPidName = $vidPidKey.PSChildName
        if ($vidPidName -notmatch '(?i)VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') { continue }
        $vid = $Matches[1].ToUpperInvariant()
        $pid = $Matches[2].ToUpperInvariant()
        if ($vid -ne '054C' -and $vid -ne '045E') { continue }

        foreach ($instKey in Get-ChildItem -LiteralPath $vidPidKey.PSPath -ErrorAction SilentlyContinue) {
            $instName = $instKey.PSChildName
            $fullId = ('USB\' + $vidPidName + '\' + $instName)
            $fname = Read-EnumFriendlyName -InstanceId $fullId
            if (Test-IsControllerUsbComposite -InstanceId $fullId -FriendlyName $fname) {
                $key = $fullId.ToUpperInvariant()
                $cid = Read-EnumContainerId -InstanceId $fullId
                $usbParents[$key] = [ordered]@{
                    InstanceId   = $fullId
                    FriendlyName = $fname
                    Vid          = $vid
                    Pid          = $pid
                    ContainerId  = $cid
                }
                if ($cid) { $containerToUsbParent[$cid.ToUpperInvariant()] = $fullId }
            }
        }
    }
}

$hidRootAll = Join-Path $enumRoot 'HID'
if (Test-Path -LiteralPath $hidRootAll) {
    foreach ($vidPidKey in Get-ChildItem -LiteralPath $hidRootAll -ErrorAction SilentlyContinue) {
        $vidPidName = $vidPidKey.PSChildName
        if ($vidPidName -notmatch '(?i)VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') { continue }
        $vid = $Matches[1].ToUpperInvariant()
        $pid = $Matches[2].ToUpperInvariant()
        if ($vid -ne '054C' -and $vid -ne '045E') { continue }

        foreach ($instKey in Get-ChildItem -LiteralPath $vidPidKey.PSPath -ErrorAction SilentlyContinue) {
            $fullId = ('HID\' + $vidPidName + '\' + $instKey.PSChildName)
            $fname = Read-EnumFriendlyName -InstanceId $fullId
            if (-not (Test-IsControllerHidInstance -InstanceId $fullId -FriendlyName $fname)) { continue }

            $cid = Read-EnumContainerId -InstanceId $fullId
            if ($cid) {
                $cu = $cid.ToUpperInvariant()
                if (-not $hidByContainer.ContainsKey($cu)) { $hidByContainer[$cu] = $fullId }
                elseif ($fullId -match '(?i)MI_03') { $hidByContainer[$cu] = $fullId }
            }
            $vk = ($vid + ':' + $pid).ToUpperInvariant()
            if (-not $hidByVidPid.ContainsKey($vk)) { $hidByVidPid[$vk] = @() }
            $hidByVidPid[$vk] = @($hidByVidPid[$vk]) + @($fullId)
        }
    }
}

$cards = New-Object System.Collections.Generic.List[object]
$now = (Get-Date).ToString('o')

function Add-ControllerCard {
    param(
        [string]$UsbParent,
        [string]$HidInst,
        [string]$Vid,
        [string]$Pid,
        [string]$ChildName,
        [bool]$ParentResolved
    )
    $cap = Get-ControllerTypeAndCapability -Vid $Vid -DevicePid $Pid -NameBlob (($UsbParent + ' ' + $HidInst + ' ' + $ChildName).Trim())
    $maxHz = [int]$cap.MaxRateHz
    if ($maxHz -le 0) { $maxHz = 1000 }

    $displayName = 'Périphérique USB composite'
    if ([string]$cap.Type -eq 'DualSense') { $displayName = 'PS5 DualSense' }
    elseif ([string]$cap.Type -eq 'PS4') { $displayName = 'PS4 DualShock' }
    elseif ($ChildName) { $displayName = $ChildName }

    $cardKey = if ($UsbParent) { $UsbParent.ToUpperInvariant() } else { $HidInst.ToUpperInvariant() }
    if ($script:dedupeKeys.ContainsKey($cardKey)) { return }
    $script:dedupeKeys[$cardKey] = $true

    $card = [PSCustomObject]@{
        DisplayName           = $displayName
        ChildName             = $ChildName
        Name                  = $displayName
        FriendlyName          = $displayName
        DeviceInstanceId      = $HidInst
        InstanceId            = $HidInst
        DeviceId              = $HidInst
        UsbParentDeviceId     = $UsbParent
        UsbCompositeParentId  = $UsbParent
        TargetHidusbfDeviceId = $UsbParent
        Vid                   = $Vid
        Pid                   = $Pid
        Type                  = [string]$cap.Type
        Badge                 = [string]$cap.Badge
        MaxRateHz             = $maxHz
        CurrentRateHz         = 0
        ConfiguredRate        = 0
        HasFilter             = $false
        Present               = $true
        ParentResolved        = $ParentResolved
        LastKnownRateHz       = 0
        LastSeen              = $now
        CardId                = if ($UsbParent) { $UsbParent } else { $HidInst }
    }
    $cards.Add($card) | Out-Null
    Write-DetectLog ("[DEVICE-DETECT-FAST] " + $card.Badge + " vid=" + $Vid + " pid=" + $Pid + " parent=" + $UsbParent + " hid=" + $HidInst) $LogPath
}

foreach ($pk in ($usbParents.Keys | Sort-Object)) {
    $u = $usbParents[$pk]
    $usbParent = [string]$u.InstanceId
    $vid = [string]$u.Vid
    $pid = [string]$u.Pid
    $hidInst = Get-HidInstanceForParent -UsbParentId $usbParent -Vid $vid -Pid $pid -HidByContainer $hidByContainer -HidByVidPid $hidByVidPid
    if (-not $hidInst) { $hidInst = $usbParent }
    $childName = Read-EnumFriendlyName -InstanceId $hidInst
    Add-ControllerCard -UsbParent $usbParent -HidInst $hidInst -Vid $vid -Pid $pid -ChildName $childName -ParentResolved $true
}

foreach ($vk in ($hidByVidPid.Keys | Sort-Object)) {
    $hidList = @($hidByVidPid[$vk])
    foreach ($hidInst in $hidList) {
        if ($hidInst -notmatch '(?i)MI_03' -and $hidInst -notmatch '(?i)game|controller|wireless|dual') {
            $fn = Read-EnumFriendlyName -InstanceId $hidInst
            if (-not (Test-IsControllerNameBlob ($hidInst + ' ' + $fn))) { continue }
        }
        $vp = Get-VidPidFromInstanceId $hidInst
        $vid = $vp.Vid
        $pid = $vp.Pid
        $cid = Read-EnumContainerId -InstanceId $hidInst
        $usbParent = ''
        if ($cid) {
            $cu = $cid.ToUpperInvariant()
            if ($containerToUsbParent.ContainsKey($cu)) {
                $usbParent = [string]$containerToUsbParent[$cu]
            }
        }
        if ($usbParent) {
            $parentKey = $usbParent.ToUpperInvariant()
            if ($script:dedupeKeys.ContainsKey($parentKey)) { continue }
        }
        $childName = Read-EnumFriendlyName -InstanceId $hidInst
        Add-ControllerCard -UsbParent $usbParent -HidInst $hidInst -Vid $vid -Pid $pid -ChildName $childName -ParentResolved ([bool]$usbParent)
    }
}

if (-not $cards.Count -and (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
    Write-DetectLog '[DEVICE] Fast scan registry empty — trying Get-PnpDevice' $LogPath
    foreach ($pd in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
        $instId = [string]$pd.InstanceId
        if (-not $instId -or $instId -notmatch '(?i)VID_(054C|045E)') { continue }
        $fname = [string]$pd.FriendlyName
        if (-not (Test-IsControllerHidInstance -InstanceId $instId -FriendlyName $fname)) { continue }
        $vp = Get-VidPidFromInstanceId $instId
        $usbParent = ''
        if ($instId -match '(?i)^USB\\' -and $instId -notmatch '(?i)&MI_\d+') {
            $usbParent = $instId
        } else {
            try {
                $target = Resolve-HidusbfCompositeTarget -DeviceInstanceId $instId -Vid $vp.Vid -DevicePid $vp.Pid -LogFile $LogPath
                if ($target) { $usbParent = [string]$target.TargetHidusbfDeviceId }
            } catch {}
        }
        Add-ControllerCard -UsbParent $usbParent -HidInst $instId -Vid $vp.Vid -Pid $vp.Pid -ChildName $fname -ParentResolved ([bool]$usbParent)
    }
}

$list = @($cards)
if (-not $list.Count) {
    $json = '[]'
} elseif ($list.Count -eq 1) {
    $json = '[' + (($list[0] | ConvertTo-Json -Depth 6 -Compress)) + ']'
} else {
    $json = $list | ConvertTo-Json -Depth 6 -Compress:$false
}

Write-JsonFile -Path $FastOutputPath -Json $json
Write-JsonFile -Path $OutputPath -Json $json

if ($list.Count -gt 0) {
    Write-JsonFile -Path $CachePath -Json $json
}

Write-DetectLog ('[DEVICE] Fast scan result count=' + $list.Count) $LogPath
exit 0
