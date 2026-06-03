#Requires -Version 5.1
<#
.SYNOPSIS
  Silent automatic HIDUSBF apply for a selected controller (no Setup.exe).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$ResultPath = '',
    [string]$ParamFile = '',
    [string]$DeviceInstanceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = '',
    [ValidateSet(1000, 8000)]
    [int]$Rate = 1000
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

function Write-AutoLog {
    param([string]$Line)
    if (-not $script:AutoLogPath) { return }
    Write-DeviceLog ("[DEVICE-AUTO] " + $Line) $script:AutoLogPath
}

function Write-AutoResult {
    param(
        [bool]$Success,
        [string]$Code,
        [string]$Message,
        [int]$ExitCode = 1,
        [bool]$NeedsReconnect = $false,
        [bool]$FallbackAvailable = $true,
        [bool]$Verified = $false,
        [string]$ErrorDetail = ''
    )
    $payload = [ordered]@{
        Success           = $Success
        Code              = $Code
        Message           = $Message
        NeedsReconnect    = $NeedsReconnect
        FallbackAvailable = $FallbackAvailable
        Verified          = $Verified
        Rate              = $script:AutoRate
        DeviceInstanceId  = $script:AutoDeviceInstanceId
        Vid               = $script:AutoVid
        Pid               = $script:AutoDevicePid
    }
    if ($ErrorDetail) { $payload.ErrorDetail = $ErrorDetail }

    if ($script:AutoResultPath) {
        try {
            $dir = Split-Path -Parent $script:AutoResultPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $json = $payload | ConvertTo-Json -Depth 4 -Compress:$false
            [System.IO.File]::WriteAllText($script:AutoResultPath, $json, [System.Text.UTF8Encoding]::new($false))
        } catch {}
    }

    if ($Success) {
        Write-AutoLog ('FINAL result=prepared verified=' + $Verified.ToString().ToLowerInvariant())
    } else {
        Write-AutoLog ('FINAL result=error')
        Write-AutoLog ('ERROR detail=' + ($ErrorDetail -replace '\s+', ' '))
    }

    if ($script:AutoAppRoot) {
        Write-ScriptExitCode -AppRoot $script:AutoAppRoot -Code $ExitCode
    }
    exit $ExitCode
}

function Test-HidusbfLowerFilterOnPath {
    param([string]$RegPath)
    if (-not $RegPath -or -not (Test-Path -LiteralPath $RegPath)) { return $false }
    try {
        $prop = Get-ItemProperty -LiteralPath $RegPath -Name LowerFilters -ErrorAction SilentlyContinue
        return ($null -ne $prop.LowerFilters -and @($prop.LowerFilters) -contains 'hidusbf')
    } catch {
        return $false
    }
}

function Test-HidusbfDriverPresent {
    $svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\hidusbf'
    if (Test-Path -LiteralPath $svcKey) { return $true }
    $driversKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\HIDUSBF'
    return (Test-Path -LiteralPath $driversKey)
}

function Import-SweetLowCertificateDetailed {
    param([string]$CertPath)
    if (-not $CertPath -or -not (Test-Path -LiteralPath $CertPath)) {
        Write-AutoLog 'Import certificate start (SweetLow.CER missing — skipped)'
        Write-AutoLog 'Import certificate result=skipped exitcode=0'
        return $true
    }
    Write-AutoLog 'Import certificate start'
    $tpOut = & certutil.exe -addstore -f 'TrustedPublisher' $CertPath 2>&1 | Out-String
    $tpCode = $LASTEXITCODE
    Write-AutoLog ("Import certificate TrustedPublisher exitcode=" + $tpCode)
    foreach ($line in ($tpOut -split "`r?`n")) {
        $t = $line.Trim()
        if ($t) { Write-AutoLog ('Import certificate stdout=' + $t) }
    }

    $rootOut = & certutil.exe -addstore -f 'Root' $CertPath 2>&1 | Out-String
    $rootCode = $LASTEXITCODE
    Write-AutoLog ("Import certificate Root exitcode=" + $rootCode)
    foreach ($line in ($rootOut -split "`r?`n")) {
        $t = $line.Trim()
        if ($t) { Write-AutoLog ('Import certificate stderr=' + $t) }
    }

    $ok = ($tpCode -eq 0 -or $tpOut -match '(?i)completed successfully|already in store|CertUtil: -addstore command completed successfully') -and
          ($rootCode -eq 0 -or $rootOut -match '(?i)completed successfully|already in store|CertUtil: -addstore command completed successfully')
    Write-AutoLog ('Import certificate result=' + ($(if ($ok) { 'ok' } else { 'failed' })))
    return $ok
}

function Install-HidusbfDriverInfDetailed {
    param([string]$InfPath)
    if (-not (Test-Path -LiteralPath $InfPath)) {
        Write-AutoLog 'INF install start (INF missing)'
        Write-AutoLog 'INF install result=failed exitcode=-1'
        return $false
    }

    if (Test-HidusbfDriverPresent) {
        Write-AutoLog 'INF install start (driver service already present — skip install attempt)'
        Write-AutoLog 'INF install result=already_present exitcode=0'
        return $true
    }

    Write-AutoLog 'INF install start'
    $section = 'DefaultInstall.nt'
    $argLine = "setupapi,InstallHinfSection $section 132 `"$InfPath`""
    $proc = Start-Process -FilePath 'rundll32.exe' -ArgumentList $argLine -Wait -PassThru -WindowStyle Hidden
    $code = if ($proc) { $proc.ExitCode } else { -1 }
    Write-AutoLog ("INF install exitcode=" + $code)

    if (Test-HidusbfDriverPresent) {
        Write-AutoLog 'INF install result=ok (service present after attempt)'
        return $true
    }

    if ($code -eq 0) {
        Write-AutoLog 'INF install result=ok exitcode=0'
        return $true
    }

    Write-AutoLog 'INF install result=failed'
    return $false
}

function Find-SelectedControllerDevice {
    param(
        [string]$DeviceInstanceId,
        [string]$Vid,
        [string]$DevicePid
    )
    $target = ($DeviceInstanceId + '').ToUpperInvariant()
    $mi = ''
    if ($DeviceInstanceId -match '(?i)MI_(\d+)') { $mi = $Matches[1] }

    try {
        foreach ($dev in (Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)) {
            $id = [string]$dev.DeviceID
            if ($target -and $id.ToUpperInvariant() -eq $target) { return $dev }
            if (-not $Vid -or -not $DevicePid) { continue }
            if ($id -notmatch ('(?i)VID_' + [regex]::Escape($Vid))) { continue }
            if ($id -notmatch ('(?i)PID_' + [regex]::Escape($DevicePid))) { continue }
            if ($mi -and $id -notmatch ('(?i)MI_' + [regex]::Escape($mi))) { continue }
            if ($id -match '(?i)^(HID|USB)\\') { return $dev }
        }
    } catch {
        Write-AutoLog ("Device lookup exception=" + $_.Exception.Message)
    }
    return $null
}

$paramJson = Import-ControllerOverclockerParams -ParamFile $ParamFile
if ($paramJson) {
    if ($paramJson.AppRoot) { $AppRoot = [string]$paramJson.AppRoot }
    if ($paramJson.LogPath) { $LogPath = [string]$paramJson.LogPath }
    if ($paramJson.DeviceInstanceId) { $DeviceInstanceId = [string]$paramJson.DeviceInstanceId }
    if ($paramJson.Vid) { $Vid = [string]$paramJson.Vid }
    if ($paramJson.Pid) { $DevicePid = [string]$paramJson.Pid }
    if ($paramJson.Rate) { $Rate = [int]$paramJson.Rate }
}

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) {
    Write-AutoResult -Success $false -Code 'APP_ROOT' -Message 'Chemin application introuvable' -ExitCode 9 -ErrorDetail 'app_root_unresolved'
}

$script:AutoAppRoot = $app
$script:AutoLogPath = if ($LogPath) { $LogPath } else { Join-Path $app 'logs\controller-overclocker.log' }
$script:AutoResultPath = if ($ResultPath) { $ResultPath } else { Join-Path $app 'logs\controller-overclocker-apply-result.json' }
$script:AutoRate = $Rate
$script:AutoDeviceInstanceId = $DeviceInstanceId
$script:AutoVid = $Vid
$script:AutoDevicePid = $DevicePid

Write-AutoLog 'Start apply'
Write-AutoLog ('IsAdmin=' + (Test-IsAdmin))
Write-AutoLog ('DeviceInstanceId=' + $DeviceInstanceId)
Write-AutoLog ('VID=' + $Vid)
Write-AutoLog ('PID=' + $DevicePid)
Write-AutoLog ('Rate=' + $Rate)

if (-not (Test-IsAdmin)) {
    Write-AutoResult -Success $false -Code 'NOT_ADMIN' -Message 'Droits administrateur requis pour appliquer HIDUSBF' -ExitCode 20 -ErrorDetail 'process_not_elevated'
}

if (-not $DeviceInstanceId) {
    Write-AutoResult -Success $false -Code 'DEVICE_NOT_FOUND' -Message 'Aucun peripherique selectionne' -ExitCode 1 -ErrorDetail 'no_device_selected'
}

$label = $DeviceInstanceId + ' VID=' + $Vid + ' PID=' + $DevicePid
if (Test-BlockedInputDevice $label) {
    Write-AutoResult -Success $false -Code 'DEVICE_NOT_ALLOWED' -Message 'Peripherique clavier/souris refuse' -ExitCode 4 -ErrorDetail 'blocked_input_device'
}
if (-not (Test-AllowedControllerDevice -Text $label -Vid $Vid -DevicePid $DevicePid)) {
    Write-AutoResult -Success $false -Code 'DEVICE_NOT_ALLOWED' -Message 'Seules les manettes autorisees' -ExitCode 4 -ErrorDetail 'device_not_allowed'
}

$pnpMatch = Find-SelectedControllerDevice -DeviceInstanceId $DeviceInstanceId -Vid $Vid -DevicePid $DevicePid
if (-not $pnpMatch) {
    Write-AutoResult -Success $false -Code 'DEVICE_NOT_FOUND' -Message 'Manette introuvable ou deconnectee' -ExitCode 1 -ErrorDetail 'device_not_found_in_pnp'
}

$bundle = Ensure-HidusbfFullBundle -AppRoot $app -LogFile $script:AutoLogPath
$toolsPath = if ($bundle.Root) { $bundle.Root } else { Join-Path $app 'Tools\hidusbf' }
Write-AutoLog ('ToolsPath=' + $toolsPath)
Write-AutoLog ('HIDUSBF_AS.INF exists=' + (Test-Path -LiteralPath $bundle.InfPath))
Write-AutoLog ('SweetLow.CER exists=' + (Test-Path -LiteralPath $bundle.CertPath))

if (-not $bundle.Found) {
    Write-AutoResult -Success $false -Code 'BUNDLE_MISSING' -Message 'Bundle HIDUSBF incomplet dans Tools\hidusbf' -ExitCode 11 -ErrorDetail 'hidusbf_bundle_missing'
}

$variantSys = Get-HidusbfVariantSysPath -Bundle $bundle -Rate $Rate
$variantLabel = if ($Rate -eq 8000) { 'AMD64_AS\4khz-8khz\hidusbf.sys' } else { 'AMD64_AS\1khz\hidusbf.sys' }
Write-AutoLog ('Selected driver variant=' + $variantLabel)
Write-AutoLog ('Selected driver exists=' + (Test-Path -LiteralPath $variantSys))
Write-AutoLog ('Selected driver path=' + $variantSys)

if (-not $variantSys) {
    Write-AutoResult -Success $false -Code 'VARIANT_MISSING' -Message ('Variante driver introuvable pour ' + $Rate + ' Hz') -ExitCode 8 -ErrorDetail 'variant_sys_missing'
}

if (-not (Import-SweetLowCertificateDetailed -CertPath $bundle.CertPath)) {
    Write-AutoResult -Success $false -Code 'CERT_FAILED' -Message 'Import certificat SweetLow echoue' -ExitCode 6 -ErrorDetail 'certificate_import_failed'
}

if (-not (Install-HidusbfDriverInfDetailed -InfPath $bundle.InfPath)) {
    if (-not (Test-HidusbfDriverPresent)) {
        Write-AutoResult -Success $false -Code 'INF_FAILED' -Message 'Installation INF HIDUSBF echouee' -ExitCode 7 -ErrorDetail 'inf_install_failed'
    }
    Write-AutoLog 'INF install failed but driver present — continuing'
}

if (-not (Copy-HidusbfVariantToActive -Bundle $bundle -VariantSysPath $variantSys -Rate $Rate -LogFile $script:AutoLogPath)) {
    Write-AutoResult -Success $false -Code 'VARIANT_COPY_FAILED' -Message 'Copie hidusbf.sys active echouee' -ExitCode 8 -ErrorDetail 'variant_copy_failed'
}

Set-HidusbfPatchUsbXhci -Rate $Rate -LogFile $script:AutoLogPath | Out-Null
Restart-HidusbfDriverService -LogFile $script:AutoLogPath | Out-Null

$regPlan = Find-DeviceRegistryPaths -DeviceInstanceId $DeviceInstanceId -Vid $Vid -DevicePid $DevicePid -LogFile $script:AutoLogPath
if (-not $regPlan -or -not $regPlan.ApplyPaths -or $regPlan.ApplyPaths.Count -eq 0) {
    Write-AutoResult -Success $false -Code 'REGISTRY_FAILED' -Message 'Cle registre du peripherique introuvable' -ExitCode 5 -ErrorDetail 'registry_paths_not_found'
}

$usbApplyPaths = @($regPlan.ApplyPaths | Where-Object { $_ -match '(?i)\\Enum\\USB\\' -and $_ -match '(?i)MI_\d+' })
if ($usbApplyPaths.Count -eq 0) {
    Write-AutoResult -Success $false -Code 'REGISTRY_FAILED' -Message 'Interface USB MI_xx introuvable pour cette manette' -ExitCode 5 -ErrorDetail 'usb_mi_path_not_found'
}

$backupDir = Join-Path $app 'logs\controller-overclocker-backup'
foreach ($path in @($regPlan.ApplyPaths | Select-Object -Unique)) {
    Write-AutoLog ('Registry target key=' + $path)
    $backupFile = Backup-DeviceRegistryKey -RegPath $path -BackupDir $backupDir -LogFile $script:AutoLogPath
    Write-AutoLog ('Registry backup path=' + $(if ($backupFile) { $backupFile } else { '(none)' }))
}

$applied = $false
foreach ($path in $usbApplyPaths) {
    if (Test-HidusbfLowerFilterOnPath -RegPath $path) {
        Write-AutoLog ('Registry apply result=already_present ' + $path)
        $applied = $true
        continue
    }
    try {
        if (Add-HidusbfLowerFilter -RegPath $path) {
            if (Test-HidusbfLowerFilterOnPath -RegPath $path) {
                $applied = $true
                Write-AutoLog ('Registry apply result=ok ' + $path)
            } else {
                Write-AutoLog ('Registry apply result=verify_failed ' + $path)
            }
        } else {
            Write-AutoLog ('Registry apply result=failed ' + $path)
        }
    } catch {
        Write-AutoLog ('Registry apply result=exception ' + $path + ' ' + $_.Exception.Message)
    }
}

if (-not $applied) {
    Write-AutoResult -Success $false -Code 'REGISTRY_FAILED' -Message 'Application filtre HIDUSBF sur le peripherique echouee' -ExitCode 5 -ErrorDetail 'registry_apply_failed'
}

Write-AutoLog 'Device restart start'
Restart-PnpDeviceSafe -InstanceIds $regPlan.RestartIds -LogFile $script:AutoLogPath
Write-AutoLog 'Device restart result=completed (PnP disable/enable attempted)'

$verified = $false
foreach ($path in $usbApplyPaths) {
    if (Test-HidusbfLowerFilterOnPath -RegPath $path) {
        $verified = $true
        break
    }
}

if (-not $verified) {
    Write-AutoResult -Success $false -Code 'REGISTRY_FAILED' -Message 'Verification filtre HIDUSBF echouee apres application' -ExitCode 5 -ErrorDetail 'verify_failed'
}

Write-AutoResult -Success $true -Code 'PREPARED_NEEDS_MANUAL_CONFIRMATION' -Message 'Reglage prepare, mais HIDUSBF indique encore Default. Action manuelle ou probe necessaire.' -ExitCode 15 -NeedsReconnect $true -Verified $false -FallbackAvailable $true
