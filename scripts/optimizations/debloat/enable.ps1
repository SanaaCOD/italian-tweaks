<#
.SYNOPSIS
  Kojo Extreme Gaming Debloat - enable.ps1

.DESCRIPTION
  Extreme but controlled Windows debloat for gaming performance.
  - Removes OneDrive cleanly.
  - Pauses Windows Update instead of destroying it.
  - Removes/deprovisions consumer bloatware.
  - Disables telemetry/background tasks/services while protecting gaming-critical components.
  - Creates a full backup manifest before changing anything.

.NOTES
  Run as Administrator.
  Network/TCP settings are intentionally NOT modified here. Kojo Connexion/TCP Optimizer owns that area.
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [switch]$Force,
  [switch]$NoRestorePoint,
  [switch]$KeepOneDrive,
  [switch]$KeepHibernation,
  [int]$PauseWindowsUpdateDays = 35
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:WarningCount = 0
$script:ErrorCount = 0

# -----------------------------
# Paths / logging
# -----------------------------
$KojoRoot = Join-Path $env:ProgramData 'Kojo'
$BackupRoot = Join-Path $KojoRoot 'Backups\Debloat'
$LogRoot = Join-Path $KojoRoot 'Logs'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $BackupRoot $Timestamp
$ManifestPath = Join-Path $BackupDir 'debloat-manifest.json'
$LogPath = Join-Path $LogRoot 'debloat.log'

function Write-KojoLog {
  param([string]$Message, [string]$Level = 'INFO')
  if ($Level -eq 'WARN') { $script:WarningCount++ }
  elseif ($Level -eq 'ERROR') { $script:ErrorCount++ }
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  if ($script:LogReady) {
    try {
      Add-Content -Path $LogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
      $script:LogReady = $false
    }
  }
  Write-Host $line
}

function Write-DebloatFatalResult {
  param([string]$ErrorMessage)
  $msg = "DEBLOAT_RESULT success=false fatal=true error=$ErrorMessage"
  try {
    if ($script:LogReady) { Add-Content -Path $LogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [FATAL] $msg" -Encoding UTF8 }
  } catch { }
  Write-Host $msg
}

$script:LogReady = $false
try {
  New-Item -ItemType Directory -Force -Path $KojoRoot, $BackupDir, $LogRoot | Out-Null
  $script:LogReady = $true
} catch {
  Write-DebloatFatalResult -ErrorMessage "create_directories_failed $($_.Exception.Message)"
  exit 1
}

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ServiceStartModeSafe {
  param([string]$Name)
  try {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
    if ($null -eq $svc) { return $null }
    return [ordered]@{
      Name      = $svc.Name
      DisplayName = $svc.DisplayName
      StartMode = $svc.StartMode
      State     = $svc.State
      PathName  = $svc.PathName
    }
  } catch { return $null }
}

function Set-ServiceStartModeSafe {
  param(
    [string]$Name,
    [ValidateSet('Automatic','Manual','Disabled')][string]$StartupType,
    [switch]$Stop
  )
  $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if ($null -eq $svc) { return $false }
  try {
    Write-KojoLog "DEBLOAT_SERVICE_CHANGE name=$Name startup=$StartupType stop=$($Stop.IsPresent)"
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
    if ($Stop -and $svc.Status -ne 'Stopped') {
      Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    }
    return $true
  } catch {
    Write-KojoLog "SERVICE_CHANGE_FAILED name=$Name error=$($_.Exception.Message)" 'WARN'
    return $false
  }
}

function Backup-RegistryValue {
  param([string]$Path, [string]$Name)
  $exists = Test-Path $Path
  $value = $null
  $hasValue = $false
  if ($exists) {
    try {
      $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
      $value = $prop.$Name
      $hasValue = $true
    } catch { }
  }
  return [ordered]@{ Path=$Path; Name=$Name; KeyExists=$exists; ValueExists=$hasValue; Value=$value }
}

function Set-RegistryValueSafe {
  param(
    [string]$Path,
    [string]$Name,
    [object]$Value,
    [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord
  )
  try {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-KojoLog "DEBLOAT_REGISTRY_CHANGE path=$Path name=$Name value=$Value"
    return $true
  } catch {
    Write-KojoLog "REGISTRY_CHANGE_FAILED path=$Path name=$Name error=$($_.Exception.Message)" 'WARN'
    return $false
  }
}

function Disable-TaskSafe {
  param([string]$TaskPath, [string]$TaskName)
  try {
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
    if ($task.State -ne 'Disabled') {
      Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
    }
    Write-KojoLog "DEBLOAT_TASK_CHANGE disabled=$TaskPath$TaskName"
    return $true
  } catch {
    Write-KojoLog "TASK_DISABLE_SKIPPED path=$TaskPath name=$TaskName error=$($_.Exception.Message)" 'WARN'
    return $false
  }
}

function Remove-AppxLikeSafe {
  param([string[]]$Patterns)
  $removed = @()
  foreach ($pattern in $Patterns) {
    try {
      $packages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern -or $_.PackageFullName -like $pattern }
      foreach ($pkg in $packages) {
        try {
          Write-KojoLog "DEBLOAT_APPX_REMOVE package=$($pkg.PackageFullName)"
          Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
          $removed += $pkg.PackageFullName
        } catch { Write-KojoLog "APPX_REMOVE_FAILED package=$($pkg.PackageFullName) error=$($_.Exception.Message)" 'WARN' }
      }
      $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pattern -or $_.PackageName -like $pattern }
      foreach ($p in $prov) {
        try {
          Write-KojoLog "DEBLOAT_APPX_DEPROVISION package=$($p.PackageName)"
          Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue | Out-Null
        } catch { Write-KojoLog "APPX_DEPROVISION_FAILED package=$($p.PackageName) error=$($_.Exception.Message)" 'WARN' }
      }
    } catch { Write-KojoLog "APPX_PATTERN_FAILED pattern=$pattern error=$($_.Exception.Message)" 'WARN' }
  }
  return $removed
}

function Remove-CapabilitySafe {
  param([string[]]$Patterns)
  $removed = @()
  foreach ($pattern in $Patterns) {
    try {
      $caps = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern -and $_.State -eq 'Installed' }
      foreach ($cap in $caps) {
        try {
          Write-KojoLog "DEBLOAT_CAPABILITY_REMOVE name=$($cap.Name)"
          Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction SilentlyContinue | Out-Null
          $removed += $cap.Name
        } catch { Write-KojoLog "CAPABILITY_REMOVE_FAILED name=$($cap.Name) error=$($_.Exception.Message)" 'WARN' }
      }
    } catch { Write-KojoLog "CAPABILITY_PATTERN_FAILED pattern=$pattern error=$($_.Exception.Message)" 'WARN' }
  }
  return $removed
}

function Get-HibernationState {
  try {
    $out = powercfg /a 2>$null | Out-String
    return [ordered]@{ Raw=$out; SeemsEnabled=($out -match 'Hibernation') -and ($out -notmatch 'has not been enabled') }
  } catch { return [ordered]@{ Raw=$null; SeemsEnabled=$null } }
}

function Uninstall-OneDriveSafe {
  Write-KojoLog 'DEBLOAT_ONEDRIVE_REMOVE start'
  try { Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue } catch {}

  $candidates = @(
    "$env:SystemRoot\System32\OneDriveSetup.exe",
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
  ) | Where-Object { Test-Path $_ }

  foreach ($setup in $candidates) {
    try {
      Write-KojoLog "ONEDRIVE_UNINSTALL setup=$setup"
      $p = Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
      Write-KojoLog "ONEDRIVE_UNINSTALL_EXIT code=$($p.ExitCode)"
      break
    } catch { Write-KojoLog "ONEDRIVE_UNINSTALL_FAILED setup=$setup error=$($_.Exception.Message)" 'WARN' }
  }

  $runPaths = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
  )
  foreach ($rp in $runPaths) {
    try { Remove-ItemProperty -Path $rp -Name 'OneDrive' -ErrorAction SilentlyContinue } catch {}
  }

  # Hide Explorer integration and block sync client via policy.
  Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -Name 'DisableFileSyncNGSC' -Value 1 | Out-Null
  Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Value 0 | Out-Null

  $clsidPaths = @(
    'HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
    'HKCR:\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
  )
  foreach ($path in $clsidPaths) {
    if (Test-Path $path) {
      try { Set-ItemProperty -Path $path -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -ErrorAction SilentlyContinue } catch {}
    }
  }
}

function Pause-WindowsUpdateSafe {
  param([int]$Days)
  if ($Days -lt 1) { $Days = 35 }
  if ($Days -gt 35) { $Days = 35 } # Windows UX pause is normally capped at 35 days.

  $now = Get-Date
  $expiry = $now.AddDays($Days)
  $nowIso = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $expiryIso = $expiry.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

  Write-KojoLog "DEBLOAT_WINDOWS_UPDATE_PAUSE days=$Days expiry=$expiryIso"

  $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
  Set-RegistryValueSafe -Path $ux -Name 'PauseUpdatesStartTime' -Value $nowIso -Type String | Out-Null
  Set-RegistryValueSafe -Path $ux -Name 'PauseUpdatesExpiryTime' -Value $expiryIso -Type String | Out-Null
  Set-RegistryValueSafe -Path $ux -Name 'PauseFeatureUpdatesStartTime' -Value $nowIso -Type String | Out-Null
  Set-RegistryValueSafe -Path $ux -Name 'PauseFeatureUpdatesEndTime' -Value $expiryIso -Type String | Out-Null
  Set-RegistryValueSafe -Path $ux -Name 'PauseQualityUpdatesStartTime' -Value $nowIso -Type String | Out-Null
  Set-RegistryValueSafe -Path $ux -Name 'PauseQualityUpdatesEndTime' -Value $expiryIso -Type String | Out-Null

  $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
  Set-RegistryValueSafe -Path $wu -Name 'DeferFeatureUpdates' -Value 1 | Out-Null
  Set-RegistryValueSafe -Path $wu -Name 'DeferFeatureUpdatesPeriodInDays' -Value 365 | Out-Null
  Set-RegistryValueSafe -Path $wu -Name 'DeferQualityUpdates' -Value 1 | Out-Null
  Set-RegistryValueSafe -Path $wu -Name 'DeferQualityUpdatesPeriodInDays' -Value 30 | Out-Null

  # Keep WU alive but not eager.
  Set-ServiceStartModeSafe -Name 'wuauserv' -StartupType Manual | Out-Null
  Set-ServiceStartModeSafe -Name 'BITS' -StartupType Manual | Out-Null
  Set-ServiceStartModeSafe -Name 'UsoSvc' -StartupType Manual | Out-Null
  Set-ServiceStartModeSafe -Name 'DoSvc' -StartupType Manual | Out-Null
}

# -----------------------------
# Main
# -----------------------------
if (-not (Test-IsAdmin)) {
  Write-KojoLog 'DEBLOAT_RESULT success=false fatal=true error=not_administrator' 'ERROR'
  Write-Error 'Kojo Extreme Gaming Debloat must be run as Administrator.'
  exit 1
}

Write-KojoLog 'DEBLOAT_START profile=extreme-controlled'

if (-not $Force) {
  Write-KojoLog 'Confirmation required. Use -Force to run non-interactively.' 'WARN'
  $answer = Read-Host 'Apply Kojo Extreme Gaming Debloat now? Type YES to continue'
  if ($answer -ne 'YES') {
    Write-KojoLog 'DEBLOAT_ABORTED_BY_USER'
    exit 0
  }
}

# Target lists.
$DisableServices = @('DiagTrack','dmwappushservice','RetailDemo','MapsBroker','Fax','RemoteRegistry','WerSvc','PcaSvc')
$ManualServices  = @('WSearch','SysMain','BITS','wuauserv','UsoSvc','DoSvc','XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc','TabletInputService','Spooler')
$ProtectedServices = @('WinDefend','MpsSvc','BFE','EventLog','RpcSs','DcomLaunch','PlugPlay','Power','AudioEndpointBuilder','Audiosrv','Dhcp','Dnscache','NlaSvc','netprofm','WlanSvc','CryptSvc','msiserver','Winmgmt','Schedule','hidserv','DeviceInstall','Appinfo')

$TasksToDisable = @(
  @{Path='\Microsoft\Windows\Application Experience\'; Name='Microsoft Compatibility Appraiser'},
  @{Path='\Microsoft\Windows\Application Experience\'; Name='ProgramDataUpdater'},
  @{Path='\Microsoft\Windows\Application Experience\'; Name='StartupAppTask'},
  @{Path='\Microsoft\Windows\Customer Experience Improvement Program\'; Name='Consolidator'},
  @{Path='\Microsoft\Windows\Customer Experience Improvement Program\'; Name='UsbCeip'},
  @{Path='\Microsoft\Windows\Customer Experience Improvement Program\'; Name='KernelCeipTask'},
  @{Path='\Microsoft\Windows\DiskDiagnostic\'; Name='Microsoft-Windows-DiskDiagnosticDataCollector'},
  @{Path='\Microsoft\Windows\Feedback\Siuf\'; Name='DmClient'},
  @{Path='\Microsoft\Windows\Feedback\Siuf\'; Name='DmClientOnScenarioDownload'},
  @{Path='\Microsoft\Windows\Maps\'; Name='MapsToastTask'},
  @{Path='\Microsoft\Windows\Maps\'; Name='MapsUpdateTask'}
)

$AppxRemovePatterns = @(
  '*Clipchamp*','*MicrosoftTeams*','*Teams*','*MicrosoftSolitaireCollection*','*People*','*MixedReality*',
  '*BingNews*','*BingWeather*','*GetHelp*','*Getstarted*','*FeedbackHub*','*MicrosoftOfficeHub*',
  '*ZuneMusic*','*ZuneVideo*','*YourPhone*','*WindowsMaps*','*Todos*','*PowerAutomateDesktop*',
  '*Cortana*','*WebExperience*','*XboxGamingOverlay*','*XboxGameOverlay*','*XboxSpeechToTextOverlay*'
)

$CapabilitiesRemovePatterns = @(
  'Print.Fax.Scan*',
  'App.StepsRecorder*',
  'Browser.InternetExplorer*',
  'Microsoft.Windows.WordPad*',
  'XPS.Viewer*',
  'MathRecognizer*',
  'App.Support.QuickAssist*'
)

$RegistryTargets = @(
  @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name='AppCaptureEnabled'; Value=0; Type='DWord'},
  @{Path='HKCU:\System\GameConfigStore'; Name='GameDVR_Enabled'; Value=0; Type='DWord'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name='AllowGameDVR'; Value=0; Type='DWord'},
  @{Path='HKCU:\Software\Microsoft\GameBar'; Name='AllowAutoGameMode'; Value=1; Type='DWord'},
  @{Path='HKCU:\Software\Microsoft\GameBar'; Name='ShowStartupPanel'; Value=0; Type='DWord'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsConsumerFeatures'; Value=1; Type='DWord'},
  @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338388Enabled'; Value=0; Type='DWord'},
  @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338389Enabled'; Value=0; Type='DWord'},
  @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SilentInstalledAppsEnabled'; Value=0; Type='DWord'},
  @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name='Enabled'; Value=0; Type='DWord'},
  @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='TaskbarDa'; Value=0; Type='DWord'},
  @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowCopilotButton'; Value=0; Type='DWord'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name='TurnOffWindowsCopilot'; Value=1; Type='DWord'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; Value=0; Type='DWord'},
  @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'; Name='PowerThrottlingOff'; Value=1; Type='DWord'}
)

# Backup everything before action.
$Manifest = [ordered]@{
  schema = 'kojo.extreme-debloat.v1'
  createdAt = (Get-Date).ToString('o')
  profile = 'extreme-controlled'
  backupDir = $BackupDir
  logPath = $LogPath
  services = @{}
  tasks = @()
  registry = @()
  appx = @()
  provisionedAppx = @()
  capabilities = @()
  hibernation = $null
  oneDrive = @{}
  actions = @()
  warnings = @()
}

Write-KojoLog 'DEBLOAT_BACKUP_CREATED begin'

foreach ($svcName in ($DisableServices + $ManualServices + $ProtectedServices | Select-Object -Unique)) {
  $s = Get-ServiceStartModeSafe -Name $svcName
  if ($null -ne $s) { $Manifest.services[$svcName] = $s }
}

foreach ($taskRef in $TasksToDisable) {
  try {
    $task = Get-ScheduledTask -TaskPath $taskRef.Path -TaskName $taskRef.Name -ErrorAction Stop
    $Manifest.tasks += [ordered]@{ TaskPath=$task.TaskPath; TaskName=$task.TaskName; State=[string]$task.State }
  } catch { }
}

foreach ($reg in $RegistryTargets) {
  $Manifest.registry += Backup-RegistryValue -Path $reg.Path -Name $reg.Name
}
# Extra backup for Windows Update / OneDrive keys touched by functions.
$extraRegBackup = @(
  @{Path='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name='PauseUpdatesStartTime'},
  @{Path='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name='PauseUpdatesExpiryTime'},
  @{Path='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name='PauseFeatureUpdatesStartTime'},
  @{Path='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name='PauseFeatureUpdatesEndTime'},
  @{Path='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name='PauseQualityUpdatesStartTime'},
  @{Path='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name='PauseQualityUpdatesEndTime'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='DeferFeatureUpdates'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='DeferFeatureUpdatesPeriodInDays'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='DeferQualityUpdates'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name='DeferQualityUpdatesPeriodInDays'},
  @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; Name='DisableFileSyncNGSC'},
  @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='ShowSyncProviderNotifications'}
)
foreach ($reg in $extraRegBackup) { $Manifest.registry += Backup-RegistryValue -Path $reg.Path -Name $reg.Name }

try { $Manifest.appx = @(Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, InstallLocation, PackageFamilyName) } catch {}
try { $Manifest.provisionedAppx = @(Get-AppxProvisionedPackage -Online | Select-Object DisplayName, PackageName) } catch {}
try { $Manifest.capabilities = @(Get-WindowsCapability -Online | Where-Object {$_.State -eq 'Installed'} | Select-Object Name, State) } catch {}
$Manifest.hibernation = Get-HibernationState
$Manifest.oneDrive = [ordered]@{
  UserPathExists = (Test-Path (Join-Path $env:USERPROFILE 'OneDrive'))
  SetupSystem32 = (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe")
  SetupSysWOW64 = (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")
  SetupLocal = (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe")
}

try {
  $Manifest | ConvertTo-Json -Depth 12 | Set-Content -Path $ManifestPath -Encoding UTF8
  Write-KojoLog "DEBLOAT_BACKUP_CREATED manifest=$ManifestPath"
} catch {
  Write-KojoLog "DEBLOAT_RESULT success=false fatal=true error=backup_manifest_failed $($_.Exception.Message)" 'ERROR'
  exit 1
}

# Non-critical apply phase: warnings must not terminate the script.
$ErrorActionPreference = 'Continue'
$removedAppx = @()
$removedCaps = @()

try {
  # Restore point.
  if (-not $NoRestorePoint) {
    try {
      Write-KojoLog 'DEBLOAT_RESTORE_POINT_CREATE start'
      Checkpoint-Computer -Description 'Kojo Extreme Gaming Debloat' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
      Write-KojoLog 'DEBLOAT_RESTORE_POINT_CREATE ok'
    } catch {
      Write-KojoLog "RESTORE_POINT_FAILED error=$($_.Exception.Message)" 'WARN'
    }
  }

  # Apply services.
  foreach ($svcName in $DisableServices) {
    if ($ProtectedServices -contains $svcName) { continue }
    Set-ServiceStartModeSafe -Name $svcName -StartupType Disabled -Stop | Out-Null
  }
  foreach ($svcName in $ManualServices) {
    if ($ProtectedServices -contains $svcName) { continue }
    Set-ServiceStartModeSafe -Name $svcName -StartupType Manual | Out-Null
  }

  # Disable tasks.
  foreach ($taskRef in $TasksToDisable) { Disable-TaskSafe -TaskPath $taskRef.Path -TaskName $taskRef.Name | Out-Null }

  # Registry tweaks.
  foreach ($reg in $RegistryTargets) {
    $kind = [Microsoft.Win32.RegistryValueKind]::$($reg.Type)
    Set-RegistryValueSafe -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $kind | Out-Null
  }

  # Remove bloat AppX and capabilities.
  $removedAppx = Remove-AppxLikeSafe -Patterns $AppxRemovePatterns
  $removedCaps = Remove-CapabilitySafe -Patterns $CapabilitiesRemovePatterns

  # OneDrive removal requested for this mode unless explicitly kept.
  if (-not $KeepOneDrive) { Uninstall-OneDriveSafe }

  # Windows Update paused, not destroyed.
  Pause-WindowsUpdateSafe -Days $PauseWindowsUpdateDays

  # Hibernation / fast startup off unless kept.
  if (-not $KeepHibernation) {
    try {
      Write-KojoLog 'DEBLOAT_HIBERNATION_OFF'
      powercfg /hibernate off | Out-Null
    } catch { Write-KojoLog "HIBERNATION_OFF_FAILED error=$($_.Exception.Message)" 'WARN' }
  }

  # NTFS / filesystem tweaks.
  try { Write-KojoLog 'DEBLOAT_NTFS_DISABLE_LAST_ACCESS'; fsutil behavior set disablelastaccess 1 | Out-Null } catch { Write-KojoLog "NTFS_LAST_ACCESS_FAILED error=$($_.Exception.Message)" 'WARN' }
  try { Write-KojoLog 'DEBLOAT_NTFS_DISABLE_8DOT3'; fsutil behavior set disable8dot3 1 | Out-Null } catch { Write-KojoLog "NTFS_8DOT3_FAILED error=$($_.Exception.Message)" 'WARN' }

  # Cleanup (per-item to avoid pipeline terminating errors under strict mode).
  $cleanupTargets = @($env:TEMP, "$env:WINDIR\Temp", "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache")
  foreach ($target in $cleanupTargets) {
    if (-not (Test-Path $target)) { continue }
    try {
      Write-KojoLog "DEBLOAT_CLEANUP path=$target"
      $items = @(Get-ChildItem -Path $target -Force -ErrorAction SilentlyContinue)
      foreach ($item in $items) {
        try {
          Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
          Write-KojoLog "CLEANUP_ITEM_FAILED path=$($item.FullName) error=$($_.Exception.Message)" 'WARN'
        }
      }
    } catch {
      Write-KojoLog "CLEANUP_FAILED path=$target error=$($_.Exception.Message)" 'WARN'
    }
  }
} catch {
  Write-KojoLog "DEBLOAT_APPLY_UNEXPECTED error=$($_.Exception.Message)" 'WARN'
}

# Mark state (non-blocking).
$StatePath = Join-Path $BackupRoot 'current-state.json'
$state = [ordered]@{
  applied = $true
  profile = 'extreme-controlled'
  appliedAt = (Get-Date).ToString('o')
  manifestPath = $ManifestPath
  version = '1.0'
}
try {
  $state | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Encoding UTF8
} catch {
  Write-KojoLog "STATE_WRITE_FAILED error=$($_.Exception.Message)" 'WARN'
}

Write-KojoLog "DEBLOAT_RESULT success=true warnings=$($script:WarningCount) errors=$($script:ErrorCount) manifest=$ManifestPath removedAppx=$($removedAppx.Count) removedCapabilities=$($removedCaps.Count)"
Write-Host ''
Write-Host 'Kojo Extreme Gaming Debloat applied.' -ForegroundColor Green
Write-Host "Backup manifest: $ManifestPath" -ForegroundColor Cyan
Write-Host 'A restart is recommended.' -ForegroundColor Yellow
exit 0
