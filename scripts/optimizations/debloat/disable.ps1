<#
.SYNOPSIS
  Kojo Extreme Gaming Debloat - disable.ps1

.DESCRIPTION
  Restores what can be restored from the Kojo debloat manifest.
  Designed as a real rollback helper, not a generic default reset.

.NOTES
  Run as Administrator.
  AppX/OneDrive restoration is best-effort because Windows may remove package sources.
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
  [string]$ManifestPath,
  [switch]$Force,
  [switch]$SkipOneDriveReinstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$KojoRoot = Join-Path $env:ProgramData 'Kojo'
$BackupRoot = Join-Path $KojoRoot 'Backups\Debloat'
$LogRoot = Join-Path $KojoRoot 'Logs'
$LogPath = Join-Path $LogRoot 'debloat.log'
New-Item -ItemType Directory -Force -Path $BackupRoot, $LogRoot | Out-Null

function Write-KojoLog {
  param([string]$Message, [string]$Level = 'INFO')
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
  Write-Host $line
}

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestManifestPath {
  $statePath = Join-Path $BackupRoot 'current-state.json'
  if (Test-Path $statePath) {
    try {
      $state = Get-Content $statePath -Raw | ConvertFrom-Json
      if ($state.manifestPath -and (Test-Path $state.manifestPath)) { return [string]$state.manifestPath }
    } catch {}
  }
  $latest = Get-ChildItem -Path $BackupRoot -Recurse -Filter 'debloat-manifest.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latest) { return $latest.FullName }
  return $null
}

function Convert-StartModeToStartupType {
  param([string]$StartMode)
  switch -Regex ($StartMode) {
    'Auto' { return 'Automatic' }
    'Manual' { return 'Manual' }
    'Disabled' { return 'Disabled' }
    default { return 'Manual' }
  }
}

function Set-ServiceStartModeSafe {
  param([string]$Name, [string]$StartupType)
  $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if ($null -eq $svc) { return $false }
  try {
    Write-KojoLog "DEBLOAT_RESTORE_SERVICE name=$Name startup=$StartupType"
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
    return $true
  } catch {
    Write-KojoLog "RESTORE_SERVICE_FAILED name=$Name error=$($_.Exception.Message)" 'WARN'
    return $false
  }
}

function Restore-RegistryValue {
  param($Entry)
  try {
    $path = [string]$Entry.Path
    $name = [string]$Entry.Name
    $keyExists = [bool]$Entry.KeyExists
    $valueExists = [bool]$Entry.ValueExists

    if ($valueExists) {
      if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
      Set-ItemProperty -Path $path -Name $name -Value $Entry.Value -ErrorAction Stop
      Write-KojoLog "DEBLOAT_RESTORE_REGISTRY restored path=$path name=$name value=$($Entry.Value)"
    } else {
      if (Test-Path $path) {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        Write-KojoLog "DEBLOAT_RESTORE_REGISTRY removed path=$path name=$name"
      }
      # We generally avoid deleting entire keys because other apps may have written values after backup.
      if (-not $keyExists) { Write-KojoLog "DEBLOAT_RESTORE_REGISTRY key_was_absent path=$path preserved_if_now_exists" }
    }
  } catch {
    Write-KojoLog "RESTORE_REGISTRY_FAILED path=$($Entry.Path) name=$($Entry.Name) error=$($_.Exception.Message)" 'WARN'
  }
}

function Restore-TaskState {
  param($Entry)
  try {
    $path = [string]$Entry.TaskPath
    $name = [string]$Entry.TaskName
    $state = [string]$Entry.State
    if ($state -eq 'Disabled') {
      Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue | Out-Null
      Write-KojoLog "DEBLOAT_RESTORE_TASK disabled=$path$name"
    } else {
      Enable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue | Out-Null
      Write-KojoLog "DEBLOAT_RESTORE_TASK enabled=$path$name"
    }
  } catch {
    Write-KojoLog "RESTORE_TASK_FAILED path=$($Entry.TaskPath) name=$($Entry.TaskName) error=$($_.Exception.Message)" 'WARN'
  }
}

function Reinstall-OneDriveBestEffort {
  if ($SkipOneDriveReinstall) { return }
  Write-KojoLog 'DEBLOAT_RESTORE_ONEDRIVE start'
  $candidates = @(
    "$env:SystemRoot\System32\OneDriveSetup.exe",
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
  ) | Where-Object { Test-Path $_ }
  foreach ($setup in $candidates) {
    try {
      Write-KojoLog "ONEDRIVE_REINSTALL setup=$setup"
      $p = Start-Process -FilePath $setup -ArgumentList '/install' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
      Write-KojoLog "ONEDRIVE_REINSTALL_EXIT code=$($p.ExitCode)"
      break
    } catch { Write-KojoLog "ONEDRIVE_REINSTALL_FAILED setup=$setup error=$($_.Exception.Message)" 'WARN' }
  }
  try { Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -Name 'DisableFileSyncNGSC' -ErrorAction SilentlyContinue } catch {}
}

function Restore-AppxBestEffort {
  param($Manifest)
  Write-KojoLog 'DEBLOAT_RESTORE_APPX_BEST_EFFORT start'
  if (-not $Manifest.appx) { return }
  foreach ($pkg in $Manifest.appx) {
    try {
      $name = [string]$pkg.Name
      $installLocation = [string]$pkg.InstallLocation
      if ([string]::IsNullOrWhiteSpace($installLocation)) { continue }
      $appxManifest = Join-Path $installLocation 'AppxManifest.xml'
      if (Test-Path $appxManifest) {
        Write-KojoLog "APPX_REREGISTER name=$name"
        Add-AppxPackage -DisableDevelopmentMode -Register $appxManifest -ErrorAction SilentlyContinue
      }
    } catch { Write-KojoLog "APPX_REREGISTER_FAILED name=$($pkg.Name) error=$($_.Exception.Message)" 'WARN' }
  }
}

if (-not (Test-IsAdmin)) {
  Write-Error 'Kojo Extreme Gaming Debloat restore must be run as Administrator.'
  exit 1
}

if (-not $ManifestPath) { $ManifestPath = Get-LatestManifestPath }
if (-not $ManifestPath -or -not (Test-Path $ManifestPath)) {
  Write-Error 'No Kojo debloat manifest found. Restore cannot continue.'
  exit 2
}

Write-KojoLog "DEBLOAT_RESTORE_START manifest=$ManifestPath"

if (-not $Force) {
  $answer = Read-Host 'Restore Kojo Debloat using this manifest? Type YES to continue'
  if ($answer -ne 'YES') {
    Write-KojoLog 'DEBLOAT_RESTORE_ABORTED_BY_USER'
    exit 0
  }
}

$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

# Restore services exactly from manifest where possible.
try {
  $serviceProps = $Manifest.services.PSObject.Properties
  foreach ($prop in $serviceProps) {
    $svcName = $prop.Name
    $svcData = $prop.Value
    $startup = Convert-StartModeToStartupType -StartMode ([string]$svcData.StartMode)
    Set-ServiceStartModeSafe -Name $svcName -StartupType $startup | Out-Null
  }
} catch { Write-KojoLog "RESTORE_SERVICES_BLOCK_FAILED error=$($_.Exception.Message)" 'WARN' }

# Restore tasks.
try { foreach ($task in $Manifest.tasks) { Restore-TaskState -Entry $task } } catch { Write-KojoLog "RESTORE_TASKS_BLOCK_FAILED error=$($_.Exception.Message)" 'WARN' }

# Restore registry.
try { foreach ($reg in $Manifest.registry) { Restore-RegistryValue -Entry $reg } } catch { Write-KojoLog "RESTORE_REGISTRY_BLOCK_FAILED error=$($_.Exception.Message)" 'WARN' }

# Restore hibernation if it seemed enabled before.
try {
  if ($Manifest.hibernation -and $Manifest.hibernation.SeemsEnabled -eq $true) {
    Write-KojoLog 'DEBLOAT_RESTORE_HIBERNATION_ON'
    powercfg /hibernate on | Out-Null
  } else {
    Write-KojoLog 'DEBLOAT_RESTORE_HIBERNATION previous_not_enabled_or_unknown'
  }
} catch { Write-KojoLog "RESTORE_HIBERNATION_FAILED error=$($_.Exception.Message)" 'WARN' }

# Windows Update unpause / restore policy keys from manifest already handled by registry restore.
try {
  Write-KojoLog 'DEBLOAT_RESTORE_WINDOWS_UPDATE ensure_services_manual_or_previous'
  # Service values were restored from manifest above. Trigger policy refresh quietly.
  gpupdate /target:computer /force | Out-Null
} catch { Write-KojoLog "RESTORE_WU_GPUPDATE_FAILED error=$($_.Exception.Message)" 'WARN' }

# Restore AppX where package source still exists.
Restore-AppxBestEffort -Manifest $Manifest

# Best effort OneDrive reinstall requested by user mode because enable removes OneDrive.
Reinstall-OneDriveBestEffort

# Mark state restored.
$statePath = Join-Path $BackupRoot 'current-state.json'
$state = [ordered]@{
  applied = $false
  restoredAt = (Get-Date).ToString('o')
  restoredFrom = $ManifestPath
}
$state | ConvertTo-Json -Depth 6 | Set-Content -Path $statePath -Encoding UTF8

Write-KojoLog 'DEBLOAT_RESTORE_RESULT ok=true'
Write-Host ''
Write-Host 'Kojo Extreme Gaming Debloat restore completed.' -ForegroundColor Green
Write-Host 'Some removed AppX packages or OneDrive components may require Microsoft Store / winget / Windows Update to fully reinstall.' -ForegroundColor Yellow
Write-Host 'A restart is recommended.' -ForegroundColor Yellow
exit 0
