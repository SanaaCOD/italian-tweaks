#Requires -Version 5.1
<#
  Liste les manettes réellement branchées (PnP PresentOnly uniquement — jamais registre/cache comme preuve).
#>
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
. (Join-Path $PSScriptRoot '..\lib\devices\Controller-Hidusbf-Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\devices\Controller-Presence-Common.ps1')

function Write-CtrlLog {
    param([string]$LogDir, [string]$Line)
    if (-not $LogDir) { return }
    Write-ItalianTweaksLog -LogDir $LogDir -Name 'controllers' -Line $Line
}

function Get-HidusbfToolStatus {
    param([string]$Root)
    $dir = Join-Path $Root 'tools\hidusbf'
    $infU = Join-Path $dir 'HIDUSBFU.INF'
    $auto = Join-Path $Root 'scripts\lib\devices\Hidusbf-Setup-Automation.ps1'
    $ok = (Test-Path -LiteralPath $infU) -and (Test-Path -LiteralPath $auto)
    return @{
        available = $ok
        path      = $dir
        message   = if ($ok) { 'HIDUSBF local OK' } else { 'Outil HIDUSBF manquant (tools/hidusbf)' }
    }
}

function Classify-Controller {
    param(
        [string]$Vid,
        [string]$DevicePid,
        [string]$NameBlob,
        [string]$LibType
    )
    $vidU = ($Vid + '').ToUpperInvariant().Replace('0X', '')
    $pidU = ($DevicePid + '').ToUpperInvariant().Replace('0X', '')
    $blob = ($NameBlob + ' ' + $LibType).Trim()

    # PS5 / DualSense — PID_054C:0CE6 (+ variantes officielles)
    if ($vidU -eq '054C' -and $pidU -match '^(0CE6|0DF2|0E5F)$') {
        return @{ type = 'PS5'; maxHz = 8000; displayName = 'PS5 DualSense' }
    }
    if ($blob -match '(?i)dualsense|\bps5\b') {
        return @{ type = 'PS5'; maxHz = 8000; displayName = 'PS5 DualSense' }
    }

    # PS4 / DualShock / Wireless Controller (Sony, pas DualSense)
    if ($blob -match '(?i)dualshock|\bps4\b') {
        return @{ type = 'PS4'; maxHz = 1000; displayName = 'PS4 DualShock' }
    }
    if ($vidU -eq '054C' -and $pidU -match '^(05C4|09CC|0BA0|0268|0C5E|054C)$') {
        return @{ type = 'PS4'; maxHz = 1000; displayName = 'PS4 DualShock' }
    }
    if ($vidU -eq '054C' -and $blob -match '(?i)wireless\s+controller' -and $blob -notmatch '(?i)dualsense') {
        return @{ type = 'PS4'; maxHz = 1000; displayName = 'PS4 Wireless Controller' }
    }

    # Xbox
    if ($vidU -eq '045E' -or $blob -match '(?i)xbox|xinput') {
        return @{ type = 'Xbox'; maxHz = 1000; displayName = 'Xbox Controller' }
    }

    # HID inconnu
    return @{ type = 'Generic'; maxHz = 1000; displayName = '' }
}

function Test-HidusbfTargetReliable {
    param(
        [string]$HidusbfTarget,
        [string]$UsbParent,
        [bool]$ParentResolved
    )
    if ($ParentResolved -and $UsbParent -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}\\') {
        return $true
    }
    if ($HidusbfTarget -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}\\' -and $HidusbfTarget -notmatch '(?i)&MI_') {
        return $true
    }
    return $false
}

function Get-PollingStatusUi {
    param([int]$CurrentHz, [int]$MaxHz, [bool]$HidusbfOk)
    if ($CurrentHz -le 0) { return @{ label = 'Inconnu'; badge = 'Action requise'; badgeType = 'warn' } }
    if ($MaxHz -ge 8000 -and $CurrentHz -ge 8000) { return @{ label = "$CurrentHz Hz"; badge = 'Optimisé'; badgeType = 'ok' } }
    if ($CurrentHz -ge $MaxHz -and $MaxHz -ge 1000) { return @{ label = "$CurrentHz Hz"; badge = 'Optimisé'; badgeType = 'ok' } }
    if ($CurrentHz -eq 125) {
        return @{ label = 'Default / 125 Hz'; badge = if ($HidusbfOk) { 'Action requise' } else { 'Non compatible' }; badgeType = 'warn' }
    }
    return @{ label = "$CurrentHz Hz"; badge = 'Action requise'; badgeType = 'warn' }
}

function Convert-RawController {
    param(
        [object]$Raw,
        [string]$Root,
        [string]$LogDir,
        [bool]$HidusbfOk
    )
    $hid = Normalize-DeviceInstanceId ([string]$Raw.DeviceInstanceId)
    $usb = Normalize-DeviceInstanceId ([string]$Raw.UsbParentDeviceId)
    if (-not $usb) { $usb = Normalize-DeviceInstanceId ([string]$Raw.CardId) }

    $presence = Test-ControllerDevicePresent -DeviceInstanceId $hid -UsbParentDeviceId $usb -Vid $Raw.Vid -DevicePid $Raw.Pid
    if (-not $presence.Present) {
        Write-CtrlLog $LogDir ("FILTERED not present id=" + $hid + " method=" + $presence.Method)
        return $null
    }

    $hidusbfTarget = $usb
    if (-not $hidusbfTarget) {
        try {
            $t = Resolve-HidusbfCompositeTarget -DeviceInstanceId $hid -Vid $Raw.Vid -DevicePid $Raw.Pid -LogFile (Join-Path $Root 'logs\controller-overclocker.log')
            if ($t -and $t.TargetHidusbfDeviceId) { $hidusbfTarget = [string]$t.TargetHidusbfDeviceId }
        } catch {}
    }
    if (-not $hidusbfTarget) { $hidusbfTarget = $hid }

    Write-CtrlLog $LogDir ("HIDUSBF_TARGET id=$hid parent=$usb target=$hidusbfTarget")

    $nameBlob = ([string]$Raw.DisplayName + ' ' + [string]$Raw.ChildName + ' ' + $hid + ' ' + $usb).Trim()
    $class = Classify-Controller -Vid $Raw.Vid -DevicePid $Raw.Pid -NameBlob $nameBlob -LibType ([string]$Raw.Type)
    $ctrlType = [string]$class['type']
    $maxHz = [int]$class['maxHz']
    $ctrlName = if ($class['displayName']) { [string]$class['displayName'] } else { [string]$Raw.DisplayName }

    $currentHz = 125
    if ($HidusbfOk -and $hidusbfTarget) {
        $currentHz = [int](Get-UsbParentPollingRate -UsbParentDeviceId $hidusbfTarget)
    }

    $targetReliable = Test-HidusbfTargetReliable -HidusbfTarget $hidusbfTarget -UsbParent $usb -ParentResolved ([bool]$Raw.ParentResolved)
    $canBoost = $false
    $boostButton = 'none'
    if ($HidusbfOk -and $targetReliable -and ($currentHz -lt $maxHz)) {
        if ($ctrlType -eq 'PS5') {
            $canBoost = $true
            $boostButton = '8000'
        }
        elseif ($ctrlType -in @('PS4', 'Xbox')) {
            $canBoost = $true
            $boostButton = '1000'
        }
        elseif ($ctrlType -eq 'Generic') {
            $canBoost = $true
            $boostButton = '1000'
        }
    }
    elseif ($ctrlType -eq 'Generic' -and -not $targetReliable) {
        Write-CtrlLog $LogDir ("GENERIC_NO_BOOST unreliable target=" + $hidusbfTarget)
    }

    $targetHz = if ($boostButton -eq '8000') { 8000 } elseif ($boostButton -eq '1000') { 1000 } else { $maxHz }

    $pollUi = Get-PollingStatusUi -CurrentHz $currentHz -MaxHz $maxHz -HidusbfOk $HidusbfOk
    $stableId = if ($usb) { $usb.ToUpperInvariant() } else { $hid.ToUpperInvariant() }

    $recommended = if (-not $HidusbfOk) { 'install_hidusbf' }
    elseif ($boostButton -eq 'none') { 'none' }
    elseif ($boostButton -eq '8000') { 'boost8000' }
    else { 'boost1000' }

    return [ordered]@{
        id                 = $stableId
        name               = $ctrlName
        type               = $ctrlType
        vendorId           = [string]$Raw.Vid
        productId          = [string]$Raw.Pid
        instanceId         = $hid
        parentInstanceId   = $usb
        devicePath         = $hid
        present            = $true
        currentPollingRate = $currentHz
        targetPollingRate  = $targetHz
        maxPollingRate     = $maxHz
        canBoost           = $canBoost
        boostButton        = $boostButton
        hidusbfTargetReliable = $targetReliable
        recommendedAction  = $recommended
        pollingLabel       = $pollUi.label
        statusBadge        = $pollUi.badge
        statusBadgeType    = $pollUi.badgeType
        hidusbfTargetId    = $hidusbfTarget
        presenceMethod     = [string]$presence.Method
        fromCache          = $false
    }
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
if (-not $LogDir) { $LogDir = Join-Path $root 'logs' }

Write-CtrlLog $LogDir 'SCAN_START source=PnPPresentOnly registry_as_presence=false cache_as_presence=false'

$hidusbf = Get-HidusbfToolStatus -Root $root
Write-CtrlLog $LogDir ("HIDUSBF_TOOL available=" + $hidusbf.available + " " + $hidusbf.message)

$libScript = Join-Path $root 'scripts\lib\devices\Get-ControllerPresentDevices.ps1'
$outFile = Join-Path $LogDir 'controller-devices-present.json'
$logFile = Join-Path $LogDir 'controller-overclocker.log'

if (-not (Test-Path -LiteralPath $libScript)) {
    Write-CtrlLog $LogDir 'ERROR lib Get-ControllerPresentDevices.ps1 missing'
    Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'GetControllers' -Message '0 manette(s) détectée(s)' -Data @{
        controllers = @()
        hidusbf       = $hidusbf
        scanMs        = $sw.ElapsedMilliseconds
    }
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
    -File $libScript -AppRoot $root -LogPath $logFile -OutputPath $outFile | Out-Null

$rawList = @()
if (Test-Path -LiteralPath $outFile) {
    try {
        $parsed = Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($parsed -is [Array]) { $rawList = @($parsed) }
        elseif ($parsed) { $rawList = @($parsed) }
    } catch {
        Write-CtrlLog $LogDir ("ERROR parse present json " + $_.Exception.Message)
    }
}

Write-CtrlLog $LogDir ("PNP_RAW_COUNT=" + $rawList.Count)

$seen = @{}
$controllers = New-Object System.Collections.Generic.List[object]

foreach ($raw in $rawList) {
    $cardKey = ([string]$raw.CardId).ToUpperInvariant()
    if (-not $cardKey) {
        $cardKey = ([string]$raw.DeviceInstanceId).ToUpperInvariant()
    }
    if ($cardKey -and $seen.ContainsKey($cardKey)) {
        Write-CtrlLog $LogDir ("DEDUP skip " + $cardKey)
        continue
    }

    $mapped = Convert-RawController -Raw $raw -Root $root -LogDir $LogDir -HidusbfOk $hidusbf.available
    if (-not $mapped) { continue }

    if ($cardKey) { $seen[$cardKey] = $true }
    # Hashtable only — [pscustomobject] shadows keys "type" and "name" (CLR members).
    $controllers.Add($mapped) | Out-Null
    Write-CtrlLog $LogDir ("ACCEPTED " + $mapped['type'] + " " + $mapped['name'] + " boost=" + $mapped['boostButton'] + " hz=" + $mapped['currentPollingRate'] + "/" + $mapped['maxPollingRate'])
}

$sw.Stop()
$count = $controllers.Count
Write-CtrlLog $LogDir ("SCAN_END count=$count ms=" + $sw.ElapsedMilliseconds)

Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'GetControllers' `
    -Message ("$count manette(s) détectée(s)") `
    -Data @{
        controllers = @($controllers.ToArray())
        hidusbf       = $hidusbf
        scanMs        = $sw.ElapsedMilliseconds
    }
