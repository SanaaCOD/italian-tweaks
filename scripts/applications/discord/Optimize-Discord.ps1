$ErrorActionPreference = "Stop"

function Write-AppLog {
    param([string]$Message)
    Write-Output $Message
}

function Set-JsonPropertyIfExists {
    param(
        [object]$Object,
        [string[]]$Names,
        $Value
    )

    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            $Object.$name = $Value
            return $true
        }
    }

    return $false
}

try {
    $wasRunning = $false
    $discordProcs = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    if ($discordProcs) {
        $wasRunning = $true
        $discordProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRoot = Join-Path $env:ProgramData "Kojo\Backups\Applications\Discord\$timestamp"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $settingsPath = Join-Path $env:APPDATA "Discord\settings.json"
    if (-not (Test-Path $settingsPath)) {
        Write-AppLog "DISCORD_SETTINGS_NOT_FOUND"
        exit 0
    }

    Copy-Item -Path $settingsPath -Destination (Join-Path $backupRoot "settings.json") -Force
    $settings = Get-Content -Path $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Set-JsonPropertyIfExists -Object $settings -Names @('OPEN_ON_STARTUP', 'openOnStartup') -Value $false | Out-Null
    Set-JsonPropertyIfExists -Object $settings -Names @('MINIMIZE_TO_TRAY', 'minimizeToTray') -Value $true | Out-Null

    if (Set-JsonPropertyIfExists -Object $settings -Names @('BACKGROUND_COLOR', 'backgroundColor') -Value '#000000') {
        Write-AppLog "DISCORD_BACKGROUND_COLOR_UPDATED"
    }

    if (-not (Set-JsonPropertyIfExists -Object $settings -Names @(
            'HARDWARE_ACCELERATION', 'hardwareAcceleration', 'enableHardwareAcceleration'
        ) -Value $false)) {
        Write-AppLog "DISCORD_HW_ACCEL_KEY_NOT_FOUND"
    }

    if (-not (Set-JsonPropertyIfExists -Object $settings -Names @(
            'ENABLE_OVERLAY', 'enableOverlay', 'overlayEnabled', 'gameOverlay'
        ) -Value $false)) {
        Write-AppLog "DISCORD_OVERLAY_SETTING_NOT_FOUND"
    }

    $settings | ConvertTo-Json -Depth 100 | Set-Content -Path $settingsPath -Encoding UTF8 -Force
    Write-AppLog "DISCORD_SETTINGS_OPTIMIZED"

    if ($wasRunning) {
        $updateExe = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
        if (Test-Path $updateExe) {
            Start-Process -FilePath $updateExe -ArgumentList @('--processStart', 'Discord.exe') -WindowStyle Hidden
            Write-AppLog "DISCORD_RELAUNCHED"
        }
    }

    exit 0
}
catch {
    Write-AppLog ("DISCORD_OPTIMIZE_ERROR=" + $_.Exception.Message)
    exit 1
}
