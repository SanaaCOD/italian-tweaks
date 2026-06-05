#Requires -Version 5.1
<#
.SYNOPSIS
  Silent automatic restore of default polling for a selected controller.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$ResultPath = '',
    [string]$ParamFile = '',
    [string]$DeviceInstanceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = ''
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

function Get-LatestDeviceBackupFiles {
    param(
        [string]$BackupDir,
        [string[]]$RegPaths
    )
    if (-not (Test-Path -LiteralPath $BackupDir)) { return @() }
    $files = @()
    foreach ($regPath in @($RegPaths | Where-Object { $_ } | Select-Object -Unique)) {
        $safe = ($regPath -replace '[\\\\:*?"<>|]', '_')
        $pattern = 'device-*-' + [regex]::Escape($safe) + '.reg'
        $match = Get-ChildItem -LiteralPath $BackupDir -Filter '*.reg' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like ('device-*-' + ($safe -replace '\[|\]', '?')) -or $_.Name -match [regex]::Escape($safe) } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $match) {
            $instancePart = ($regPath -replace '^HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\', '')
            $instanceSafe = ($instancePart -replace '[\\\\:*?"<>|]', '_')
            $match = Get-ChildItem -LiteralPath $BackupDir -Filter '*.reg' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match [regex]::Escape($instanceSafe) } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
        }
        if ($match) { $files += $match.FullName }
    }
    return @($files | Select-Object -Unique)
}

$paramJson = Import-ControllerOverclockerParams -ParamFile $ParamFile
if ($paramJson) {
    if ($paramJson.AppRoot) { $AppRoot = [string]$paramJson.AppRoot }
    if ($paramJson.LogPath) { $LogPath = [string]$paramJson.LogPath }
    if ($paramJson.DeviceInstanceId) { $DeviceInstanceId = [string]$paramJson.DeviceInstanceId }
    if ($paramJson.Vid) { $Vid = [string]$paramJson.Vid }
    if ($paramJson.Pid) { $DevicePid = [string]$paramJson.Pid }
}

if (-not (Test-IsAdmin)) {
    $failApp = Resolve-UnrealAppRoot $AppRoot
    $resultFile = if ($ResultPath) { $ResultPath } elseif ($failApp) { Join-Path $failApp 'logs\controller-overclocker-apply-result.json' } else { '' }
    if ($resultFile) {
        $payload = @{
            Success = $false
            Code = 'NOT_ADMIN'
            Message = 'Droits administrateur requis pour restaurer HIDUSBF'
            FallbackAvailable = $true
        } | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($resultFile, $payload, [System.Text.UTF8Encoding]::new($false))
    }
    if ($failApp) { Write-ScriptExitCode -AppRoot $failApp -Code 20 }
    exit 20
}

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) {
    Write-DeviceLog '[DEVICE] Result: error app_root_unresolved' $LogPath
    Write-ScriptExitCode -AppRoot $AppRoot -Code 9
    exit 9
}

if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }

Write-DeviceLog '[DEVICE] Auto restore requested' $LogPath
Write-DeviceLog ("[DEVICE] Selected device: " + $DeviceInstanceId) $LogPath
Write-DeviceLog ("[DEVICE] VID/PID: " + $Vid + '/' + $DevicePid) $LogPath
Write-DeviceLog ("[DEVICE] DeviceInstanceId: " + $DeviceInstanceId) $LogPath

if (-not $DeviceInstanceId) {
    Write-DeviceLog '[DEVICE] Result: error no_device_selected' $LogPath
    Write-ScriptExitCode -AppRoot $app -Code 1
    exit 1
}

$label = $DeviceInstanceId + ' VID=' + $Vid + ' PID=' + $DevicePid
if (Test-BlockedInputDevice $label) {
    Write-DeviceLog '[DEVICE] Result: error blocked_input_device' $LogPath
    Write-ScriptExitCode -AppRoot $app -Code 4
    exit 4
}

$regPlan = Find-DeviceRegistryPaths -DeviceInstanceId $DeviceInstanceId -Vid $Vid -DevicePid $DevicePid -LogFile $LogPath
if (-not $regPlan -or -not $regPlan.ApplyPaths -or $regPlan.ApplyPaths.Count -eq 0) {
    Write-DeviceLog '[DEVICE] Result: error registry_paths_not_found' $LogPath
    Write-ScriptExitCode -AppRoot $app -Code 5
    exit 5
}

$backupDir = Join-Path $app 'logs\controller-overclocker-backup'
$backupFiles = Get-LatestDeviceBackupFiles -BackupDir $backupDir -RegPaths $regPlan.ApplyPaths
Write-DeviceLog '[DEVICE] Registry restore' $LogPath
foreach ($backup in $backupFiles) {
    Write-DeviceLog ("[DEVICE] Restoring backup: " + $backup) $LogPath
    & reg.exe import $backup 2>&1 | Out-Null
}

Write-DeviceLog '[DEVICE] Registry apply (remove hidusbf filter)' $LogPath
$removed = $true
foreach ($path in @($regPlan.ApplyPaths | Select-Object -Unique)) {
    try {
        if (-not (Remove-HidusbfLowerFilter -RegPath $path)) {
            $removed = $false
            Write-DeviceLog ("[DEVICE] Remove hidusbf failed: " + $path) $LogPath
        } else {
            Write-DeviceLog ("[DEVICE] hidusbf removed from: " + $path) $LogPath
        }
    } catch {
        $removed = $false
        Write-DeviceLog ("[DEVICE] Remove hidusbf error: " + $path + " " + $_.Exception.Message) $LogPath
    }
}

Write-DeviceLog '[DEVICE] Device restart' $LogPath
Restart-PnpDeviceSafe -InstanceIds $regPlan.RestartIds -LogFile $LogPath

$stillFiltered = $false
foreach ($path in @($regPlan.ApplyPaths | Select-Object -Unique)) {
    try {
        $prop = Get-ItemProperty -LiteralPath $path -Name LowerFilters -ErrorAction SilentlyContinue
        if ($prop -and @($prop.LowerFilters) -contains 'hidusbf') {
            $stillFiltered = $true
            break
        }
    } catch {}
}

if ($stillFiltered -or -not $removed) {
    Write-DeviceLog '[DEVICE] Result: error restore_failed' $LogPath
    Write-ScriptExitCode -AppRoot $app -Code 5
    exit 5
}

Write-DeviceLog '[DEVICE] Result: success' $LogPath
if (-not $ResultPath) { $ResultPath = Join-Path $app 'logs\controller-overclocker-apply-result.json' }
try {
    $okPayload = @{
        Success = $true
        Code = 'RESTORED'
        Message = 'Reglage par defaut restaure'
        NeedsReconnect = $true
        FallbackAvailable = $false
    } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($ResultPath, $okPayload, [System.Text.UTF8Encoding]::new($false))
} catch {}
Write-ScriptExitCode -AppRoot $app -Code 0
exit 0
