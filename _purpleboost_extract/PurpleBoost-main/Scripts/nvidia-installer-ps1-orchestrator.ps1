# NVIDIA Installer PS1 orchestrator — simple sequential flow (no page scoring).
#Requires -Version 5.1
param(
    [string]$LogPath = '',
    [string]$LiveStatusPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$rootDir = Split-Path -Parent $scriptDir
$ps1Dir = Join-Path $scriptDir 'NVIDIA-PS1'
$logsDir = Join-Path $rootDir 'logs'
$logPath = Join-Path $logsDir 'nvidia-installer-ps1-orchestrator.log'

if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$PollMs = 500
$WindowWaitSec = 180
$StepDelayMs = 1500
$FinalWaitSec = 1200

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-SimpleLog([string]$Message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message
    Write-Host $Message
    try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch {}
    if ($LogPath) {
        try { Add-Content -LiteralPath $LogPath -Value $Message -Encoding UTF8 } catch {}
    }
}

function Set-LiveStatus([string]$Message) {
    if (-not $LiveStatusPath) { return }
    try {
        $liveDir = Split-Path -Parent $LiveStatusPath
        if ($liveDir -and -not (Test-Path -LiteralPath $liveDir)) {
            New-Item -ItemType Directory -Path $liveDir -Force | Out-Null
        }
        Add-Content -LiteralPath $LiveStatusPath -Value ('STATUS=' + $Message) -Encoding UTF8
    } catch {}
}

function Set-OrchResult([string]$Value) {
    Write-SimpleLog "NVIDIA_ORCH_RESULT=$Value"
    if ($LogPath) {
        try { Add-Content -LiteralPath $LogPath -Value ("NVIDIA_ORCH_RESULT=" + $Value) -Encoding UTF8 } catch {}
    }
    if ($Value -eq 'finished') {
        try { Add-Content -LiteralPath $LogPath -Value 'NVIDIA_TICK_RESULT=finished' -Encoding UTF8 } catch {}
    } elseif ($Value -in @('manual', 'timeout')) {
        try { Add-Content -LiteralPath $LogPath -Value ('NVIDIA_TICK_RESULT=' + $Value) -Encoding UTF8 } catch {}
    } elseif ($Value -eq 'installing') {
        try { Add-Content -LiteralPath $LogPath -Value 'NVIDIA_TICK_RESULT=installing' -Encoding UTF8 } catch {}
    }
}

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class SimpleOrchWin32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const int SW_RESTORE = 9;
}
"@

function Normalize-Text {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text.ToLowerInvariant()
    $t = $t -replace '[éèêë]', 'e'
    $t = $t -replace '[àâä]', 'a'
    $t = $t -replace '[ùûü]', 'u'
    $t = $t -replace '[ôö]', 'o'
    $t = $t -replace '[îï]', 'i'
    $t = $t -replace 'ç', 'c'
    $t = $t -replace '&', ''
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-WndText([IntPtr]$Hwnd) {
    $sb = New-Object System.Text.StringBuilder 512
    [void][SimpleOrchWin32]::GetWindowText($Hwnd, $sb, $sb.Capacity)
    return $sb.ToString()
}

function Find-NvidiaInstallerWindow {
    $script:foundWindow = [IntPtr]::Zero
    $callback = [SimpleOrchWin32+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        if (-not [SimpleOrchWin32]::IsWindowVisible($hWnd)) { return $true }
        $norm = Normalize-Text (Get-WndText $hWnd)
        if ($norm -like "*programme d'installation nvidia*" -or $norm -like '*nvidia installer*') {
            $script:foundWindow = $hWnd
            return $false
        }
        return $true
    }
    [void][SimpleOrchWin32]::EnumWindows($callback, [IntPtr]::Zero)
    return $script:foundWindow
}

function Get-VisibleChildTexts([IntPtr]$Parent) {
    $items = New-Object System.Collections.Generic.List[string]
    $callback = [SimpleOrchWin32+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        if ([SimpleOrchWin32]::IsWindowVisible($hWnd)) {
            $txt = Get-WndText $hWnd
            if ($txt -and $txt.Trim().Length -gt 0) {
                $items.Add($txt) | Out-Null
            }
        }
        return $true
    }
    [void][SimpleOrchWin32]::EnumChildWindows($Parent, $callback, [IntPtr]::Zero)
    return $items.ToArray()
}

function Invoke-NvidiaForeground([IntPtr]$Win) {
    if ($Win -eq [IntPtr]::Zero) { return $false }
    [void][SimpleOrchWin32]::ShowWindow($Win, [SimpleOrchWin32]::SW_RESTORE)
    Start-Sleep -Milliseconds 200
    [void][SimpleOrchWin32]::BringWindowToTop($Win)
    Start-Sleep -Milliseconds 200
    [void][SimpleOrchWin32]::SetForegroundWindow($Win)
    Start-Sleep -Milliseconds 300
    return $true
}

function Test-LicensePageVisible([IntPtr]$Win) {
    $norms = @(Get-VisibleChildTexts $Win | ForEach-Object { Normalize-Text $_ })
    foreach ($n in $norms) {
        if ($n -eq 'accepter et continuer' -or $n -eq 'accept and continue' -or $n -eq 'agree and continue') {
            return $true
        }
    }
    return $false
}

function Test-FinalCloseButtonVisible([IntPtr]$Win) {
    $norms = @(Get-VisibleChildTexts $Win | ForEach-Object { Normalize-Text $_ })
    foreach ($n in $norms) {
        if ($n -eq 'fermer' -or $n -eq 'terminer' -or $n -eq 'close' -or $n -eq 'finish') {
            return $true
        }
    }
    return $false
}

function Test-FinalPageVisible([IntPtr]$Win) {
    return (Test-FinalCloseButtonVisible $Win)
}

function Write-VisibleTextsDump([IntPtr]$Win) {
    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] Visible texts:'
    foreach ($t in (Get-VisibleChildTexts $Win)) {
        Write-SimpleLog "  - '$t'"
    }
}

function Wait-ForNvidiaWindow {
    $deadline = (Get-Date).AddSeconds($WindowWaitSec)
    while ((Get-Date) -lt $deadline) {
        $win = Find-NvidiaInstallerWindow
        if ($win -ne [IntPtr]::Zero) { return $win }
        Start-Sleep -Milliseconds $PollMs
    }
    return [IntPtr]::Zero
}

function Invoke-SimplePs1Step {
    param(
        [string]$StepNum,
        [string]$ScriptName,
        [IntPtr]$Win,
        [switch]$StopOnFailure
    )

    $scriptPath = Join-Path $ps1Dir $ScriptName
    Invoke-NvidiaForeground $Win | Out-Null
    Write-SimpleLog "[NVIDIA-ORCH-SIMPLE] Running step ${StepNum}: $scriptPath"

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-SimpleLog "[NVIDIA-ORCH-SIMPLE] ERROR: script not found: $scriptPath"
        if ($StopOnFailure) { exit 3 }
        return 999
    }

    $proc = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) `
        -Wait `
        -PassThru `
        -WindowStyle Hidden

    [int]$exitCode = [int]$proc.ExitCode
    Write-SimpleLog "[NVIDIA-ORCH-SIMPLE] Step $StepNum exit code: $exitCode"

    if ($StopOnFailure -and $exitCode -ne 0) {
        Write-SimpleLog "[NVIDIA-ORCH-SIMPLE] Step $StepNum failed - stopping"
        Set-OrchResult 'manual'
        exit $exitCode
    }

    return $exitCode
}

function Wait-ForFinalOrWindowClose {
  param([IntPtr]$InitialWin)

    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] Waiting final page'
    Set-LiveStatus 'NVIDIA : installation en cours...'
    Set-OrchResult 'installing'

    $deadline = (Get-Date).AddSeconds($FinalWaitSec)
    while ((Get-Date) -lt $deadline) {
        $win = Find-NvidiaInstallerWindow
        if ($win -eq [IntPtr]::Zero) {
            Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] NVIDIA window closed, success.'
            Set-OrchResult 'finished'
            exit 0
        }
        if (Test-FinalPageVisible $win) {
            return $win
        }
        Start-Sleep -Milliseconds $PollMs
    }

    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] TIMEOUT waiting final page'
    Set-OrchResult 'timeout'
    exit 10
}

# --- Admin elevation ---
if (-not (Test-IsAdmin)) {
    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] Not admin - requesting elevation'
    $psArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath
    )
    if ($LogPath) { $psArgs += @('-LogPath', $LogPath) }
    if ($LiveStatusPath) { $psArgs += @('-LiveStatusPath', $LiveStatusPath) }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $psArgs -WindowStyle Hidden | Out-Null
    } catch {
        Write-SimpleLog "[NVIDIA-ORCH-SIMPLE] Elevation failed: $($_.Exception.Message)"
        Set-OrchResult 'manual'
        exit 2
    }
    exit 0
}

Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] Orchestrator started'
Write-SimpleLog "[NVIDIA-ORCH-SIMPLE] ORCHESTRATOR FILE = $PSCommandPath"
Write-SimpleLog "[NVIDIA-ORCH-SIMPLE] ps1Dir = $ps1Dir"
Set-OrchResult 'continue'
Set-LiveStatus 'NVIDIA : attente du programme d''installation...'

$win = Wait-ForNvidiaWindow
if ($win -eq [IntPtr]::Zero) {
    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] ERROR: NVIDIA window not found'
    Set-OrchResult 'timeout'
    exit 10
}

Invoke-NvidiaForeground $Win | Out-Null
$title = Get-WndText $win
Write-SimpleLog "[NVIDIA-ORCH-SIMPLE] NVIDIA window found hwnd=$($win.ToInt64()) title='$title'"

if (-not (Test-LicensePageVisible $win)) {
    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] ERROR: License page not detected'
    Write-VisibleTextsDump $win
    Set-OrchResult 'manual'
    exit 2
}

Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] License page detected'
Set-LiveStatus 'NVIDIA : licence détectée...'

Invoke-SimplePs1Step -StepNum '01' -ScriptName '01-NVIDIA-Accepter-Continuer.ps1' -Win $win -StopOnFailure
Start-Sleep -Milliseconds $StepDelayMs

$win = Find-NvidiaInstallerWindow
if ($win -eq [IntPtr]::Zero) {
    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] NVIDIA window closed, success.'
    Set-OrchResult 'finished'
    exit 0
}

Set-LiveStatus 'NVIDIA : sélection Personnalisée...'
Invoke-SimplePs1Step -StepNum '02' -ScriptName '02-NVIDIA-Options-Personnalisee.ps1' -Win $win
Start-Sleep -Milliseconds $StepDelayMs

$win = Find-NvidiaInstallerWindow
if ($win -eq [IntPtr]::Zero) {
    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] NVIDIA window closed, success.'
    Set-OrchResult 'finished'
    exit 0
}

Set-LiveStatus 'NVIDIA : validation Options...'
Invoke-SimplePs1Step -StepNum '03' -ScriptName '03-NVIDIA-Options-Suivant.ps1' -Win $win
Start-Sleep -Milliseconds $StepDelayMs

$win = Find-NvidiaInstallerWindow
if ($win -eq [IntPtr]::Zero) {
    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] NVIDIA window closed, success.'
    Set-OrchResult 'finished'
    exit 0
}

Set-LiveStatus 'NVIDIA : options personnalisées...'
Invoke-SimplePs1Step -StepNum '04' -ScriptName '04-NVIDIA-Options-Personnalisee-Suivant.ps1' -Win $win
Start-Sleep -Milliseconds $StepDelayMs

$win = Find-NvidiaInstallerWindow
if ($win -eq [IntPtr]::Zero) {
    Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] NVIDIA window closed, success.'
    Set-OrchResult 'finished'
    exit 0
}

Set-LiveStatus 'NVIDIA : installation...'
Invoke-SimplePs1Step -StepNum '05' -ScriptName '05-NVIDIA-Installer.ps1' -Win $win

$win = Wait-ForFinalOrWindowClose -InitialWin $win
if ($win -eq [IntPtr]::Zero) {
    exit 0
}

Set-LiveStatus 'NVIDIA : fermeture de l''installeur.'
Invoke-SimplePs1Step -StepNum '06' -ScriptName '06-NVIDIA-Fermer.ps1' -Win $win

Write-SimpleLog '[NVIDIA-ORCH-SIMPLE] Done'
Set-LiveStatus 'NVIDIA : installation terminée.'
Set-OrchResult 'finished'
exit 0
