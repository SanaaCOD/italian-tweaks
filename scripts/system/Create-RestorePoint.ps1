#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-RestorePointRateLimitError {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $patterns = @(
        'RESTORE_POINT_SKIPPED',
        '30105',
        '0x800423f9',
        '0x800423F9',
        '0x800423f4',
        '0x800423F4',
        'frequency',
        'already been created',
        'already created',
        'within the last',
        'A new system restore point cannot be created'
    )

    foreach ($pattern in $patterns) {
        if ($Message -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-SystemRestoreAvailable {
    $disableSr = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -ErrorAction SilentlyContinue
    if ($null -ne $disableSr -and [int]$disableSr.DisableSR -eq 1) {
        return $false
    }

    $driveStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "C:" -ErrorAction SilentlyContinue
    if ($null -ne $driveStatus -and [int]$driveStatus."C:" -eq 1) {
        return $false
    }

    return $true
}

if (-not (Test-IsAdministrator)) {
    Write-Output "RESTORE_POINT_ERROR=ADMIN_REQUIRED"
    exit 1
}

if (-not (Test-SystemRestoreAvailable)) {
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop | Out-Null
        Write-Output "RESTORE_POINT_ENABLE_ATTEMPTED=true"
    }
    catch {
        Write-Output "RESTORE_POINT_ERROR=SYSTEM_RESTORE_UNAVAILABLE"
        Write-Output ("RESTORE_POINT_DETAIL=" + $_.Exception.Message)
        exit 1
    }
}
else {
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Output ("RESTORE_POINT_ENABLE_WARN=" + $_.Exception.Message)
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH-mm"
$description = "Kojo - Avant optimisations - $timestamp"

Write-Output ("RESTORE_POINT_DESCRIPTION=" + $description)

try {
    Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
    Write-Output "RESTORE_POINT_OK=true"
    exit 0
}
catch {
    $errorText = $_.Exception.Message
    if ($_.Exception.InnerException) {
        $errorText = "$errorText | $($_.Exception.InnerException.Message)"
    }

    if (Test-RestorePointRateLimitError -Message $errorText) {
        Write-Output "RESTORE_POINT_SKIPPED_RATE_LIMIT"
        exit 0
    }

    Write-Output ("RESTORE_POINT_ERROR=" + $errorText)
    exit 1
}
