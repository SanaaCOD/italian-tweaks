Write-Host "=== DEBLOAT PRO V1 START ===" -ForegroundColor Cyan

# --------------------------------------------------
# 1. Restore Point
# --------------------------------------------------

Write-Host "Creating restore point..."

Enable-ComputerRestore -Drive "C:\"
Checkpoint-Computer -Description "Before_Debloat_Pro_V1" -RestorePointType "MODIFY_SETTINGS"

# --------------------------------------------------
# 2. Remove OneDrive
# --------------------------------------------------

Write-Host "Removing OneDrive..."

taskkill /f /im OneDrive.exe 2>$null

Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" "/uninstall" -NoNewWindow -Wait -ErrorAction SilentlyContinue
Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" "/uninstall" -NoNewWindow -Wait -ErrorAction SilentlyContinue

Remove-Item "$env:USERPROFILE\OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$env:PROGRAMDATA\Microsoft OneDrive" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "C:\OneDriveTemp" -Force -Recurse -ErrorAction SilentlyContinue

# --------------------------------------------------
# 3. Remove Useless Apps
# --------------------------------------------------

Write-Host "Removing UWP bloat..."

$apps = @(
"*Xbox*",
"*GamingApp*",
"*GetHelp*",
"*Getstarted*",
"*Teams*",
"*Clipchamp*",
"*MicrosoftSolitaireCollection*",
"*People*",
"*ZuneMusic*",
"*ZuneVideo*",
"*BingWeather*",
"*MicrosoftOfficeHub*",
"*MicrosoftTeams*",
"*WindowsFeedbackHub*",
"*YourPhone*",
"*MixedReality*",
"*Widgets*",
"*Copilot*"
)

foreach ($app in $apps) {
    Get-AppxPackage -AllUsers $app | Remove-AppxPackage -ErrorAction SilentlyContinue
}

# --------------------------------------------------
# 4. Disable Telemetry Services
# --------------------------------------------------

Write-Host "Disabling telemetry services..."

$services = @(
"DiagTrack",
"dmwappushservice",
"RetailDemo",
"Fax",
"MapsBroker",
"WMPNetworkSvc",
"XblAuthManager",
"XblGameSave",
"XboxNetApiSvc",
"XboxGipSvc",
"WerSvc"
)

foreach ($svc in $services) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
}

# --------------------------------------------------
# 5. Disable Scheduled Tasks (Telemetry)
# --------------------------------------------------

Write-Host "Disabling scheduled tasks..."

$tasks = @(
"\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
"\Microsoft\Windows\Application Experience\ProgramDataUpdater",
"\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
"\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
"\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
"\Microsoft\Windows\Feedback\Siuf\DmClient",
"\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
)

foreach ($task in $tasks) {
    schtasks /Change /TN $task /Disable 2>$null
}

# --------------------------------------------------
# 6. Registry Performance Tweaks
# --------------------------------------------------

Write-Host "Applying performance registry tweaks..."

reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 0 /f

# --------------------------------------------------
# 7. Disable Hibernation
# --------------------------------------------------

Write-Host "Disabling hibernation..."

powercfg -h off

# --------------------------------------------------
# 8. Startup Cleanup
# --------------------------------------------------

Write-Host "Cleaning startup..."

Get-CimInstance Win32_StartupCommand | Select Name, Command, Location

Write-Host "Review startup apps manually via Task Manager > Startup"

# --------------------------------------------------
# 9. Flush Temp
# --------------------------------------------------

Write-Host "Cleaning temp files..."

Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# --------------------------------------------------
# END
# --------------------------------------------------

Write-Host ""
Write-Host "=== DEBLOAT PRO V1 COMPLETE ===" -ForegroundColor Green
Write-Host "REBOOT REQUIRED." -ForegroundColor Yellow
Write-Host "Check process count after reboot with:"
Write-Host "Get-Process | Measure-Object"