#Requires -Version 5.1
<#
.SYNOPSIS
  List actually-present game controllers via PnP (PresentOnly), not registry ghosts.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')
. (Join-Path $PSScriptRoot 'Controller-Presence-Common.ps1')

function Resolve-App([string]$root) {
    if ($root -and (Test-Path -LiteralPath $root)) { return (Resolve-Path -LiteralPath $root).Path }
    $here = $PSScriptRoot
    if ($here) {
        $c = Split-Path -Parent (Split-Path -Parent $here)
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'Unreal.hta'))) { return $c }
    }
    return ''
}

function Write-Log([string]$line, [string]$log) {
    if (-not $log) { return }
    $dir = Split-Path -Parent $log
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -LiteralPath $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $line) -Encoding UTF8
}

$app = Resolve-App $AppRoot
if (-not $app) { $app = Resolve-UnrealAppRoot '' }
if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }
if (-not $OutputPath) { $OutputPath = Join-Path $app 'logs\controller-devices-present.json' }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Log '[DEVICE] PnP present scan started' $LogPath

$presentPnP = @()
if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
    $presentPnP = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { Test-IsControllerPnpDevice $_ })
}

if (-not $presentPnP.Count) {
    try {
        $presentPnP = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object {
                [int]$_.ConfigManagerErrorCode -eq 0 -and
                (Normalize-DeviceInstanceId $_.PNPDeviceID) -match 'VID_054C|VID_045E|Controller|DualSense|Wireless'
            })
    } catch {}
}

$byParent = @{}
$hidGame = @{}
$now = (Get-Date).ToString('o')

foreach ($pd in $presentPnP) {
    $inst = Normalize-DeviceInstanceId $(if ($pd.InstanceId) { $pd.InstanceId } else { $pd.PNPDeviceID })
    if (-not $inst) { continue }
    $fname = [string]$pd.FriendlyName
    $vp = Get-VidPidFromInstanceId $inst

    if ($inst -match '(?i)^USB\\' -and $inst -notmatch '(?i)&MI_\d+') {
        $byParent[$inst.ToUpperInvariant()] = [ordered]@{
            UsbParent = $inst; Hid = ''; FriendlyName = $fname; Vid = $vp.Vid; Pid = $vp.Pid
        }
    } elseif ($inst -match '(?i)^HID\\') {
        $vk = ($vp.Vid + ':' + $vp.Pid).ToUpperInvariant()
        if (-not $hidGame.ContainsKey($vk)) { $hidGame[$vk] = @() }
        $hidGame[$vk] = @($hidGame[$vk]) + @([ordered]@{ Hid = $inst; FriendlyName = $fname; Vid = $vp.Vid; Pid = $vp.Pid })
    }
}

foreach ($pk in $byParent.Keys) {
    $p = $byParent[$pk]
    $vp = Get-VidPidFromInstanceId $p.UsbParent
    $vk = ($vp.Vid + ':' + $vp.Pid).ToUpperInvariant()
    $hidInst = ''
    if ($hidGame.ContainsKey($vk)) {
        foreach ($h in @($hidGame[$vk])) {
            if ($h.Hid -match '(?i)MI_03') { $hidInst = $h.Hid; break }
        }
        if (-not $hidInst) { $hidInst = [string]$hidGame[$vk][0].Hid }
    }
    if (-not $hidInst) { $hidInst = $p.UsbParent }
    $cap = Get-ControllerTypeAndCapability -Vid $vp.Vid -DevicePid $vp.Pid -NameBlob ($p.UsbParent + ' ' + $hidInst + ' ' + $p.FriendlyName)
    $byParent[$pk] = [PSCustomObject]@{
        DisplayName = if ($cap.Type -eq 'DualSense') { 'PS5 DualSense' } elseif ($cap.Type -eq 'PS4') { 'PS4 DualShock' } else { $p.FriendlyName }
        ChildName = $p.FriendlyName
        DeviceInstanceId = $hidInst
        InstanceId = $hidInst
        UsbParentDeviceId = $p.UsbParent
        Vid = $vp.Vid
        Pid = $vp.Pid
        Type = [string]$cap.Type
        Badge = [string]$cap.Badge
        MaxRateHz = [int]$cap.MaxRateHz
        Present = $true
        ParentResolved = $true
        FromCache = $false
        CardId = $p.UsbParent
        LastSeen = $now
    }
}

# HID-only present (no composite row yet) — resolve parent if possible
foreach ($vk in $hidGame.Keys) {
    foreach ($h in @($hidGame[$vk])) {
        $hidInst = $h.Hid
        if (-not $hidInst) { continue }
        $already = $false
        foreach ($card in $byParent.Values) {
            if (([string]$card.DeviceInstanceId).ToUpperInvariant() -eq $hidInst.ToUpperInvariant()) { $already = $true; break }
            if (([string]$card.UsbParentDeviceId).ToUpperInvariant() -eq $hidInst.ToUpperInvariant()) { $already = $true; break }
        }
        if ($already) { continue }
        if ($hidInst -notmatch '(?i)MI_03' -and $hidInst -notmatch '(?i)game|wireless|dual') { continue }

        $usbParent = ''
        try {
            $target = Resolve-HidusbfCompositeTarget -DeviceInstanceId $hidInst -Vid $h.Vid -DevicePid $h.Pid -LogFile $LogPath
            if ($target) { $usbParent = [string]$target.TargetHidusbfDeviceId }
        } catch {}

        $parentKey = if ($usbParent) { $usbParent.ToUpperInvariant() } else { ('HIDONLY:' + $hidInst.ToUpperInvariant()) }
        if ($byParent.ContainsKey($parentKey)) { continue }

        $cap = Get-ControllerTypeAndCapability -Vid $h.Vid -DevicePid $h.Pid -NameBlob ($hidInst + ' ' + $h.FriendlyName)
        $byParent[$parentKey] = [PSCustomObject]@{
            DisplayName = if ($cap.Type -eq 'DualSense') { 'PS5 DualSense' } elseif ($cap.Type -eq 'PS4') { 'PS4 DualShock' } else { $h.FriendlyName }
            ChildName = $h.FriendlyName
            DeviceInstanceId = $hidInst
            InstanceId = $hidInst
            UsbParentDeviceId = $usbParent
            Vid = $h.Vid
            Pid = $h.Pid
            Type = [string]$cap.Type
            Badge = [string]$cap.Badge
            MaxRateHz = [int]$cap.MaxRateHz
            Present = $true
            ParentResolved = [bool]$usbParent
            FromCache = $false
            CardId = if ($usbParent) { $usbParent } else { $hidInst }
            LastSeen = $now
        }
    }
}

$list = @($byParent.Values | Sort-Object { [string]$_.CardId })
if (-not $list.Count) { $json = '[]' }
elseif ($list.Count -eq 1) { $json = '[' + (($list[0] | ConvertTo-Json -Depth 6 -Compress)) + ']' }
else { $json = $list | ConvertTo-Json -Depth 6 -Compress:$false }

$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))

$sw.Stop()
Write-Log ("[DEVICE] PnP present scan count=" + $list.Count + " ms=" + $sw.ElapsedMilliseconds) $LogPath
exit 0
