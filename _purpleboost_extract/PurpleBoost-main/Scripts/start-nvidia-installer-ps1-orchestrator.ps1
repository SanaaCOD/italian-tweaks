# Launcher: requests UAC elevation then runs nvidia-installer-ps1-orchestrator.ps1 (NVCleanstall untouched).
#Requires -Version 5.1
param(
    [string]$LogPath = '',
    [string]$LiveStatusPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OrchestratorScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'nvidia-installer-ps1-orchestrator.ps1')).Path
if (-not (Test-Path -LiteralPath $OrchestratorScript)) {
    Write-Error "Orchestrator missing: $OrchestratorScript"
    exit 1
}

$logsDir = if ($LogPath) { Split-Path -Parent $LogPath } else { Join-Path $PSScriptRoot '..\logs' }
if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}
$OrchLogPath = Join-Path $logsDir 'nvidia-installer-ps1-orchestrator.log'

function Add-LauncherLog([string]$Message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message
    try { Add-Content -LiteralPath $OrchLogPath -Value $line -Encoding UTF8 } catch {}
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
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', $OrchestratorScript,
    '-LogPath', $LogPath,
    '-LiveStatusPath', $LiveStatusPath
)

if (-not (Test-IsAdmin)) {
    Add-LauncherLog '[NVIDIA-ORCH] Orchestrator requested elevation'
    Add-LauncherLog "[NVIDIA-ORCH] ORCHESTRATOR FILE = $OrchestratorScript"
    Add-LauncherLog '[NVIDIA-ORCH] ORCHESTRATOR VERSION = 2026-05-24-detection-v2'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $psArgs -WindowStyle Hidden | Out-Null
    } catch {
        Add-LauncherLog "[NVIDIA-ORCH] Elevation launch failed: $($_.Exception.Message)"
        exit 2
    }
    exit 0
}

Add-LauncherLog '[NVIDIA-ORCH] Orchestrator already elevated'
Add-LauncherLog "[NVIDIA-ORCH] ORCHESTRATOR FILE = $OrchestratorScript"
Add-LauncherLog '[NVIDIA-ORCH] ORCHESTRATOR VERSION = 2026-05-24-detection-v2'
& $OrchestratorScript -LogPath $LogPath -LiveStatusPath $LiveStatusPath
exit $LASTEXITCODE
