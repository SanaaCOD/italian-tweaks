#Requires -Version 5.1
<#
.SYNOPSIS
  Merge, dedupe, and filter controller lists — only PnP-present devices in output.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$CachePath = '',
    [string]$LinkPath = '',
    [string]$PresentPath = '',
    [string]$DetectedPath = '',
    [string]$OutputPath = '',
    [string]$FinalPath = ''
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

function Read-DeviceJson([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
        if (-not $raw.Trim()) { return @() }
        $parsed = $raw | ConvertFrom-Json
        if (-not $parsed) { return @() }
        if ($parsed -is [System.Array]) { return @($parsed) }
        return @($parsed)
    } catch { return @() }
}

function Get-MergeKey {
    param($Dev)
    $usb = (Normalize-DeviceInstanceId ([string]$Dev.UsbParentDeviceId)).ToUpperInvariant()
    if ($usb) { return ('P:' + $usb) }
    $hid = (Normalize-DeviceInstanceId ([string]$Dev.DeviceInstanceId)).ToUpperInvariant()
    if (-not $hid) { $hid = (Normalize-DeviceInstanceId ([string]$Dev.InstanceId)).ToUpperInvariant() }
    $vid = ([string]$Dev.Vid).ToUpperInvariant()
    $pid = ([string]$Dev.Pid).ToUpperInvariant()
    if ($vid -eq '054C' -and $pid -eq '0CE6') { return 'T:PS5' }
    if ($vid -eq '054C' -and $pid -match '^(05C4|09CC|0BA0|0C5E)$') { return 'T:PS4:' + $hid }
    if ($vid -and $pid -and $hid) { return ('V:' + $vid + ':' + $pid + ':' + $hid) }
    if ($hid) { return ('H:' + $hid) }
    return ('X:' + [string]$Dev.DisplayName)
}

function To-CardObject($Dev, [bool]$FromCache) {
    $hid = Normalize-DeviceInstanceId ([string]$Dev.DeviceInstanceId)
    if (-not $hid) { $hid = Normalize-DeviceInstanceId ([string]$Dev.InstanceId) }
    $usb = Normalize-DeviceInstanceId ([string]$Dev.UsbParentDeviceId)
    $vp = Get-VidPidFromInstanceId $(if ($usb) { $usb } else { $hid })
    $vid = if ($Dev.Vid) { [string]$Dev.Vid.ToUpper() } else { $vp.Vid }
    $pid = if ($Dev.Pid) { [string]$Dev.Pid.ToUpper() } else { $vp.Pid }
    $cap = Get-ControllerTypeAndCapability -Vid $vid -DevicePid $pid -NameBlob ($usb + ' ' + $hid + ' ' + $Dev.DisplayName)
    $maxHz = [int]$Dev.MaxRateHz
    if ($maxHz -le 0) { $maxHz = [int]$cap.MaxRateHz }
    if ($maxHz -le 0) { $maxHz = 1000 }
    $dn = [string]$Dev.DisplayName
    if (-not $dn) {
        $dn = if ($cap.Type -eq 'DualSense') { 'PS5 DualSense' }
        elseif ($cap.Type -eq 'PS4') { 'PS4 DualShock' }
        else { 'Controller' }
    }
    return [PSCustomObject]@{
        DisplayName = $dn
        ChildName = [string]$Dev.ChildName
        Name = $dn
        FriendlyName = $dn
        DeviceInstanceId = $hid
        InstanceId = $hid
        UsbParentDeviceId = $usb
        Vid = $vid
        Pid = $pid
        Type = if ($Dev.Type) { [string]$Dev.Type } else { [string]$cap.Type }
        Badge = if ($Dev.Badge) { [string]$Dev.Badge } else { [string]$cap.Badge }
        MaxRateHz = $maxHz
        CurrentRateHz = 0
        ConfiguredRate = 0
        Present = $false
        ParentResolved = [bool]$usb
        FromCache = $FromCache
        CardId = if ($usb) { $usb } elseif ($hid) { $hid } else { (Get-MergeKey $Dev) }
        LastSeen = (Get-Date).ToString('o')
    }
}

function Add-ToMerge {
    param($Merged, $Dev, [int]$Score, [bool]$FromCache)
    $card = To-CardObject $Dev $FromCache
    $key = Get-MergeKey $card
    if (-not $Merged.ContainsKey($key)) {
        $Merged[$key] = [ordered]@{ Card = $card; Score = $Score }
    } elseif ($Score -gt $Merged[$key].Score) {
        $Merged[$key] = [ordered]@{ Card = $card; Score = $Score }
    } else {
        Write-Log ("[DEVICE] Removed duplicate controller=" + $key) $LogPath
    }
}

$app = Resolve-App $AppRoot
if (-not $app) { $app = Resolve-UnrealAppRoot '' }
if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }
if (-not $CachePath) { $CachePath = Join-Path $app 'logs\controller-devices-cache.json' }
if (-not $PresentPath) { $PresentPath = Join-Path $app 'logs\controller-devices-present.json' }
if (-not $OutputPath) { $OutputPath = $PresentPath }
if (-not $FinalPath) { $FinalPath = Join-Path $app 'logs\controller-devices-final.json' }

$inputCount = 0
$merged = @{}
$trustedPresentIds = @{}

foreach ($dev in (Read-DeviceJson $PresentPath)) {
    $inputCount++
    Add-ToMerge $merged $dev 1000 $false
    $hid = (Normalize-DeviceInstanceId ([string]$dev.DeviceInstanceId)).ToUpperInvariant()
    $usb = (Normalize-DeviceInstanceId ([string]$dev.UsbParentDeviceId)).ToUpperInvariant()
    if ($hid) { $trustedPresentIds[$hid] = $true }
    if ($usb) { $trustedPresentIds[$usb] = $true }
}
foreach ($dev in (Read-DeviceJson $LinkPath)) { $inputCount++; Add-ToMerge $merged $dev 600 $false }
foreach ($dev in (Read-DeviceJson $DetectedPath)) { $inputCount++; Add-ToMerge $merged $dev 400 $false }
foreach ($dev in (Read-DeviceJson $CachePath)) { $inputCount++; Add-ToMerge $merged $dev 50 $true }

Write-Log ("[DEVICE] Merge controllers input count=" + $inputCount) $LogPath

$presentList = New-Object System.Collections.Generic.List[object]
foreach ($entry in $merged.Values) {
    $card = $entry.Card
    $score = [int]$entry.Score
    $hidU = (Normalize-DeviceInstanceId ([string]$card.DeviceInstanceId)).ToUpperInvariant()
    $usbU = (Normalize-DeviceInstanceId ([string]$card.UsbParentDeviceId)).ToUpperInvariant()
    $trusted = ($score -ge 1000) -or (
        ($hidU -and $trustedPresentIds.ContainsKey($hidU)) -or
        ($usbU -and $trustedPresentIds.ContainsKey($usbU))
    )
    if ($trusted) {
        $pr = [ordered]@{ Present = $true; Method = 'PnP present scan' }
    } else {
        $pr = Test-ControllerDevicePresent -DeviceInstanceId $card.DeviceInstanceId `
            -UsbParentDeviceId $card.UsbParentDeviceId -Vid $card.Vid -DevicePid $card.Pid
    }
    if (-not $pr.Present) {
        Write-Log ("[DEVICE] Removed stale cache controller=" + (Get-MergeKey $card)) $LogPath
        continue
    }
    $card.Present = $true
    $card.FromCache = $false
    $presentList.Add($card) | Out-Null
}

$out = @($presentList)
Write-Log ("[DEVICE] Merge controllers output count=" + $out.Count) $LogPath

if (-not $out.Count) { $json = '[]' }
elseif ($out.Count -eq 1) { $json = '[' + (($out[0] | ConvertTo-Json -Depth 6 -Compress)) + ']' }
else { $json = $out | ConvertTo-Json -Depth 6 -Compress:$false }

foreach ($path in @($OutputPath, $FinalPath)) {
    if (-not $path) { continue }
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

if ($out.Count -gt 0) {
    [System.IO.File]::WriteAllText($CachePath, $json, [System.Text.UTF8Encoding]::new($false))
}

exit 0
