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

    $changed = $false
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            $Object.$name = $Value
            $changed = $true
        }
    }
    return $changed
}

function Optimize-JsonConfigFile {
    param(
        [string]$FilePath,
        [string]$BackupRoot
    )

    try {
        $raw = Get-Content -Path $FilePath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $false }

        $json = $raw | ConvertFrom-Json
        $modified = $false

        $modified = (Set-JsonPropertyIfExists -Object $json -Names @(
            'AutoLaunch', 'autoLaunch', 'LaunchOnStartup', 'launchOnStartup'
        ) -Value $false) -or $modified

        $modified = (Set-JsonPropertyIfExists -Object $json -Names @(
            'RunInBackground', 'runInBackground', 'KeepLoggedIn', 'keepLoggedIn', 'CloseBehavior'
        ) -Value $false) -or $modified

        $modified = (Set-JsonPropertyIfExists -Object $json -Names @(
            'HardwareAcceleration', 'hardwareAcceleration', 'EnableHardwareAcceleration'
        ) -Value $false) -or $modified

        $modified = (Set-JsonPropertyIfExists -Object $json -Names @(
            'EnableNotifications', 'enableNotifications', 'ShowNotifications'
        ) -Value $false) -or $modified

        if (-not $modified) { return $false }

        $relative = $FilePath -replace '[\\:]+', '_'
        Copy-Item -Path $FilePath -Destination (Join-Path $BackupRoot $relative) -Force
        $json | ConvertTo-Json -Depth 100 | Set-Content -Path $FilePath -Encoding UTF8 -Force
        Write-AppLog ("BATTLENET_CONFIG_UPDATED=" + $FilePath)
        return $true
    }
    catch {
        return $false
    }
}

try {
    $wasRunning = $false
    $bnProcs = Get-Process -Name "Battle.net", "Agent" -ErrorAction SilentlyContinue
    if ($bnProcs) {
        $wasRunning = $true
        $bnProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRoot = Join-Path $env:ProgramData "Kojo\Backups\Applications\BattleNet\$timestamp"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $searchRoots = @(
        (Join-Path $env:APPDATA "Battle.net"),
        (Join-Path $env:LOCALAPPDATA "Battle.net"),
        (Join-Path $env:ProgramData "Battle.net")
    )

    $anyChanged = $false
    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }

        $files = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Extension -in @('.json', '.config') -and
                $_.FullName -notmatch '\\Call of Duty\\|\\Warzone\\|\\Games\\'
            }

        foreach ($file in $files) {
            if (Optimize-JsonConfigFile -FilePath $file.FullName -BackupRoot $backupRoot) {
                $anyChanged = $true
            }
        }
    }

    if (-not $anyChanged) {
        Write-AppLog "BATTLENET_CONFIG_NOT_FOUND"
    }

    if ($wasRunning) {
        $launcherCandidates = @(
            (Join-Path ${env:ProgramFiles(x86)} "Battle.net\Battle.net Launcher.exe"),
            (Join-Path $env:ProgramFiles "Battle.net\Battle.net Launcher.exe")
        )
        foreach ($launcher in $launcherCandidates) {
            if (Test-Path $launcher) {
                Start-Process -FilePath $launcher -WindowStyle Normal
                Write-AppLog "BATTLENET_RELAUNCHED"
                break
            }
        }
    }

    exit 0
}
catch {
    Write-AppLog ("BATTLENET_OPTIMIZE_ERROR=" + $_.Exception.Message)
    exit 1
}
