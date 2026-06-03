#Requires -Version 5.1
<#
.SYNOPSIS
  Direct Controller Overclocker — strict 1000 Hz / 8000 Hz branches (CLI RateHz only).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$ParamFile = '',
    [string]$ResultPath = '',
    [string]$DeviceInstanceId = '',
    [string]$UsbParentDeviceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = '',
    [int]$RateHz = 0,
    [int]$MaxRateHz = 0,
    [string]$DriverPath = '',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

$paramJson = Import-ControllerOverclockerParams -ParamFile $ParamFile
if ($paramJson) {
    if ($paramJson.AppRoot) { $AppRoot = [string]$paramJson.AppRoot }
    if ($paramJson.LogPath) { $LogPath = [string]$paramJson.LogPath }
    if (-not $DeviceInstanceId -and $paramJson.DeviceInstanceId) { $DeviceInstanceId = [string]$paramJson.DeviceInstanceId }
    if (-not $UsbParentDeviceId -and $paramJson.UsbParentDeviceId) { $UsbParentDeviceId = [string]$paramJson.UsbParentDeviceId }
    if (-not $Vid -and $paramJson.Vid) { $Vid = [string]$paramJson.Vid }
    if (-not $DevicePid -and $paramJson.Pid) { $DevicePid = [string]$paramJson.Pid }
    if ($paramJson.DriverPath) { $DriverPath = [string]$paramJson.DriverPath }
    if (-not $PSBoundParameters.ContainsKey('MaxRateHz') -and $paramJson.MaxRateHz) {
        $MaxRateHz = [int]$paramJson.MaxRateHz
    }
    if ($paramJson.Uninstall -eq $true -or [string]$paramJson.Mode -eq 'Restore') { $Uninstall = $true }
}

if (-not $DeviceInstanceId) { $DeviceInstanceId = [string]$env:CONTROLLER_OC_INSTANCE_ID }
if (-not $UsbParentDeviceId) { $UsbParentDeviceId = [string]$env:CONTROLLER_OC_USB_PARENT_ID }
if (-not $DriverPath) { $DriverPath = [string]$env:CONTROLLER_OC_DRIVER_PATH }
if ($DriverPath -match '(?i)\.zip$') { $DriverPath = '' }
if (-not $Uninstall -and $env:CONTROLLER_OC_UNINSTALL -match '^(?i)(1|true|yes)$') { $Uninstall = $true }

$script:AppPath = Resolve-UnrealAppRoot $AppRoot
if (-not $script:AppPath) { exit 9 }
$script:LogFile = if ($LogPath) { $LogPath } else { Join-Path $script:AppPath 'logs\controller-overclocker.log' }
if (-not $ResultPath) { $ResultPath = Join-Path $script:AppPath 'logs\controller-oc-result.json' }

$script:TargetHidusbfDeviceId = ''
$script:UsbCompositeParentId = ''
$script:BundleHt = @{}
$script:UsbKey = ''
$script:ClassKey = ''
$script:RateHz = 0

function Write-OcLog { param([string]$Line) Write-DeviceLog ("[CONTROLLER-OC] " + $Line) $script:LogFile }

function Write-OcResult {
    param(
        [bool]$Success,
        [bool]$Verified,
        [string]$Code,
        [string]$Message,
        [bool]$NeedsReconnect = $false,
        [int]$ExitCode = 1,
        [int]$ConfirmedRate = -1,
        [string]$DriverVariant = '',
        [int]$PatchUSBXHCI = -1
    )
    $req = if ($Uninstall) { 125 } else { [int]$script:RateHz }
    $conf = if ($ConfirmedRate -ge 0) { [int]$ConfirmedRate } else { $req }
    $variant = if ($DriverVariant) { $DriverVariant } else { (Get-DriverVariantLabelForRate -RateHz $conf) }
    $payload = [ordered]@{
        Success               = $Success
        Verified              = $Verified
        Code                  = $Code
        Message               = $Message
        RequestedRate         = $req
        ConfirmedRate         = $conf
        DriverVariant         = $variant
        DeviceInstanceId      = $DeviceInstanceId
        UsbParentDeviceId     = $UsbParentDeviceId
        UsbCompositeParentId  = $script:UsbCompositeParentId
        TargetHidusbfDeviceId = $script:TargetHidusbfDeviceId
        NeedsReconnect        = $NeedsReconnect
    }
    if ($PatchUSBXHCI -ge 0) { $payload.PatchUSBXHCI = $PatchUSBXHCI }
    $dir = Split-Path -Parent $ResultPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
    $legacyPath = Join-Path $script:AppPath 'logs\controller-overclocker-apply-result.json'
    [System.IO.File]::WriteAllText($legacyPath, ($payload | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
    Write-ScriptExitCode -AppRoot $script:AppPath -Code $ExitCode
}

function Test-ValidControllerInstanceId {
    param([string]$Id)
    $x = ($Id + '').Trim()
    if (-not $x) { return $false }
    if ($x -match '^(?i)(test|null|undefined|none|n/a|na)$') { return $false }
    if ($x.Length -lt 12) { return $false }
    if ($x -notmatch '^(?i)(HID|USB)\\') { return $false }
    if ($x -notmatch '(?i)VID_[0-9A-F]{4}') { return $false }
    if ($x -notmatch '(?i)PID_[0-9A-F]{4}') { return $false }
    return $true
}

function Test-BlockedName {
    param([string]$Text)
    return ($Text -match '(?i)keyboard|clavier|mouse|souris|razer\s*mouse|hid\s*keyboard')
}

function Get-TargetUsbRegPath { param([string]$UsbId) return ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + $UsbId) }

function Get-ClassRegPathFromUsbKey {
    param([string]$UsbRegPath)
    try {
        $drv = (Get-ItemProperty -LiteralPath $UsbRegPath -Name Driver -ErrorAction Stop).Driver
        if (-not $drv) { return '' }
        return ('HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $drv)
    } catch { return '' }
}

function Get-PatchUsbXhciReadback {
    $xhci = $null
    foreach ($keyPath in @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\hidusbf\Parameters',
        'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF'
    )) {
        if (-not (Test-Path -LiteralPath $keyPath)) { continue }
        try {
            $v = (Get-ItemProperty -LiteralPath $keyPath -Name PatchUSBXHCI -ErrorAction SilentlyContinue).PatchUSBXHCI
            if ($null -ne $v) { $xhci = [int]$v; break }
        } catch {}
    }
    if ($null -eq $xhci) { return -1 }
    return $xhci
}

function Set-PatchStrict {
    param([int]$PatchXhci)
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\hidusbf\Parameters'
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -LiteralPath $key -Name PatchUSBPort -Value 1 -Type DWord -Force
    Set-ItemProperty -LiteralPath $key -Name PatchUSBXHCI -Value $PatchXhci -Type DWord -Force
    foreach ($alt in @('HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF')) {
        if (-not (Test-Path -LiteralPath $alt)) { New-Item -Path $alt -Force | Out-Null }
        Set-ItemProperty -LiteralPath $alt -Name PatchUSBPort -Value 1 -Type DWord -Force
        Set-ItemProperty -LiteralPath $alt -Name PatchUSBXHCI -Value $PatchXhci -Type DWord -Force
    }
    return $PatchXhci
}

function Restart-TargetDevice {
    param([string]$InstanceId)
    Write-OcLog ("Restart device target=" + $InstanceId)
    try {
        $p = Start-Process -FilePath 'pnputil.exe' -ArgumentList @('/restart-device', $InstanceId) -Wait -PassThru -WindowStyle Hidden
        Write-OcLog ("Restart result=pnputil_exit_" + $p.ExitCode)
        if ($p.ExitCode -eq 0) { return $true }
    } catch { Write-OcLog ("Restart result=pnputil_error " + $_.Exception.Message) }
    try {
        Restart-PnpDeviceSafe -InstanceIds @($InstanceId) -LogFile $script:LogFile
        Write-OcLog 'Restart result=disable_enable_attempted'
        return $true
    } catch { Write-OcLog ("Restart result=fallback_error " + $_.Exception.Message) }
    return $false
}

function Assert-Not8000Path {
    param([string]$Path)
    if ($Path -match '(?i)4khz|8khz') {
        Write-OcResult -Success $false -Verified $false -Code 'RATE_1000_USING_8000_VARIANT' `
            -Message 'Apply-Controller1000: chemin variante 8000 interdit' -ExitCode 38
        exit 38
    }
}

function Copy-1khzVariantOnly {
    param([hashtable]$Bundle)
    $variant = Get-HidusbfVariantSysPath -Bundle $Bundle -Rate 1000
    if (-not $variant -or -not (Test-Path -LiteralPath $variant)) {
        Write-OcResult -Success $false -Verified $false -Code 'VARIANT_NOT_FOUND' -Message 'Variante 1khz introuvable' -ExitCode 33
        exit 33
    }
    Assert-Not8000Path -Path $variant
    Write-OcLog ("Driver variant path=" + $variant)
    if (-not (Copy-HidusbfVariantToActive -Bundle $Bundle -VariantSysPath $variant -Rate 1000 -LogFile $script:LogFile)) {
        $dest = Join-Path $Bundle.DriverDir 'AMD64_AS\hidusbf.sys'
        if ($dest) {
            $dDir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dDir)) { New-Item -ItemType Directory -Path $dDir -Force | Out-Null }
            Copy-Item -LiteralPath $variant -Destination $dest -Force
        }
    }
    if (-not (Test-ActiveDriverVariantMatchesRate -Bundle $Bundle -RequestedRate 1000)) {
        Write-OcResult -Success $false -Verified $false -Code 'DRIVER_VARIANT_MISMATCH_1000' `
            -Message 'Variante driver 1khz non activee' -ExitCode 35
        exit 35
    }
}

function Copy-8khzVariantOnly {
    param([hashtable]$Bundle)
    $variant = Get-HidusbfVariantSysPath -Bundle $Bundle -Rate 8000
    if (-not $variant -or -not (Test-Path -LiteralPath $variant)) {
        Write-OcResult -Success $false -Verified $false -Code 'VARIANT_NOT_FOUND' -Message 'Variante 4khz-8khz introuvable' -ExitCode 33
        exit 33
    }
    if ($variant -notmatch '(?i)4khz|8khz') {
        Write-OcResult -Success $false -Verified $false -Code 'DRIVER_VARIANT_MISMATCH_8000' `
            -Message 'Chemin variante 8000 invalide' -ExitCode 35
        exit 35
    }
    Write-OcLog ("Driver variant path=" + $variant)
    if (-not (Copy-HidusbfVariantToActive -Bundle $Bundle -VariantSysPath $variant -Rate 8000 -LogFile $script:LogFile)) {
        $dest = Join-Path $Bundle.DriverDir 'AMD64_AS\hidusbf.sys'
        if ($dest) {
            $dDir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dDir)) { New-Item -ItemType Directory -Path $dDir -Force | Out-Null }
            Copy-Item -LiteralPath $variant -Destination $dest -Force
        }
    }
    if (-not (Test-ActiveDriverVariantMatchesRate -Bundle $Bundle -RequestedRate 8000)) {
        Write-OcResult -Success $false -Verified $false -Code 'DRIVER_VARIANT_MISMATCH_8000' `
            -Message 'Variante driver 4khz-8khz non activee' -ExitCode 35
        exit 35
    }
}

function Set-BIntervalOnClass {
    param([int]$Value)
    if (-not $script:ClassKey -or -not (Test-Path -LiteralPath $script:ClassKey)) { return }
    $before = (Get-ItemProperty -LiteralPath $script:ClassKey -Name bInterval -ErrorAction SilentlyContinue).bInterval
    Write-OcLog ("bInterval before=" + $before)
    Set-ItemProperty -LiteralPath $script:ClassKey -Name bInterval -Value $Value -Type DWord -Force
    Write-OcLog ("bInterval after=" + $Value)
}

function Invoke-ApplyController1000 {
    Write-OcLog 'ENTER Apply-Controller1000'
    Write-OcLog 'RequestedRate=1000'
    Write-OcLog 'DriverVariant=1khz'
    Write-OcLog 'PatchUSBXHCI=1 PatchUSBPort=1 bInterval=1'

    Copy-1khzVariantOnly -Bundle $script:BundleHt

    $patch = Set-PatchStrict -PatchXhci 1
    Write-OcLog ("PatchUSBXHCI applied=" + $patch)

    [void](Add-HidusbfLowerFilter -RegPath $script:UsbKey)
    Set-BIntervalOnClass -Value 1

    $restartOk = Restart-TargetDevice -InstanceId $UsbParentDeviceId
    $needsReconnect = -not $restartOk
    Start-Sleep -Seconds 1

    $readback = Get-PatchUsbXhciReadback
    Write-OcLog ("PatchUSBXHCI readback=" + $readback)
    $activeRate = Get-ActiveHidusbfVariantRateFromBundle -Bundle $script:BundleHt
    $variantLabel = if ($null -ne $activeRate) { (Get-DriverVariantLabelForRate -RateHz $activeRate) } else { 'unknown' }
    Write-OcLog ("Variant readback=" + $variantLabel)

    if ($readback -eq 3) {
        Write-OcResult -Success $false -Verified $false -Code '1000_STILL_HAS_8000_PATCH' `
            -Message '1000 demande mais PatchUSBXHCI=3 (8000)' -ConfirmedRate 8000 `
            -DriverVariant '4khz-8khz' -PatchUSBXHCI 3 -ExitCode 39
        exit 39
    }

    $confirmed = Get-ConfirmedControllerRate -Bundle $script:BundleHt
    if ($readback -eq 1 -and $confirmed -eq 1000) {
        Write-OcResult -Success $true -Verified $true -Code 'APPLIED_1000_CONFIRMED' `
            -Message '1000 demande — 1000 detecte' -ConfirmedRate 1000 `
            -DriverVariant '1khz' -PatchUSBXHCI 1 -NeedsReconnect $needsReconnect -ExitCode 0
        exit 0
    }

    if ($confirmed -eq 8000 -or $readback -eq 3) {
        Write-OcResult -Success $false -Verified $false -Code 'RATE_1000_FAILED_STILL_8000' `
            -Message '1000 demande mais 8000 detecte' -ConfirmedRate 8000 `
            -DriverVariant '4khz-8khz' -PatchUSBXHCI $(if ($readback -ge 0) { $readback } else { 3 }) -ExitCode 36
        exit 36
    }

    Write-OcResult -Success $true -Verified $false -Code 'PREPARED_NEEDS_RECONNECT' `
        -Message '1000 Hz prepare — rebranche la manette' -ConfirmedRate $confirmed `
        -DriverVariant (Get-DriverVariantLabelForRate -RateHz $confirmed) -PatchUSBXHCI $readback `
        -NeedsReconnect $true -ExitCode 0
    exit 0
}

function Invoke-ApplyController8000 {
    Write-OcLog 'ENTER Apply-Controller8000'
    Write-OcLog 'RequestedRate=8000'
    Write-OcLog 'DriverVariant=4khz-8khz'

    Copy-8khzVariantOnly -Bundle $script:BundleHt

    $patch = Set-PatchStrict -PatchXhci 3
    Write-OcLog ("PatchUSBXHCI applied=" + $patch)

    [void](Add-HidusbfLowerFilter -RegPath $script:UsbKey)
    Set-BIntervalOnClass -Value 1

    $restartOk = Restart-TargetDevice -InstanceId $UsbParentDeviceId
    $needsReconnect = -not $restartOk
    Start-Sleep -Seconds 1

    $readback = Get-PatchUsbXhciReadback
    Write-OcLog ("PatchUSBXHCI readback=" + $readback)
    $activeRate = Get-ActiveHidusbfVariantRateFromBundle -Bundle $script:BundleHt
    $variantLabel = if ($null -ne $activeRate) { (Get-DriverVariantLabelForRate -RateHz $activeRate) } else { 'unknown' }
    Write-OcLog ("Variant readback=" + $variantLabel)

    $confirmed = Get-ConfirmedControllerRate -Bundle $script:BundleHt
    if ($readback -eq 3 -and $confirmed -eq 8000) {
        Write-OcResult -Success $true -Verified $true -Code 'APPLIED_8000_CONFIRMED' `
            -Message '8000 Hz confirme' -ConfirmedRate 8000 `
            -DriverVariant '4khz-8khz' -PatchUSBXHCI 3 -NeedsReconnect $needsReconnect -ExitCode 0
        exit 0
    }

    if ($confirmed -ne 8000) {
        Write-OcResult -Success $false -Verified $false -Code 'ACTIVE_RATE_MISMATCH' `
            -Message ('8000 demande mais ' + $confirmed + ' Hz detecte') -ConfirmedRate $confirmed `
            -DriverVariant (Get-DriverVariantLabelForRate -RateHz $confirmed) -PatchUSBXHCI $readback -ExitCode 37
        exit 37
    }

    Write-OcResult -Success $true -Verified $false -Code 'PREPARED_NEEDS_RECONNECT' `
        -Message '8000 Hz prepare — rebranche la manette' -ConfirmedRate $confirmed `
        -DriverVariant '4khz-8khz' -PatchUSBXHCI $readback -NeedsReconnect $true -ExitCode 0
    exit 0
}

# --- Rate resolution: CLI only (apply) ---
if ($Uninstall) {
    $script:RateHz = 125
} else {
    if (-not $PSBoundParameters.ContainsKey('RateHz')) {
        Write-OcLog 'CLI RateHz=(missing)'
        Write-OcResult -Success $false -Verified $false -Code 'RATE_MISSING' -Message 'RateHz CLI obligatoire' -ExitCode 2
        exit 2
    }
    $script:RateHz = [int]$PSBoundParameters['RateHz']
    Write-OcLog ("CLI RateHz=" + $script:RateHz)
    if ($script:RateHz -notin @(1000, 8000)) {
        Write-OcLog ("FINAL RateHz=INVALID (" + $script:RateHz + ")")
        Write-OcResult -Success $false -Verified $false -Code 'INVALID_RATE' -Message 'RateHz doit etre 1000 ou 8000' -ExitCode 2
        exit 2
    }
    Write-OcLog ("FINAL RateHz=" + $script:RateHz)
}

if (-not $Uninstall -and -not (Test-IsAdmin)) {
    $elevParams = @{
        AppRoot           = $script:AppPath
        LogPath           = $script:LogFile
        ParamFile         = $ParamFile
        ResultPath        = $ResultPath
        DeviceInstanceId  = $DeviceInstanceId
        UsbParentDeviceId = $UsbParentDeviceId
        Vid               = $Vid
        DevicePid         = $DevicePid
        RateHz            = $script:RateHz
        MaxRateHz         = $MaxRateHz
        DriverPath        = $DriverPath
        Uninstall         = $Uninstall
    }
    Invoke-RelaunchElevated -ScriptPath $PSCommandPath -BoundParams $elevParams
}

Write-OcLog ("DeviceInstanceId=" + $DeviceInstanceId)
Write-OcLog ("UsbParentDeviceId=" + $UsbParentDeviceId)

if (-not (Test-ValidControllerInstanceId $DeviceInstanceId)) {
    Write-OcResult -Success $false -Verified $false -Code 'INVALID_DEVICE_INSTANCE_ID' -Message 'Aucun peripherique selectionne' -ExitCode 1
    exit 1
}

if (Test-BlockedName $DeviceInstanceId) {
    Write-OcResult -Success $false -Verified $false -Code 'BLOCKED_DEVICE' -Message 'Securite: clavier/souris refuse' -ExitCode 4
    exit 4
}

$bundle = Resolve-HidusbfToolPath -AppRoot $script:AppPath -LogFile $script:LogFile
if (-not $bundle.Resolved) {
    Write-OcResult -Success $false -Verified $false -Code 'HIDUSBF_NOT_FOUND' -Message 'HIDUSBF extrait introuvable' -ExitCode 12
    exit 12
}

foreach ($k in $bundle.Keys) { $script:BundleHt[$k] = $bundle[$k] }

$serviceExists = $false
try { $serviceExists = [bool](Get-Service -Name 'hidusbf' -ErrorAction SilentlyContinue) } catch {}
if (-not $serviceExists) {
    $inf = $bundle.InfPath
    try {
        $pnp = Start-Process -FilePath 'pnputil.exe' -ArgumentList @('/add-driver', $inf, '/install') -Wait -PassThru -WindowStyle Hidden
        Write-OcLog ("INF install exit=" + $pnp.ExitCode)
    } catch { Write-OcLog 'INF install failed' }
}

if (-not $Vid -or -not $DevicePid) {
    $vpLine = Get-VidPidFromInstanceId $DeviceInstanceId
    if (-not $Vid) { $Vid = $vpLine.Vid }
    if (-not $DevicePid) { $DevicePid = $vpLine.Pid }
}

$capApply = Get-ControllerTypeAndCapability -Vid $Vid -DevicePid $DevicePid -NameBlob $DeviceInstanceId
if ($MaxRateHz -le 0) { $MaxRateHz = [int]$capApply.MaxRateHz }
Write-OcLog ("Selected VID/PID=" + $Vid + '/' + $DevicePid)
Write-OcLog ("Selected Type=" + [string]$capApply.Type)
Write-OcLog ("MaxRateHz=" + $MaxRateHz)

if (-not $Uninstall -and $MaxRateHz -gt 0 -and $script:RateHz -gt $MaxRateHz) {
    Write-OcResult -Success $false -Verified $false -Code 'RATE_NOT_SUPPORTED_BY_CONTROLLER' `
        -Message ('Cette manette ne supporte pas ' + $script:RateHz + ' Hz') -ConfirmedRate $MaxRateHz -ExitCode 40
    exit 40
}

function Test-IsDualSenseUsbCompositeParent {
    param([string]$UsbId)
    if (-not $UsbId) { return $false }
    if ($UsbId -notmatch '(?i)^USB\\VID_054C&PID_0CE6\\') { return $false }
    if ($UsbId -match '(?i)&MI_') { return $false }
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $UsbId
    return (Test-Path -LiteralPath $regPath)
}

$resolvedParent = ''
if (Test-IsDualSenseUsbCompositeParent $UsbParentDeviceId) {
    $resolvedParent = $UsbParentDeviceId
    Write-OcLog ("USB parent hint accepted=" + $resolvedParent)
} else {
    $compositeTarget = Resolve-HidusbfCompositeTarget `
        -DeviceInstanceId $DeviceInstanceId `
        -Vid $Vid `
        -DevicePid $DevicePid `
        -HintUsbParentId $UsbParentDeviceId `
        -LogFile $script:LogFile

    if ($compositeTarget.Code -eq 'WRONG_TARGET_MI_INTERFACE') {
        Write-OcResult -Success $false -Verified $false -Code 'WRONG_TARGET_MI_INTERFACE' -Message ([string]$compositeTarget.Message) -ExitCode 32
        exit 32
    }

    if (-not $compositeTarget.TargetHidusbfDeviceId) {
        Write-OcResult -Success $false -Verified $false -Code 'USB_COMPOSITE_NOT_FOUND' -Message 'Parent USB composite introuvable' -ExitCode 31
        exit 31
    }

    $resolvedParent = [string]$compositeTarget.TargetHidusbfDeviceId
    $script:UsbCompositeParentId = [string]$compositeTarget.UsbCompositeParentId
}

$script:TargetHidusbfDeviceId = $resolvedParent
if (-not $script:UsbCompositeParentId) { $script:UsbCompositeParentId = $resolvedParent }
$UsbParentDeviceId = $script:TargetHidusbfDeviceId
Write-OcLog ("TargetHidusbfDeviceId=" + $UsbParentDeviceId)

$script:UsbKey = Get-TargetUsbRegPath $UsbParentDeviceId
if (-not (Test-Path -LiteralPath $script:UsbKey)) {
    Write-OcResult -Success $false -Verified $false -Code 'USB_PARENT_KEY_MISSING' -Message 'Cle USB parent introuvable' -ExitCode 31
    exit 31
}

$script:ClassKey = Get-ClassRegPathFromUsbKey -UsbRegPath $script:UsbKey
Write-OcLog ("Target USB parent key=" + $script:UsbKey)
Write-OcLog ("Driver class key=" + $script:ClassKey)

if ($Uninstall) {
    Write-OcLog 'ENTER Restore-125 (NoPatch + remove filter)'
    $nopatch = Get-HidusbfVariantSysPath -Bundle $script:BundleHt -Rate 125
    if ($nopatch -and (Test-Path -LiteralPath $nopatch)) {
        Write-OcLog ("NoPatch variant=" + $nopatch)
        [void](Copy-HidusbfVariantToActive -Bundle $script:BundleHt -VariantSysPath $nopatch -Rate 125 -LogFile $script:LogFile)
    } else {
        Write-OcLog 'WARN NoPatch hidusbf.sys missing — continuing filter removal'
    }

    foreach ($keyPath in @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\hidusbf\Parameters',
        'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF'
    )) {
        if (-not (Test-Path -LiteralPath $keyPath)) { continue }
        try {
            Remove-ItemProperty -LiteralPath $keyPath -Name PatchUSBXHCI -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $keyPath -Name PatchUSBPort -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-OcLog 'PatchUSBXHCI/PatchUSBPort cleared'

    [void](Remove-HidusbfLowerFilter -RegPath $script:UsbKey)
    if ($script:ClassKey) { Remove-ItemProperty -LiteralPath $script:ClassKey -Name bInterval -ErrorAction SilentlyContinue }
    $restartOk = Restart-TargetDevice -InstanceId $UsbParentDeviceId
    Start-Sleep -Seconds 1

    $filters = @((Get-ItemProperty -LiteralPath $script:UsbKey -Name LowerFilters -ErrorAction SilentlyContinue).LowerFilters)
    $verifiedHz = Get-UsbParentPollingRate -UsbParentDeviceId $UsbParentDeviceId
    Write-OcLog ("Restore verify filter=" + ($filters -join ',') + " pollingHz=$verifiedHz")

    if ($filters -notcontains 'hidusbf' -and $verifiedHz -le 125) {
        Write-OcResult -Success $true -Verified $true -Code 'RESTORED_125' -Message 'Polling restauré à 125 Hz' `
            -ConfirmedRate 125 -DriverVariant 'NoPatch' -NeedsReconnect (-not $restartOk) -ExitCode 0
        exit 0
    }
    if ($filters -notcontains 'hidusbf') {
        Write-OcResult -Success $true -Verified $false -Code 'RESTORED_FILTER_OFF' `
            -Message 'Filtre HIDUSBF retiré — rebranchez la manette si le polling reste élevé' `
            -ConfirmedRate $verifiedHz -DriverVariant 'NoPatch' -NeedsReconnect $true -ExitCode 0
        exit 0
    }
    Write-OcResult -Success $false -Verified $false -Code 'VERIFY_FAILED' `
        -Message ('Restauration non confirmée (filtre hidusbf encore actif, polling ' + $verifiedHz + ' Hz)') -ExitCode 34
    exit 34
}

switch ($script:RateHz) {
    1000 { Invoke-ApplyController1000 }
    8000 { Invoke-ApplyController8000 }
    default {
        Write-OcResult -Success $false -Verified $false -Code 'RATE_INVALID' -Message 'Rate invalide' -ExitCode 2
        exit 2
    }
}
