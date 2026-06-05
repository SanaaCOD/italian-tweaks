# PurpleBoost - Debloat DISABLE / Rollback
# Remet l'inverse du Debloat_Kojo.ps1 autant que possible.
# À lancer en administrateur.

$ErrorActionPreference = "Continue"

Write-Host "=== DEBLOAT ROLLBACK START ===" -ForegroundColor Cyan

# --------------------------------------------------
# 1. Re-enable services
# --------------------------------------------------

Write-Host "Restoring services..."

$serviceDefaults = @{
    "DiagTrack"       = "Automatic"
    "dmwappushservice" = "Manual"
    "RetailDemo"     = "Manual"
    "Fax"            = "Manual"
    "MapsBroker"     = "Automatic"
    "WMPNetworkSvc"  = "Manual"
    "XblAuthManager" = "Manual"
    "XblGameSave"    = "Manual"
    "XboxNetApiSvc"  = "Manual"
    "XboxGipSvc"     = "Manual"
    "WerSvc"         = "Manual"
}

foreach ($svc in $serviceDefaults.Keys) {
    try {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue

        if ($null -ne $service) {
            Set-Service -Name $svc -StartupType $serviceDefaults[$svc] -ErrorAction SilentlyContinue

            if ($serviceDefaults[$svc] -eq "Automatic") {
                Start-Service -Name $svc -ErrorAction SilentlyContinue
            }

            Write-Host "Service restored: $svc -> $($serviceDefaults[$svc])"
        }
    }
    catch {}
}

# --------------------------------------------------
# 2. Re-enable scheduled tasks
# --------------------------------------------------

Write-Host "Restoring scheduled tasks..."

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
    try {
        schtasks.exe /Change /TN $task /Enable 2>$null | Out-Null
        Write-Host "Task enabled: $task"
    }
    catch {}
}

# --------------------------------------------------
# 3. Restore registry defaults
# --------------------------------------------------

Write-Host "Restoring registry values..."

try {
    reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 0 /f | Out-Null
}
catch {}

try {
    # Windows default commonly used value
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 10 /f | Out-Null
}
catch {}

try {
    # Windows default commonly used value
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 20 /f | Out-Null
}
catch {}

# --------------------------------------------------
# 4. Re-enable hibernation
# --------------------------------------------------

Write-Host "Re-enabling hibernation..."

try {
    powercfg.exe -h on
}
catch {}

# --------------------------------------------------
# 5. Try reinstall OneDrive
# --------------------------------------------------

Write-Host "Trying to reinstall OneDrive if installer exists..."

$oneDriveInstallers = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
    "$env:SystemRoot\System32\OneDriveSetup.exe"
)

foreach ($installer in $oneDriveInstallers) {
    if (Test-Path $installer) {
        try {
            Start-Process -FilePath $installer -ArgumentList "/install" -Wait -ErrorAction SilentlyContinue
            Write-Host "OneDrive installer launched: $installer"
            break
        }
        catch {}
    }
}

# --------------------------------------------------
# 6. Try re-register removed UWP apps if still present locally
# --------------------------------------------------

Write-Host "Trying to re-register removed UWP apps if packages still exist..."

$appPatterns = @(
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

foreach ($pattern in $appPatterns) {
    try {
        $packages = Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue

        foreach ($pkg in $packages) {
            $manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"

            if (Test-Path $manifest) {
                Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction SilentlyContinue
                Write-Host "Re-registered: $($pkg.Name)"
            }
        }
    }
    catch {}
}

Write-Host ""
Write-Host "=== DEBLOAT ROLLBACK COMPLETE ===" -ForegroundColor Green
Write-Host "REBOOT REQUIRED." -ForegroundColor Yellow