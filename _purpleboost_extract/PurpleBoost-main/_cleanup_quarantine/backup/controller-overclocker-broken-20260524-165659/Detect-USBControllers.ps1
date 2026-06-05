#Requires -Version 5.1
<#
.SYNOPSIS
  Scans USB/HID game controllers for Controller Overclocker (Unreal).
  Groups by USB composite parent; outputs JSON for multi-card UI.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

function Resolve-UnrealAppRoot([string]$root) {
    if ($root -and (Test-Path -LiteralPath $root)) { return (Resolve-Path -LiteralPath $root).Path }
    $here = $PSScriptRoot
    if ($here) {
        $c = Split-Path -Parent (Split-Path -Parent $here)
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'Unreal.hta'))) { return $c }
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}

function Write-DeviceLog([string]$line, [string]$logFile) {
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
    return ($text -match '(?i)keyboard|clavier|mouse|souris|touchpad|trackpad|track\s*point|digitizer|pen\s|stylus|consumer\s+control|vendor-defined\s+device|system\s+controller|bluetooth\s+le\s+generic|hid-compliant\s+vendor|sensor|biometric|fingerprint|camera|webcam|headset|receiver|dongle\s+for\s+wireless|wireless\s+radio')
}

function Test-IsGameControllerName([string]$text) {
    if (-not $text) { return $false }
    if (Test-IsInputDeviceExcluded $text) { return $false }
    return ($text -match '(?i)DualSense|DualShock|DUALSHOCK|Wireless\s+Controller|PS5|PS4|Xbox|XInput|Controller|Game\s+Controller|HID-compliant\s+game\s+controller|Contrôleur de jeu|Contr.leur de jeu|Périphérique\s+de\s+jeu\s+HID|Périphérique\s+d.entrée\s+USB|Périphérique\s+USB\s+composite|manette|joystick|gamepad|Scuf')
}

function Test-IsControllerCandidate([object]$dev) {
    $name = [string]$dev.Name
    $caption = [string]$dev.Caption
    $desc = [string]$dev.Description
    $class = [string]$dev.PNPClass
    $deviceId = [string]$dev.DeviceID
    $blob = ($name + ' ' + $caption + ' ' + $desc + ' ' + $deviceId).Trim()

    if (-not $deviceId -or $deviceId -notmatch 'VID_[0-9A-Fa-f]{4}') { return $false }
    if (Test-IsInputDeviceExcluded $blob) { return $false }

    if ($class -match '^(HIDClass|USB|Media|System)$' -and (Test-IsGameControllerName $blob)) { return $true }
    if ($class -eq 'HIDClass' -and $blob -match '(?i)game|controller|joystick|xinput|dualsense|dualshock|xbox|manette|wireless') { return $true }

    $vp = Get-VidPidFromInstanceId $deviceId
    if ($vp.Vid -eq '054C' -and $vp.Pid) { return $true }
    if ($vp.Vid -eq '045E' -and $blob -match '(?i)controller|xbox|gamepad|xinput') { return $true }
    if (Test-IsGameControllerName $blob) { return $true }
    return $false
}

function Get-MemberDisplayRank([object]$entry) {
    $score = 0
    $n = [string]$entry.Name
    $id = [string]$entry.InstanceId
    if ($n -match '(?i)game controller|contrôleur de jeu|dualsense|wireless controller|dualshock|xbox|gamepad|manette') { $score += 60 }
    if ($id -match '(?i)^HID\\') { $score += 30 }
    if ($id -match '(?i)^USB\\' -and $id -match '(?i)MI_\d+') { $score += 25 }
    if ($n -match '(?i)composite|périphérique usb composite') { $score += 50 }
    if ($n -match '(?i)périphérique d.entrée usb|usb input device') { $score += 20 }
    return $score
}

function New-RawControllerMember([object]$dev) {
    $deviceId = [string]$dev.DeviceID
    $name = [string]$dev.Name
    if (-not $name) { $name = [string]$dev.Caption }
    $vp = Get-VidPidFromInstanceId $deviceId
    return [PSCustomObject]@{
        Name             = $name
        FriendlyName     = if ($dev.Caption) { [string]$dev.Caption } else { $name }
        InstanceId       = $deviceId
        Vid              = $vp.Vid
        Pid              = $vp.Pid
        UsbParentDeviceId = ''
        ParentResolved   = $false
        ContainerId      = ''
    }
}

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) { $app = Resolve-UnrealAppRoot '' }

if (-not $LogPath) {
    $LogPath = if ($app) { Join-Path $app 'logs\controller-overclocker.log' } else { '' }
}
if (-not $OutputPath) {
    $OutputPath = if ($app) { Join-Path $app 'logs\controller-overclocker-detect.json' } else { '' }
}
$detectDetailPath = if ($app) { Join-Path $app 'logs\controller-devices-detected.json' } else { '' }

Write-DeviceLog '[DEVICE] Scan started (multi-controller)' $LogPath

$rawMembers = New-Object System.Collections.Generic.List[object]
$pnpEntities = @()

try {
    $pnpEntities = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)
} catch {
    Write-DeviceLog ('[DEVICE] Win32_PnPEntity error: ' + $_.Exception.Message) $LogPath
}

foreach ($dev in $pnpEntities) {
    if (Test-IsControllerCandidate $dev) {
        $rawMembers.Add((New-RawControllerMember $dev)) | Out-Null
    }
}

try {
    $signed = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop
    $seen = @{}
    foreach ($m in $rawMembers) { $seen[[string]$m.InstanceId] = $true }
    foreach ($drv in $signed) {
        $devId = [string]$drv.DeviceID
        if (-not $devId -or $seen.ContainsKey($devId)) { continue }
        $name = [string]$drv.DeviceName
        if (-not $name) { $name = [string]$drv.FriendlyName }
        $fake = [PSCustomObject]@{
            Name        = $name
            Caption     = $name
            Description = [string]$drv.DriverVersion
            PNPClass    = 'HIDClass'
            DeviceID    = $devId
        }
        if (Test-IsControllerCandidate $fake) {
            $rawMembers.Add((New-RawControllerMember $fake)) | Out-Null
            $seen[$devId] = $true
        }
    }
} catch {
    Write-DeviceLog ('[DEVICE] Win32_PnPSignedDriver warn: ' + $_.Exception.Message) $LogPath
}

try {
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        foreach ($pd in (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
            $devId = [string]$pd.InstanceId
            if (-not $devId) { continue }
            $already = $false
            foreach ($m in $rawMembers) {
                if ([string]$m.InstanceId -ieq $devId) { $already = $true; break }
            }
            if ($already) { continue }
            $fake = [PSCustomObject]@{
                Name        = [string]$pd.FriendlyName
                Caption     = [string]$pd.FriendlyName
                Description = [string]$pd.Class
                PNPClass    = [string]$pd.Class
                DeviceID    = $devId
            }
            if (Test-IsControllerCandidate $fake) {
                $rawMembers.Add((New-RawControllerMember $fake)) | Out-Null
            }
        }
    }
} catch {
    Write-DeviceLog ('[DEVICE] Get-PnpDevice warn: ' + $_.Exception.Message) $LogPath
}

foreach ($member in $rawMembers) {
    $reg = Get-EnumDeviceRegistryInfo -InstanceId ([string]$member.InstanceId)
    $member.ContainerId = [string]$reg.ContainerId
    $usbParent = ''
    try {
        $target = Resolve-HidusbfCompositeTarget `
            -DeviceInstanceId ([string]$member.InstanceId) `
            -Vid ([string]$member.Vid) `
            -DevicePid ([string]$member.Pid) `
            -LogFile $LogPath
        $usbParent = [string]$target.TargetHidusbfDeviceId
    } catch {
        Write-DeviceLog ('[DEVICE-DETECT] Parent resolve error: ' + $_.Exception.Message) $LogPath
    }
    $member.UsbParentDeviceId = $usbParent
    $member.ParentResolved = [bool]$usbParent
}

$groups = @{}
foreach ($member in $rawMembers) {
    $parentId = [string]$member.UsbParentDeviceId
    $containerId = [string]$member.ContainerId
    if ($parentId) {
        $key = ('USB:' + $parentId).ToUpperInvariant()
    } elseif ($containerId) {
        $key = ('CID:' + $containerId).ToUpperInvariant()
    } else {
        $key = ('RAW:' + [string]$member.InstanceId).ToUpperInvariant()
    }
    if (-not $groups.ContainsKey($key)) {
        $groups[$key] = New-Object System.Collections.Generic.List[object]
    }
    $groups[$key].Add($member) | Out-Null
}

$cards = New-Object System.Collections.Generic.List[object]

foreach ($groupKey in ($groups.Keys | Sort-Object)) {
    $members = @($groups[$groupKey] | Sort-Object { Get-MemberDisplayRank $_ } -Descending)
    if (-not $members.Count) { continue }

    $best = $members[0]
    $usbParent = ''
    foreach ($m in $members) {
        if ([string]$m.UsbParentDeviceId) { $usbParent = [string]$m.UsbParentDeviceId; break }
    }
    if (-not $usbParent) {
        foreach ($m in $members) {
            try {
                $target = Resolve-HidusbfCompositeTarget `
                    -DeviceInstanceId ([string]$m.InstanceId) `
                    -Vid ([string]$m.Vid) `
                    -DevicePid ([string]$m.Pid) `
                    -LogFile $LogPath
                if ($target.TargetHidusbfDeviceId) {
                    $usbParent = [string]$target.TargetHidusbfDeviceId
                    break
                }
            } catch {}
        }
    }
    $parentVp = Get-VidPidFromInstanceId $(if ($usbParent) { $usbParent } else { [string]$best.InstanceId })
    $parentVid = [string]$parentVp.Vid
    $parentPid = [string]$parentVp.Pid
    if (-not $parentVid) { $parentVid = [string]$best.Vid }
    if (-not $parentPid) { $parentPid = [string]$best.Pid }

    $containerId = ''
    foreach ($m in $members) {
        if ([string]$m.ContainerId) { $containerId = [string]$m.ContainerId; break }
    }
  if (-not $containerId -and $usbParent) {
        $containerId = [string](Get-EnumDeviceRegistryInfo -InstanceId $usbParent).ContainerId
    }

    $childInfo = Get-ContainerControllerChildBlob -ContainerId $containerId
    $nameBlob = (($members | ForEach-Object { [string]$_.Name + ' ' + [string]$_.FriendlyName }) -join ' | ')
    $cap = Get-ControllerTypeAndCapability -Vid $parentVid -DevicePid $parentPid -NameBlob $nameBlob -ChildName ([string]$childInfo.ChildName)

    $displayName = 'Périphérique USB composite'
    foreach ($m in $members) {
        if ([string]$m.Name -match '(?i)composite|périphérique usb composite') {
            $displayName = [string]$m.Name
            break
        }
    }

    $preferredInstance = [string]$best.InstanceId
    foreach ($m in $members) {
        $mid = [string]$m.InstanceId
        if ($mid -match '(?i)^HID\\' -and $mid -match '(?i)MI_0[03]') {
            $preferredInstance = $mid
            break
        }
    }

    $currentRate = if ($usbParent) { Get-UsbParentPollingRate -UsbParentDeviceId $usbParent } else { 125 }
    $hasFilter = $currentRate -gt 125

    $maxHz = 1000
    if ($null -ne $cap.MaxRateHz) { $maxHz = [int]$cap.MaxRateHz }
    $card = [PSCustomObject]@{
        DisplayName           = $displayName
        ChildName             = if ($childInfo.ChildName) { [string]$childInfo.ChildName } else { [string]$best.Name }
        Name                  = $displayName
        FriendlyName          = $displayName
        DeviceInstanceId      = $preferredInstance
        InstanceId            = $preferredInstance
        DeviceId              = $preferredInstance
        UsbParentDeviceId     = $usbParent
        UsbCompositeParentId  = $usbParent
        TargetHidusbfDeviceId = $usbParent
        Vid                   = $parentVid
        Pid                   = $parentPid
        Type                  = [string]$cap.Type
        Badge                 = [string]$cap.Badge
        MaxRateHz             = $maxHz
        CurrentRateHz         = [int]$currentRate
        ConfiguredRate        = [int]$currentRate
        HasFilter             = [bool]$hasFilter
        Present               = $true
        ParentResolved        = [bool]$usbParent
        Status                = if ($currentRate -ge 8000) { 'Optimized8000' } elseif ($currentRate -ge 1000) { 'Optimized1000' } else { 'Default' }
        CardId                = if ($usbParent) { $usbParent } else { ($parentVid + ':' + $parentPid) }
    }

    Write-DeviceLog (
        '[DEVICE-DETECT] Controller found: badge=' + $card.Badge +
        ' vid=' + $card.Vid +
        ' pid=' + $card.Pid +
        ' max=' + $card.MaxRateHz +
        ' current=' + $card.CurrentRateHz +
        ' usbParent=' + $card.UsbParentDeviceId +
        ' Parent resolved=' + $card.ParentResolved.ToString().ToLowerInvariant()
    ) $LogPath

    $cards.Add($card) | Out-Null
}

$dedupCards = @{}
foreach ($c in $cards) {
    $dk = if ($c.UsbParentDeviceId) { $c.UsbParentDeviceId.ToUpperInvariant() } else { ($c.Vid + ':' + $c.Pid) }
    if (-not $dedupCards.ContainsKey($dk)) {
        $dedupCards[$dk] = $c
    }
}
$list = @($dedupCards.Values | Sort-Object Type, DisplayName)

if (-not $list.Count) {
    Write-DeviceLog '[DEVICE] No controller matched scan filters' $LogPath
}

if (-not $list.Count) {
    $json = '[]'
} elseif ($list.Count -eq 1) {
    $json = '[' + (($list[0] | ConvertTo-Json -Depth 6 -Compress)) + ']'
} else {
    $json = $list | ConvertTo-Json -Depth 6 -Compress:$false
}

foreach ($outFile in @($OutputPath, $detectDetailPath)) {
    if (-not $outFile) { continue }
    $outDir = Split-Path -Parent $outFile
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($outFile, $json, [System.Text.UTF8Encoding]::new($false))
    Write-DeviceLog ('[DEVICE] Wrote ' + $list.Count + ' card(s) to ' + $outFile) $LogPath
}

exit 0
