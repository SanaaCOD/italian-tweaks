$ErrorActionPreference = "Stop"

function Write-AppLog {
    param([string]$Message)
    Write-Output $Message
}

function Set-IniValue {
    param(
        [string[]]$Lines,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )

    $sectionFound = $false
    $keyFound = $false
    $result = New-Object System.Collections.Generic.List[string]
    $sectionPattern = "^\[$([regex]::Escape($Section))\]\s*$"
    $keyPattern = "^\s*$([regex]::Escape($Key))\s*="

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]

        if ($line -match $sectionPattern) {
            $sectionFound = $true
            $result.Add($line)
            continue
        }

        if ($sectionFound -and $line -match '^\[') {
            if (-not $keyFound) {
                $result.Add("$Key=$Value")
                $keyFound = $true
            }
            $sectionFound = $false
            $result.Add($line)
            continue
        }

        if ($sectionFound -and $line -match $keyPattern) {
            $result.Add("$Key=$Value")
            $keyFound = $true
            continue
        }

        $result.Add($line)
    }

    if ($sectionFound -and -not $keyFound) {
        $result.Add("$Key=$Value")
        $keyFound = $true
    }

    if (-not $sectionFound -and -not $keyFound) {
        return $null
    }

    return ,$result.ToArray()
}

try {
    $wasRunning = $false
    $obsProcs = Get-Process -Name "obs64", "obs32" -ErrorAction SilentlyContinue
    if ($obsProcs) {
        $wasRunning = $true
        $obsProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupRoot = Join-Path $env:ProgramData "Kojo\Backups\Applications\OBS\$timestamp"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $obsConfigDir = Join-Path $env:APPDATA "obs-studio"
    if (-not (Test-Path $obsConfigDir)) {
        Write-AppLog "OBS_CONFIG_NOT_FOUND"
        exit 0
    }

    $changed = $false
    $globalIni = Join-Path $obsConfigDir "global.ini"
    if (Test-Path $globalIni) {
        Copy-Item -Path $globalIni -Destination (Join-Path $backupRoot "global.ini") -Force
        $lines = Get-Content -Path $globalIni -Encoding UTF8
        $updated = $lines

        foreach ($pair in @(
            @{ Section = 'BasicWindow'; Key = 'PreviewEnabled'; Value = 'false' },
            @{ Section = 'BasicWindow'; Key = 'EnableAutoUpdates'; Value = 'false' },
            @{ Section = 'BasicWindow'; Key = 'SysTrayEnabled'; Value = 'false' }
        )) {
            $next = Set-IniValue -Lines $updated -Section $pair.Section -Key $pair.Key -Value $pair.Value
            if ($null -ne $next) {
                $updated = $next
                $changed = $true
            }
        }

        if ($changed) {
            $updated | Set-Content -Path $globalIni -Encoding UTF8 -Force
            Write-AppLog "OBS_GLOBAL_INI_OPTIMIZED"
        }
    }

    $kojoProfileDir = Join-Path $obsConfigDir "basic\profiles\Kojo Performance"
    if (-not (Test-Path $kojoProfileDir)) {
        New-Item -ItemType Directory -Path $kojoProfileDir -Force | Out-Null
        @(
            '[General]',
            'Name=Kojo Performance'
        ) | Set-Content -Path (Join-Path $kojoProfileDir "basic.ini") -Encoding UTF8 -Force
        Write-AppLog "OBS_KOJO_PROFILE_CREATED"
        $changed = $true
    }

    if (-not $changed) {
        Write-AppLog "OBS_SAFE_OPTIMIZATION_LIMITED"
    }

    if ($wasRunning) {
        $obsExeCandidates = @(
            (Join-Path $env:ProgramFiles "obs-studio\bin\64bit\obs64.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "obs-studio\bin\64bit\obs64.exe")
        )
        foreach ($obsExe in $obsExeCandidates) {
            if (Test-Path $obsExe) {
                $workDir = Split-Path $obsExe -Parent
                Start-Process -FilePath $obsExe -WorkingDirectory $workDir -WindowStyle Normal
                Write-AppLog "OBS_RELAUNCHED"
                break
            }
        }
    }

    exit 0
}
catch {
    Write-AppLog ("OBS_OPTIMIZE_ERROR=" + $_.Exception.Message)
    exit 1
}
