# Launcher: requests UAC elevation then runs nvidia-installer-elevated-helper.ps1 (NVCleanstall untouched).
#Requires -Version 5.1
param(
    [string]$LogPath = '',
    [string]$LiveStatusPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HelperScript = Join-Path $PSScriptRoot 'nvidia-installer-elevated-helper.ps1'
if (-not (Test-Path -LiteralPath $HelperScript)) {
    Write-Error "Helper missing: $HelperScript"
    exit 1
}

$logsDir = if ($LogPath) { Split-Path -Parent $LogPath } else { Join-Path $PSScriptRoot '..\logs' }
if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}
$HelperLogPath = Join-Path $logsDir 'nvidia-installer-elevated-helper.log'

function Add-LauncherLog([string]$Message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message
    try { Add-Content -LiteralPath $HelperLogPath -Value $line -Encoding UTF8 } catch {}
    if ($LogPath) {
        try { Add-Content -LiteralPath $LogPath -Value $Message -Encoding UTF8 } catch {}
    }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$psArgs = @(
    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
    '-File', $HelperScript,
    '-LogPath', $LogPath,
    '-LiveStatusPath', $LiveStatusPath,
    '-HelperLogPath', $HelperLogPath
)

if (-not (Test-IsAdmin)) {
    Add-LauncherLog '[NVIDIA-ELEVATED] Helper requested elevation'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $psArgs -WindowStyle Hidden | Out-Null
    } catch {
        Add-LauncherLog "[NVIDIA-ELEVATED] Elevation launch failed: $($_.Exception.Message)"
        exit 2
    }
    exit 0
}

Add-LauncherLog '[NVIDIA-ELEVATED] Helper already elevated'
& $HelperScript -LogPath $LogPath -LiveStatusPath $LiveStatusPath -HelperLogPath $HelperLogPath
exit $LASTEXITCODE
