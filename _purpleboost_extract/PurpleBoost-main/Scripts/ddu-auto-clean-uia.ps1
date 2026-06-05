# UI Automation helper for DDU (WPF) — called from ddu-auto-clean.ahk
param(
    [Parameter(Mandatory = $false)][ValidateSet('NVIDIA', 'AMD', 'INTEL')][string]$Vendor = 'NVIDIA',
    [string]$LiveStatusPath = '',
    [string]$LogPath = '',
    [string]$NoSafeModeArg = 'oui',
    [switch]$WatchPopupsOnly,
    [int]$PollMs = 200
)

$ErrorActionPreference = 'Continue'
$script:WorkflowPollMs = 200
$script:DduPopupPollMs = 125
$script:DduSafeModePopupTimeoutMs = 1500
$script:SafeClickBlockCoordinateFallbacks = $true
$script:DduCachedProcessIds = @()
$script:DduCachedProcessIdsAt = [DateTime]::MinValue
$script:DduLastPopupDumpUtc = [DateTime]::MinValue
$script:DduWin32ClickTypeReady = $false
$script:DduSafeModeCloseLastCycleUtc = [DateTime]::MinValue
$script:DduSafeModeCloseCycleKey = ''
$script:DduSafeModeManualWarned = $false

function Write-SafeClickBlocked([string]$context) {
    Write-LiveStatus "[SAFECLICK] Fallback coordonnées bloqué pour sécurité : $context"
    Write-LogLine "[SAFECLICK] Fallback coordonnées bloqué pour sécurité : $context"
}

function Write-DduTimingLog([string]$label, [int]$elapsedMs) {
    $line = "[DDU Timing] ${label} en ${elapsedMs} ms."
    Write-LogLine $line
}

function Write-LiveStatus([string]$msg) {
    if (-not $LiveStatusPath) { return }
    try {
        $dir = Split-Path -Parent $LiveStatusPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $LiveStatusPath -Value ("STATUS=" + $msg) -Encoding UTF8
    } catch {}
}

. (Join-Path $PSScriptRoot 'Safe-UiaClick.ps1')
$script:SafeUiaLogFn = { param([string]$m) Write-LiveStatus $m; Write-LogLine $m }

function Write-LogLine([string]$line) {
    if (-not $LogPath) { return }
    try {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch {}
}

function Test-ForbiddenCleanText([string]$name) {
    if (-not $name) { return $true }
    $u = $name.ToUpperInvariant()
    if ($u -match 'CLEAN AND DO NOT|NE PAS RED|DO NOT RESTART|WITHOUT RESTART|NETTOYER ET NE PAS|NETTOYER SANS') { return $false }
    if ($u -match 'CLEAN AND RESTART|NETTOYER ET RED|RESTART|REDEMARR|SHUTDOWN|ETEINDRE|ÉTEINDRE') { return $true }
    return $false
}

function Test-AllowedCleanNoRestart([string]$name) {
    if (-not $name) { return $false }
    $u = $name.ToUpperInvariant()
    if ($u -match 'CLEAN AND DO NOT|DO NOT RESTART|NE PAS RED|NETTOYER ET NE PAS|NETTOYER SANS|WITHOUT RESTART|DO NOT REBOOT') { return $true }
    return $false
}

function Test-RestartDangerText([string]$blob) {
    if (-not $blob) { return $false }
    $u = $blob.ToUpperInvariant()
    if ($u -match 'RESTART|REDEMARR|REBOOT|SHUTDOWN|ÉTEINDRE|ETEINDRE') { return $true }
    return $false
}

function Test-RestartOnlyPopup([string]$blob) {
    if (Test-DduSafeModeWarningOkOnlyPopup $blob) { return $false }
    if (-not (Test-RestartDangerText $blob)) { return $false }
    if (Test-FinalQuitPopup $blob) { return $false }
    return $true
}

# Popup information DDU : pas en mode sans échec — uniquement OK, ne redémarre pas le PC.
function Test-DduSafeModeWarningOkOnlyPopup([string]$blob) {
    if (-not $blob) { return $false }
    if ($blob -match '(?i)PAS en mode sans échec|pas en mode sans echec') { return $true }
    if ($blob -match "(?i)vous n.?êtes pas en mode sans échec|vous n.?etes pas en mode sans echec|not in safe mode") { return $true }
    if ($blob -match '(?i)pour un nettoyage sans erreur') { return $true }
    if ($blob -match '(?i)redémarrer en mode sans échec|redemarrer en mode sans echec') {
        if ($blob -notmatch '(?i)voulez-vous redémarrer|do you want to restart|redémarrer maintenant|restart now') {
            return $true
        }
    }
    if ($blob -match '(?i)mode sans échec|mode sans echec') {
        if ($blob -match '(?i)ddu a détecté|ddu a detecte|nettoyage sans erreur|recommandé|recommande') {
            return $true
        }
    }
    return $false
}

function Test-DduSafeModePopup([string]$blob) {
    return (Test-DduSafeModeWarningOkOnlyPopup $blob)
}

function Test-DduPopupWindowTitle([string]$title) {
    if (-not $title) { return $false }
    return ($title -match 'Display Driver Uninstaller')
}

function Test-IsDduRelatedWindow(
    [System.Windows.Automation.AutomationElement]$win,
    [string]$blob
) {
    try {
        $n = [string]$win.Current.Name
        if ($n -match 'Display Driver Uninstaller|Driver Uninstaller|^\s*DDU\s*$|Guru3D') { return $true }
    } catch {}
    if ($blob -match 'Display Driver Uninstaller|Driver Uninstaller|DDU|Guru3D') { return $true }
    return $false
}

function Get-DduPopupTextShallow([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    try {
        $rn = [string]$root.Current.Name
        if ($rn) { $parts.Add($rn) | Out-Null }
        $kids = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($k in $kids) {
            try {
                $kn = [string]$k.Current.Name
                if ($kn) { $parts.Add($kn) | Out-Null }
                $gk = $k.FindAll([System.Windows.Automation.TreeScope]::Children,
                    [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($gc in $gk) {
                    try {
                        $gcn = [string]$gc.Current.Name
                        if ($gcn) { $parts.Add($gcn) | Out-Null }
                    } catch {}
                }
            } catch {}
        }
    } catch {}
    return ($parts -join "`n")
}

function Get-DduWindowsByTitle {
    $list = New-Object System.Collections.Generic.List[System.Windows.Automation.AutomationElement]
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $all) {
        try {
            $title = [string]$w.Current.Name
            if (Test-DduPopupWindowTitle $title) {
                $list.Add($w) | Out-Null
            }
        } catch {}
    }
    return $list
}

function Get-DduRootWindow {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $nameCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty,
        'Display Driver Uninstaller'
    )
    $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $nameCond)
    if ($win) { return $win }
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $all) {
        try {
            $n = [string]$w.Current.Name
            if ($n -match 'Display Driver Uninstaller|^\s*DDU\s*$') { return $w }
        } catch {}
    }
    return $null
}

function Test-DduMainUiReady([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return $false }
    try {
        $combos = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::ComboBox
            )))
        if ($combos.Count -ge 2) { return $true }
        $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Button
            )))
        foreach ($btn in $buttons) {
            $n = [string]$btn.Current.Name
            if (Test-AllowedCleanNoRestart $n) { return $true }
        }
    } catch {}
    return $false
}

function Send-KeysSequence([string]$keys) {
    if (-not $keys) { return $false }
    try {
        $ws = New-Object -ComObject WScript.Shell
        $ws.SendKeys($keys)
        return $true
    } catch {
        return $false
    }
}

function Set-DduWindowForeground([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return }
    try {
        $hwnd = [int]$win.Current.NativeWindowHandle
        if ($hwnd -eq 0) { return }
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DduWin32Fg {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue | Out-Null
        [DduWin32Fg]::SetForegroundWindow([IntPtr]$hwnd) | Out-Null
    } catch {}
}

function Test-DduInterferingProgramsPopup([string]$blob) {
    if (-not $blob) { return $false }
    if ($blob -match 'DDU a fermé les programmes connus') { return $true }
    if ($blob -match 'DDU a ferme les programmes connus') { return $true }
    if ($blob -match 'programs known to interfere') { return $true }
    if ($blob -match 'MSI Afterburner' -and $blob -match 'DDU|interfér|interfer|fermé|closed') { return $true }
    if ($blob -match 'RTSS' -and $blob -match 'DDU|interfér|interfer|fermé|closed|Afterburner') { return $true }
    return $false
}

function Get-DduTextBlob([System.Windows.Automation.AutomationElement]$root) {
    return (Get-DduTextBlobFast $root 80)
}

function Get-DduTextBlobFast(
    [System.Windows.Automation.AutomationElement]$root,
    [int]$maxNames = 50
) {
    if (-not $root) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    $interesting = @(
        [System.Windows.Automation.ControlType]::Text,
        [System.Windows.Automation.ControlType]::Button,
        [System.Windows.Automation.ControlType]::Pane,
        [System.Windows.Automation.ControlType]::Group,
        [System.Windows.Automation.ControlType]::Window
    )
    try {
        $rn = [string]$root.Current.Name
        if ($rn) { $parts.Add($rn) | Out-Null }
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        $n = 0
        foreach ($el in $all) {
            if ($n -ge $maxNames) { break }
            try {
                $ct = $el.Current.ControlType
                if ($interesting -notcontains $ct) { continue }
                $name = [string]$el.Current.Name
                if ($name) {
                    $parts.Add($name) | Out-Null
                    $n++
                }
            } catch {}
        }
    } catch {}
    return ($parts -join "`n")
}

function Ensure-DduWin32ClickType {
    if ($script:DduWin32ClickTypeReady) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class DduWin32Click {
    public const int BM_CLICK = 0x00F5;
    public const int WM_COMMAND = 0x0111;
    public const int IDOK = 1;
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr hWndParent, IntPtr hWndChildAfter, string lpszClass, string lpszWindow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
}
"@ -ErrorAction SilentlyContinue | Out-Null
    $script:DduWin32ClickTypeReady = $true
}

function Get-DduHwndWindowText([IntPtr]$hwnd) {
    if ($hwnd -eq [IntPtr]::Zero) { return '' }
    Ensure-DduWin32ClickType
    try {
        $sb = New-Object System.Text.StringBuilder 1024
        [void][DduWin32Click]::GetWindowText($hwnd, $sb, $sb.Capacity)
        return $sb.ToString()
    } catch {
        return ''
    }
}

function Test-DduHwndTextIsSafeModeWarning([IntPtr]$hwnd) {
    $t = Get-DduHwndWindowText $hwnd
    if (-not $t) { return $false }
    return (Test-DduSafeModeWarningOkOnlyPopup $t)
}

function Test-DduSafeModePopupTarget(
    [System.Windows.Automation.AutomationElement]$w,
    [string]$blob
) {
    if (-not $w) { return $false }
    if (-not (Test-DduSafeModeWarningOkOnlyPopup $blob)) { return $false }
    $meta = Get-DduWindowMeta $w
    if ($meta.Title -notmatch 'Display Driver Uninstaller') { return $false }
    if (-not (Test-DduWindowOkOnlyActions $w)) { return $false }
    if (Test-DduRealRestartConfirmationDialog $w $blob) { return $false }
    if (-not (Find-DduOkButtonInWindow $w)) { return $false }
    if (Test-DduMainUiReady $w) {
        if ($blob -notmatch '(?i)PAS en mode sans échec|pas en mode sans echec|nettoyage sans erreur') {
            return $false
        }
    }
    return $true
}

function Get-DduSafeModeCloseCycleKey([System.Windows.Automation.AutomationElement]$w) {
    $meta = Get-DduWindowMeta $w
    return ('sm|' + $meta.ProcessId + '|' + $meta.NativeHandle.ToInt64())
}

function Test-DduSafeModeCloseThrottleAllows([string]$cycleKey) {
    if (-not $cycleKey) { return $true }
    $now = [DateTime]::UtcNow
    if ($cycleKey -eq $script:DduSafeModeCloseCycleKey) {
        if (($now - $script:DduSafeModeCloseLastCycleUtc).TotalSeconds -lt 2) {
            return $false
        }
    }
    $script:DduSafeModeCloseCycleKey = $cycleKey
    $script:DduSafeModeCloseLastCycleUtc = $now
    return $true
}

function Find-DduSafeModePopupWindow {
    foreach ($w in (Get-DduFastRelatedWindows)) {
        try {
            $blob = Get-DduTextBlobFast $w 45
            if (Test-DduSafeModePopupTarget $w $blob) {
                return @{ Window = $w; Blob = $blob }
            }
        } catch {}
    }
    return $null
}

function Get-DduDialogHwndCandidates([IntPtr]$rootHwnd) {
    $list = New-Object System.Collections.Generic.List[IntPtr]
    if ($rootHwnd -ne [IntPtr]::Zero) { [void]$list.Add($rootHwnd) }
    if ($rootHwnd -eq [IntPtr]::Zero) { return $list }
    Ensure-DduWin32ClickType
    try {
        $child = [IntPtr]::Zero
        for ($i = 0; $i -lt 16; $i++) {
            $child = [DduWin32Click]::FindWindowEx($rootHwnd, $child, '#32770', $null)
            if ($child -eq [IntPtr]::Zero) { break }
            if ([DduWin32Click]::IsWindow($child)) { [void]$list.Add($child) }
        }
    } catch {}
    return $list
}

function Invoke-DduSafeModeOkWmCommandIdok(
    [System.Windows.Automation.AutomationElement]$w,
    [string]$blob
) {
    if (-not (Test-DduSafeModePopupTarget $w $blob)) { return $false }
    Ensure-DduWin32ClickType
    $rootHwnd = (Get-DduWindowMeta $w).NativeHandle
    if ($rootHwnd -eq [IntPtr]::Zero) { return $false }

    foreach ($hDlg in (Get-DduDialogHwndCandidates $rootHwnd)) {
        try {
            if (-not [DduWin32Click]::IsWindow($hDlg)) { continue }
            if (-not [DduWin32Click]::IsWindowVisible($hDlg)) { continue }
            if (-not (Test-DduHwndTextIsSafeModeWarning $hDlg)) {
                if ($hDlg -ne $rootHwnd) { continue }
                if (-not (Test-DduSafeModeWarningOkOnlyPopup $blob)) { continue }
            }
            [void][DduWin32Click]::SetForegroundWindow($hDlg)
            Start-Sleep -Milliseconds 50
            $idOk = [IntPtr][int][DduWin32Click]::IDOK
            [void][DduWin32Click]::SendMessage($hDlg, [DduWin32Click]::WM_COMMAND, $idOk, [IntPtr]::Zero)
            [void][DduWin32Click]::PostMessage($hDlg, [DduWin32Click]::WM_COMMAND, $idOk, [IntPtr]::Zero)
            Write-DduPopupLine '[SAFE-WIN32] DDU safe mode warning OK WM_COMMAND IDOK invoked'
            return $true
        } catch {}
    }
    return $false
}

function Test-DduSafeModeWarningClosedAfterAttempt {
    Start-Sleep -Milliseconds 300
    return (-not (Test-DduSafeModeWarningStillVisible))
}

function Get-DduCachedProcessIds {
    $now = [DateTime]::UtcNow
    if ($script:DduCachedProcessIds.Count -gt 0 -and ($now - $script:DduCachedProcessIdsAt).TotalSeconds -lt 8) {
        return $script:DduCachedProcessIds
    }
    $ids = New-Object System.Collections.Generic.List[int]
    foreach ($procName in @('Display Driver Uninstaller', 'DDU')) {
        try {
            Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Id -gt 0) { [void]$ids.Add($_.Id) }
            }
        } catch {}
    }
    if ($ids.Count -eq 0) {
        try {
            Get-Process | Where-Object {
                $_.MainWindowTitle -match 'Display Driver Uninstaller|^\s*DDU\s*$'
            } | ForEach-Object { if ($_.Id -gt 0) { [void]$ids.Add($_.Id) } }
        } catch {}
    }
    $script:DduCachedProcessIds = @($ids | Select-Object -Unique)
    $script:DduCachedProcessIdsAt = $now
    return $script:DduCachedProcessIds
}

function Get-DduFastRelatedWindows {
    $list = New-Object System.Collections.Generic.List[System.Windows.Automation.AutomationElement]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $pids = Get-DduCachedProcessIds

    $add = {
        param([System.Windows.Automation.AutomationElement]$el)
        if (-not $el) { return }
        try {
            if (-not $el.Current.IsOffscreen) { }
            $id = ($el.GetRuntimeId() | ForEach-Object { $_.ToString() }) -join ','
            if ($seen.Contains($id)) { return }
            [void]$seen.Add($id)
            $list.Add($el) | Out-Null
        } catch {}
    }

    try {
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $tops = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($w in $tops) {
            try {
                if (-not $w.Current.IsEnabled) { continue }
                $pid = 0
                try { $pid = [int]$w.Current.ProcessId } catch {}
                $title = [string]$w.Current.Name
                $matchPid = ($pid -gt 0 -and $pids -contains $pid)
                $matchTitle = ($title -match 'Display Driver Uninstaller|^\s*DDU\s*$|Driver Uninstaller')
                if ($matchPid -or $matchTitle) { & $add $w }
            } catch {}
        }
    } catch {}

    return $list
}

function Get-DduWindowMeta([System.Windows.Automation.AutomationElement]$w) {
    $meta = @{
        Title = ''
        ProcessId = 0
        ClassName = ''
        NativeHandle = [IntPtr]::Zero
    }
    if (-not $w) { return $meta }
    try { $meta.Title = [string]$w.Current.Name } catch {}
    try { $meta.ProcessId = [int]$w.Current.ProcessId } catch {}
    try { $meta.ClassName = [string]$w.Current.ClassName } catch {}
    try { $meta.NativeHandle = [IntPtr][int]$w.Current.NativeWindowHandle } catch {}
    return $meta
}

function Get-DduButtonsSnapshot([System.Windows.Automation.AutomationElement]$root) {
    $rows = New-Object System.Collections.Generic.List[string]
    if (-not $root) { return $rows }
    try {
        $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Button
            )))
        $n = 0
        foreach ($btn in $buttons) {
            if ($n -ge 12) { break }
            try {
                $name = [string]$btn.Current.Name
                $aid = ''
                try { $aid = [string]$btn.Current.AutomationId } catch {}
                $ct = $btn.Current.ControlType.ProgrammaticName
                $en = $btn.Current.IsEnabled
                $r = $btn.Current.BoundingRectangle
                $rect = ('L{0:F0},T{1:F0},W{2:F0},H{3:F0}' -f $r.X, $r.Y, $r.Width, $r.Height)
                $rows.Add("Name='$name' AutomationId='$aid' ControlType=$ct IsEnabled=$en BoundingRectangle=$rect") | Out-Null
                $n++
            } catch {}
        }
    } catch {}
    return $rows
}

function Write-DduPopupLine([string]$line) {
    Write-LogLine $line
    Write-SafeUiaMsg $line
}

function Write-DduPopupDumpThrottled(
    [System.Windows.Automation.AutomationElement]$root,
    [string]$reason
) {
    $now = [DateTime]::UtcNow
    if (($now - $script:DduLastPopupDumpUtc).TotalSeconds -lt 5) { return }
    $script:DduLastPopupDumpUtc = $now
    Write-UiaDumpForElement $root $reason
}

function Write-DduSafeModePopupDiagnostic(
    [System.Windows.Automation.AutomationElement]$w,
    [string]$blob,
    [System.Windows.Automation.AutomationElement]$okBtn,
    [string]$invokeMethod
) {
    $meta = Get-DduWindowMeta $w
    Write-DduPopupLine '[DDU-POPUP] Safe mode warning detected'
    Write-DduPopupLine ("[DDU-POPUP] title=" + $meta.Title)
    Write-DduPopupLine ("[DDU-POPUP] ProcessId=" + $meta.ProcessId)
    Write-DduPopupLine ("[DDU-POPUP] className=" + $meta.ClassName)
    $snippet = ($blob -replace "`r?`n", ' | ').Trim()
    if ($snippet.Length -gt 280) { $snippet = $snippet.Substring(0, 280) + '…' }
    Write-DduPopupLine ("[DDU-POPUP] text=" + $snippet)
    foreach ($row in (Get-DduButtonsSnapshot $w)) {
        Write-DduPopupLine ("[DDU-POPUP] button: " + $row)
    }
    if ($okBtn) {
        $desc = Get-UiaElementDescriptor $okBtn
        Write-DduPopupLine ("[DDU-POPUP] OK candidate found: " + $desc)
        Write-DduPopupLine ("[DDU-POPUP] OK invoke method = " + $invokeMethod)
    } else {
        Write-DduPopupLine '[DDU-POPUP] OK candidate found: none'
    }
}

function Test-DduSafeModeWarningStillVisible {
    foreach ($w in (Get-DduFastRelatedWindows)) {
        try {
            $blob = Get-DduTextBlobFast $w 40
            if (Test-DduSafeModeWarningOkOnlyPopup $blob) { return $true }
        } catch {}
    }
    return $false
}

function Find-DduOkButtonCandidates([System.Windows.Automation.AutomationElement]$root) {
    $list = New-Object System.Collections.Generic.List[System.Windows.Automation.AutomationElement]
    if (-not $root) { return @() }
    try {
        $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Button
            )))
        foreach ($btn in $buttons) {
            try {
                if (-not $btn.Current.IsEnabled) { continue }
                $n = [string]$btn.Current.Name
                if (Test-DduOkButtonName $n) { $list.Add($btn) | Out-Null }
            } catch {}
        }
    } catch {}
    return @($list)
}

function Find-DduOkButtonInWindow([System.Windows.Automation.AutomationElement]$root) {
    $cands = Find-DduOkButtonCandidates $root
    foreach ($btn in $cands) {
        try {
            $inv = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            if ($inv) { return $btn }
        } catch {}
    }
    foreach ($btn in $cands) { return $btn }
    return $null
}

function Test-DduWindowOkOnlyActions([System.Windows.Automation.AutomationElement]$root) {
    if (Test-DduWindowHasRestartConfirmButtons $root) { return $false }
    $okCount = 0
    $other = 0
    try {
        $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Button
            )))
        foreach ($btn in $buttons) {
            try {
                if (-not $btn.Current.IsEnabled) { continue }
                $n = [string]$btn.Current.Name
                if (-not $n) { continue }
                if (Test-DduOkButtonName $n) { $okCount++; continue }
                if ($n -match '^(?:&)?(?:Yes|Oui|No|Non)$|Restart|Redémarrer|Reboot') { $other++ }
            } catch {}
        }
    } catch {}
    return ($okCount -ge 1 -and $other -eq 0)
}

function Invoke-DduOkLegacyAccessible([System.Windows.Automation.AutomationElement]$okBtn) {
    if (-not $okBtn) { return $false }
    try {
        $leg = $okBtn.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
        if ($leg) {
            $leg.DoDefaultAction()
            return $true
        }
    } catch {}
    return $false
}

function Invoke-DduSafeModeOkWin32Click(
    [System.Windows.Automation.AutomationElement]$w,
    [string]$blob
) {
    if (-not (Test-DduSafeModeWarningOkOnlyPopup $blob)) { return $false }
    if (-not (Test-DduWindowOkOnlyActions $w)) { return $false }
    Ensure-DduWin32ClickType
    $meta = Get-DduWindowMeta $w
    $parent = $meta.NativeHandle
    if ($parent -eq [IntPtr]::Zero) { return $false }
    try {
        [DduWin32Click]::SetForegroundWindow($parent) | Out-Null
    } catch {}
    $labels = @('OK', '&OK', 'Ok')
    foreach ($label in $labels) {
        try {
            $h = [DduWin32Click]::FindWindowEx($parent, [IntPtr]::Zero, $null, $label)
            if ($h -eq [IntPtr]::Zero) { continue }
            if (-not [DduWin32Click]::IsWindowVisible($h)) { continue }
            [DduWin32Click]::SendMessage($h, [DduWin32Click]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
            Write-DduPopupLine '[SAFE-WIN32] DDU safe mode warning OK BM_CLICK invoked'
            return $true
        } catch {}
    }
    return $false
}

function Invoke-DduSafeModeWarningOk {
    $hit = Find-DduSafeModePopupWindow
    if (-not $hit) { return $false }

    $w = $hit.Window
    $blob = $hit.Blob

    if (Test-DduRealRestartConfirmationDialog $w $blob) {
        Write-DduPopupLine '[DDU-POPUP] Real restart confirmation detected, manual required'
        Write-LiveStatus 'DDU : confirmation redémarrage détectée — action manuelle requise.'
        return $false
    }

    $cycleKey = Get-DduSafeModeCloseCycleKey $w
    if (-not (Test-DduSafeModeCloseThrottleAllows $cycleKey)) {
        return $false
    }

    Set-DduWindowForeground $w
    Start-Sleep -Milliseconds 80

    $okBtn = Find-DduOkButtonInWindow $w
    Write-DduSafeModePopupDiagnostic $w $blob $okBtn 'pending'

    if ($okBtn -and (SafeInvokeElement $okBtn 'OK')) {
        Write-DduPopupLine '[DDU-POPUP] OK invoke method = SafeInvokeElement'
        if (Test-DduSafeModeWarningClosedAfterAttempt) {
            Write-DduPopupLine '[DDU-POPUP] Safe mode warning closed'
            Write-LiveStatus '[DDU] Avertissement mode sans échec validé (OK).'
            $script:DduSafeModeManualWarned = $false
            return $true
        }
    }

    if ($okBtn -and (Invoke-DduOkLegacyAccessible $okBtn)) {
        Write-DduPopupLine '[SAFE-UIA] DDU OK via LegacyIAccessiblePattern'
        if (Test-DduSafeModeWarningClosedAfterAttempt) {
            Write-DduPopupLine '[DDU-POPUP] Safe mode warning closed'
            Write-LiveStatus '[DDU] Avertissement mode sans échec validé (OK).'
            $script:DduSafeModeManualWarned = $false
            return $true
        }
    }

    if (Invoke-DduSafeModeOkWin32Click $w $blob) {
        if (Test-DduSafeModeWarningClosedAfterAttempt) {
            Write-DduPopupLine '[DDU-POPUP] Safe mode warning closed'
            Write-LiveStatus '[DDU] Avertissement mode sans échec validé (OK).'
            $script:DduSafeModeManualWarned = $false
            return $true
        }
    }

    if (Invoke-DduSafeModeOkWmCommandIdok $w $blob) {
        if (Test-DduSafeModeWarningClosedAfterAttempt) {
            Write-DduPopupLine '[DDU-POPUP] Safe mode warning closed'
            Write-LiveStatus '[DDU] Avertissement mode sans échec validé (OK).'
            $script:DduSafeModeManualWarned = $false
            return $true
        }
        Write-DduPopupLine '[DDU-POPUP] WM_COMMAND IDOK failed, popup still visible'
    } else {
        Write-DduPopupLine '[DDU-POPUP] WM_COMMAND IDOK not sent (target validation failed)'
    }

    if (Test-DduSafeModeWarningStillVisible) {
        Write-DduPopupDumpThrottled $w 'DDU safe mode warning still visible after close attempts'
        if (-not $script:DduSafeModeManualWarned) {
            Write-LiveStatus 'DDU : pop-up mode sans échec toujours visible — cliquez OK manuellement si le nettoyage semble bloqué.'
            $script:DduSafeModeManualWarned = $true
        }
        return $false
    }

    Write-DduPopupLine '[DDU-POPUP] Safe mode warning closed'
    return $true
}

function Test-DduOkButtonName([string]$name) {
    if (-not $name) { return $false }
    $n = $name.Trim()
    return ($n -eq 'OK' -or $n -eq '&OK' -or $n -eq 'Ok')
}

function Test-DduWindowHasRestartConfirmButtons([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return $false }
    $patterns = @(
        '^(?:&)?Yes$', '^(?:&)?Oui$', 'Restart', 'Redémarrer', 'Redemarrer',
        'Reboot', 'Shutdown', 'Éteindre', 'Eteindre', 'Annuler et redémarrer'
    )
    try {
        $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Button
            )))
        foreach ($btn in $buttons) {
            try {
                if (-not $btn.Current.IsEnabled) { continue }
                $n = [string]$btn.Current.Name
                if (-not $n) { continue }
                if (Test-DduOkButtonName $n) { continue }
                foreach ($p in $patterns) {
                    if ($n -match $p) { return $true }
                }
            } catch {}
        }
    } catch {}
    return $false
}

function Test-DduRealRestartConfirmationDialog(
    [System.Windows.Automation.AutomationElement]$w,
    [string]$blob
) {
    if (Test-DduSafeModeWarningOkOnlyPopup $blob) { return $false }
    if ($blob -match '(?i)CLEAN AND RESTART|NETTOYER ET RED') { return $true }
    if ($blob -match '(?i)voulez-vous redémarrer|do you want to restart|redémarrer maintenant|restart now') { return $true }
    if ($w -and (Test-DduWindowHasRestartConfirmButtons $w)) { return $true }
    if (Test-RestartOnlyPopup $blob) { return $true }
    return $false
}

function Test-DduRestartOrQuitDialogBlob(
    [string]$blob,
    [System.Windows.Automation.AutomationElement]$w = $null
) {
    if (-not $blob) { return $false }
    if (Test-DduSafeModeWarningOkOnlyPopup $blob) { return $false }
    if (Test-DduRealRestartConfirmationDialog $w $blob) { return $true }
    if (Test-FinalQuitPopup $blob) { return $true }
    $u = $blob.ToUpperInvariant()
    if ($u -match 'VOULEZ-VOUS QUITTER|DO YOU WANT TO QUIT|WANT TO QUIT') { return $true }
    return $false
}

function Test-DduWindowHasCleanActionButton([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return $false }
    try {
        $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Button
            )))
        foreach ($btn in $buttons) {
            try {
                $n = [string]$btn.Current.Name
                if (Test-AllowedCleanNoRestart $n) { return $true }
            } catch {}
        }
    } catch {}
    return $false
}

function Test-DduWindowIsKnownOkDialog(
    [System.Windows.Automation.AutomationElement]$w,
    [string]$blob
) {
    if (-not $w) { return $false }
    if (-not (Find-DduOkButtonInWindow $w)) { return $false }

    # Avertissement mode sans échec : OK seul sur fenêtre DDU (même si boutons Nettoyer dans l'arbre UIA).
    if (Test-DduSafeModeWarningOkOnlyPopup $blob) {
        try {
            $title = [string]$w.Current.Name
            if (Test-DduPopupWindowTitle $title) { return $true }
        } catch {}
        if (Test-IsDduRelatedWindow $w $blob) { return $true }
    }

    if (Test-DduRealRestartConfirmationDialog $w $blob) { return $false }
    if (Test-DduRestartOrQuitDialogBlob $blob $w) { return $false }

    if (Test-DduWorkflowPopup $blob) { return $true }
    if (Test-DduInterferingProgramsPopup $blob) { return $true }
    if ($blob -match '(?i)Afterburner|RTSS|programmes connus|programs known to interfere|fermé|closed|information|avertissement|warning') {
        return $true
    }
    if (Test-DduWindowHasCleanActionButton $w) {
        return $false
    }
    try {
        $title = [string]$w.Current.Name
        if (Test-DduPopupWindowTitle $title) { return $true }
    } catch {}
    return (Test-IsDduRelatedWindow $w $blob)
}

function Get-DduRelatedUiWindows {
    return (Get-DduFastRelatedWindows)
}

function Invoke-DduKnownOkDialog {
    if (Find-DduSafeModePopupWindow) {
        return (Invoke-DduSafeModeWarningOk)
    }

    $handled = $false
    $popupSeen = $false
    foreach ($w in (Get-DduFastRelatedWindows)) {
        try {
            $title = [string]$w.Current.Name
            $blob = Get-DduTextBlobFast $w 40
            if (-not $blob) { $blob = Get-DduPopupTextShallow $w }
            if (Test-DduSafeModeWarningOkOnlyPopup $blob) { continue }
            if (-not (Test-DduWindowIsKnownOkDialog $w $blob)) { continue }

            if (Test-DduRealRestartConfirmationDialog $w $blob) {
                Write-DduPopupLine '[DDU-POPUP] Real restart confirmation detected, manual required'
                Write-LiveStatus 'DDU : confirmation redémarrage — action manuelle requise.'
                continue
            }

            $popupSeen = $true
            Set-DduWindowForeground $w
            Start-Sleep -Milliseconds 80

            $okBtn = Find-DduOkButtonInWindow $w
            if (-not $okBtn) { continue }

            $snippet = ($blob -replace "`r?`n", ' ').Trim()
            if ($snippet.Length -gt 220) { $snippet = $snippet.Substring(0, 220) + '…' }

            if (SafeInvokeElement $okBtn 'OK') {
                Write-DduPopupLine "[SAFE-UIA] DDU popup OK invoked: title=$title text=$snippet"
                Write-LiveStatus '[DDU] Pop-up information validée (OK).'
                $handled = $true
                Start-Sleep -Milliseconds 200
            }
        } catch {}
    }

    if ($popupSeen -and -not $handled) {
        Write-DduPopupLine 'DDU popup detected but OK button not found'
        Write-LiveStatus 'DDU : pop-up détectée — bouton OK introuvable, action manuelle requise.'
        foreach ($w in (Get-DduFastRelatedWindows)) {
            try {
                $blob = Get-DduTextBlobFast $w 40
                if (Test-DduWindowIsKnownOkDialog $w $blob) {
                    Write-DduPopupDumpThrottled $w 'DDU popup detected but OK button not found'
                    break
                }
            } catch {}
        }
    }

    return $handled
}

function Invoke-DduPopupOkClick(
    [System.Windows.Automation.AutomationElement]$w,
    [string[]]$okPatterns,
    [string[]]$forbidden
) {
    Set-DduWindowForeground $w
    Start-Sleep -Milliseconds 200
    $okBtn = Find-DduOkButtonInWindow $w
    if ($okBtn) {
        return (SafeInvokeElement $okBtn 'OK')
    }
    return $false
}

function Test-DduWorkflowPopup([string]$blob) {
    if (-not $blob) { return $false }
    if (Test-DduSafeModePopup $blob) { return $true }
    if (Test-DduInterferingProgramsPopup $blob) { return $true }
    if ($blob -match '(?i)MSI Afterburner|RTSS|programmes connus pour interf') { return $true }
    if ($blob -match '(?i)mode sans .?chec|vous n.?êtes pas en mode sans') { return $true }
    return $false
}

function Handle-DduWorkflowPopups {
    return (Invoke-DduKnownOkDialog)
}

function Test-DduOptionalOkPopupVisible {
    if (Find-DduSafeModePopupWindow) { return $true }
    if (Test-DduSafeModeWarningStillVisible) { return $true }
    foreach ($w in (Get-DduFastRelatedWindows)) {
        try {
            $blob = Get-DduTextBlobFast $w 40
            if (-not $blob) { $blob = Get-DduPopupTextShallow $w }
            if (Test-DduWindowIsKnownOkDialog $w $blob) { return $true }
        } catch {}
    }
    return $false
}

function Wait-DduOptionalOkPopup {
    Write-LogLine '[DDU] Recherche popup avertissement DDU...'
    Write-LiveStatus '[DDU] Recherche popup avertissement DDU...'

    $deadline = [DateTime]::UtcNow.AddMilliseconds($script:DduSafeModePopupTimeoutMs)
    $popupOkClicked = $false
    $detectLogged = $false

    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-DduOptionalOkPopupVisible) {
            if (-not $detectLogged) {
                Write-LogLine '[DDU] Popup OK détectée, tentative fermeture...'
                Write-LiveStatus '[DDU] Popup OK détectée, tentative fermeture...'
                $detectLogged = $true
            }
            if (Invoke-DduSafeModeWarningOk) {
                $popupOkClicked = $true
                break
            }
            if (Invoke-DduKnownOkDialog) {
                $popupOkClicked = $true
                break
            }
        } else {
            $elapsedMs = [int](([DateTime]::UtcNow - $script:flowStartUtc).TotalMilliseconds)
            if ($elapsedMs -ge 400) { break }
        }
        Start-Sleep -Milliseconds $script:DduPopupPollMs
    }

    if ($popupOkClicked) {
        Write-LogLine ('TIME_AFTER_SAFE_MODE_OK_MS=' + [int](([DateTime]::UtcNow - $script:flowStartUtc).TotalMilliseconds))
        return $true
    }

    if (-not $detectLogged) {
        Write-LogLine '[DDU] Aucune popup OK détectée après 1500 ms, continuation workflow.'
        Write-LiveStatus '[DDU] Aucune popup OK détectée après 1500 ms, continuation workflow.'
    } else {
        Write-LogLine '[DDU] Popup OK non fermée automatiquement, continuation workflow.'
        Write-LiveStatus '[DDU] Popup OK non fermée automatiquement, continuation workflow.'
    }
    return $false
}

function Invoke-DduPopupWatchTick {
    if (Find-DduSafeModePopupWindow) {
        Invoke-DduSafeModeWarningOk | Out-Null
        return
    }
    Invoke-DduKnownOkDialog | Out-Null
}

function Wait-Until([scriptblock]$Test, [int]$TimeoutMs, [int]$IntervalMs = 0) {
    if ($IntervalMs -le 0) { $IntervalMs = $script:DduPopupPollMs }
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        Invoke-DduPopupWatchTick
        if (& $Test) { return $true }
        Start-Sleep -Milliseconds $IntervalMs
    }
    return $false
}

function Wait-DduMainWindowReady([int]$TimeoutSec = 5) {
    $t0 = [DateTime]::UtcNow
    $ok = Wait-Until {
        $w = Get-DduRootWindow
        if ($w -and (Test-DduMainUiReady $w)) { $script:DduReadyWindow = $w; return $true }
        $false
    } ($TimeoutSec * 1000) $script:WorkflowPollMs
    if ($ok) {
        Write-DduTimingLog 'Fenêtre DDU détectée' ([int](([DateTime]::UtcNow - $t0).TotalMilliseconds))
        Write-LogLine '[DDU] Fenêtre détectée.'
    }
    if ($ok -and $script:DduReadyWindow) { return $script:DduReadyWindow }
    return $null
}

function Try-SelectComboFast(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$labels,
    [string]$value,
    [int]$TimeoutMs = 5000
) {
    $done = $false
    Wait-Until {
        if (Select-ComboByLabels $root $labels $value) { $done = $true; return $true }
        $false
    } $TimeoutMs $script:WorkflowPollMs | Out-Null
    return $done
}

function Invoke-DduScreenClick([int]$x, [int]$y) {
    Write-BlockedUnsafeClick "Invoke-DduScreenClick($x,$y)"
    return $false
}

function Try-ClickCleanNoRestart([System.Windows.Automation.AutomationElement]$root, [int]$TimeoutMs = 2000) {
    $clicked = $false
    $t0 = [DateTime]::UtcNow
    Wait-Until {
        if (Click-CleanNoRestartButton $root) { $clicked = $true; return $true }
        $false
    } $TimeoutMs $script:WorkflowPollMs | Out-Null
    if (-not $clicked) {
        Write-SafeClickBlocked 'DDU Nettoyer : offset fixe Left+135 Top+154 désactivé'
        Write-LogLine '[DDU] Bouton Nettoyer et NE PAS redémarrer introuvable via UIA, action manuelle requise.'
        Write-LiveStatus '[DDU] Bouton Nettoyer et NE PAS redémarrer introuvable via UIA, action manuelle requise.'
    }
    if ($clicked) {
        Write-DduTimingLog 'Bouton nettoyage cliqué' ([int](([DateTime]::UtcNow - $t0).TotalMilliseconds))
        Write-LogLine '[DDU] Bouton Nettoyer et NE PAS redémarrer cliqué.'
        Write-LiveStatus '[DDU] Bouton Nettoyer et NE PAS redémarrer cliqué.'
        Start-Sleep -Milliseconds 300
    }
    return $clicked
}

function Invoke-Element([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    try {
        $inv = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        if ($inv) { $inv.Invoke(); return $true }
    } catch {}
    return $false
}

function Click-ButtonInWindow(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$patterns,
    [string[]]$forbidden
) {
    if (-not $root) { return $false }
    $btnType = [System.Windows.Automation.ControlType]::Button
    $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
    foreach ($btn in $buttons) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            $u = $n.ToUpperInvariant()
            if ($forbidden) {
                $skip = $false
                foreach ($f in $forbidden) {
                    if ($u -match $f) { $skip = $true; break }
                }
                if ($skip) { continue }
            }
            foreach ($p in $patterns) {
                if ($n -match $p) {
                    if (Invoke-Element $btn) { return $true }
                }
            }
        } catch {}
    }
    return $false
}

function Get-WindowTextShallow([System.Windows.Automation.AutomationElement]$w) {
    if (-not $w) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    try {
        $n = [string]$w.Current.Name
        if ($n) { $parts.Add($n) | Out-Null }
        $kids = $w.FindAll([System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($k in $kids) {
            try {
                $kn = [string]$k.Current.Name
                if ($kn) { $parts.Add($kn) | Out-Null }
            } catch {}
        }
    } catch {}
    return ($parts -join "`n")
}

function Test-FinalQuitPopup([string]$blob) {
    if (-not $blob) { return $false }
    if (Test-RestartDangerText $blob) { return $false }
    $u = $blob.ToUpperInvariant()
    $hasDone = ($u -match 'UNINSTALL|DÉSINSTALL|DESINSTALL') -and ($u -match 'COMPLETE|TERMIN|FINISHED|DONE')
    $hasQuit = $u -match 'DO YOU WANT TO QUIT|WANT TO QUIT|VOULEZ-VOUS QUITTER|VOULEZ VOUS QUITTER|QUITTER'
    if ($hasQuit -and ($hasDone -or $u -match 'COMPLETE|TERMIN|FINISHED')) { return $true }
    if ($hasDone -and $u -match 'QUIT|EXIT|QUITTER') { return $true }
    return $false
}

function Wait-AndHandleFinalDduPopups([int]$timeoutMinutes) {
    $deadline = (Get-Date).AddMinutes($timeoutMinutes)
    $forbiddenYes = @('RESTART', 'REDEMARR', 'REBOOT', 'SHUTDOWN', 'ÉTEINDRE', 'ETEINDRE')
    $finalFound = $false
    $finalText = ''
    $yesClicked = $false
    $restartDetected = $false
    $dduClosed = $false

    while ((Get-Date) -lt $deadline) {
        $anyDdu = $false
        foreach ($w in (Get-DduWindowsByTitle)) {
            $anyDdu = $true
            $blob = Get-TextBlob $w
            if (Test-RestartOnlyPopup $blob) {
                $restartDetected = $true
                Write-LogLine 'FINAL_RESTART_TEXT_DETECTED=oui'
                Write-LiveStatus 'DDU demande une action liée au redémarrage. Action manuelle requise.'
                $snippet = ($blob -replace "`n", ' | ')
                if ($snippet.Length -gt 500) { $snippet = $snippet.Substring(0, 500) }
                Write-LogLine ('FINAL_DDU_POPUP_TEXT=' + $snippet)
                Write-LogLine 'FINAL_DDU_POPUP_FOUND=oui'
                Write-LogLine 'FINAL_YES_CLICKED=non'
                Write-LogLine 'DDU_CLOSED=non'
                return 'restart_manual'
            }
            if (Test-FinalQuitPopup $blob) {
                $finalFound = $true
                $finalText = ($blob -replace "`n", ' | ')
                Write-LiveStatus 'Fenêtre finale DDU détectée, fermeture…'
                if (Click-ButtonInWindow $w @('^Yes$', '^&Yes$', '^Oui$', '^&Oui$') $forbiddenYes) {
                    $yesClicked = $true
                    Start-Sleep -Milliseconds 800
                }
            }
        }
        if (-not $anyDdu -and $yesClicked) {
            $dduClosed = $true
            break
        }
        if ($yesClicked) {
            Start-Sleep -Seconds 2
            $still = Get-DduRootWindow
            if (-not $still) {
                $dduClosed = $true
                break
            }
        }
        Start-Sleep -Seconds 2
    }

    Write-LogLine ('FINAL_DDU_POPUP_FOUND=' + $(if ($finalFound) { 'oui' } else { 'non' }))
    if ($finalText) {
        $snippet = $finalText
        if ($snippet.Length -gt 500) { $snippet = $snippet.Substring(0, 500) }
        Write-LogLine ('FINAL_DDU_POPUP_TEXT=' + $snippet)
    } else {
        Write-LogLine 'FINAL_DDU_POPUP_TEXT='
    }
    Write-LogLine ('FINAL_YES_CLICKED=' + $(if ($yesClicked) { 'oui' } else { 'non' }))
    Write-LogLine ('FINAL_RESTART_TEXT_DETECTED=' + $(if ($restartDetected) { 'oui' } else { 'non' }))
    Write-LogLine ('DDU_CLOSED=' + $(if ($dduClosed -or $yesClicked) { 'oui' } else { 'non' }))

    if ($restartDetected) { return 'restart_manual' }
    if ($yesClicked) {
        Write-LiveStatus 'Nettoyage DDU terminé. Redémarrage conseillé.'
        return 'ok'
    }
    if ($finalFound) { return 'final_no_yes' }
    return 'timeout'
}

function Invoke-SelectionItemPattern([System.Windows.Automation.AutomationElement]$combo, [string]$targetText) {
    if (-not $combo) { return $false }
    try {
        $selPattern = $combo.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($selPattern) {
            $selPattern.Select()
            Start-Sleep -Milliseconds 200
        }
    } catch {}
    try {
        $expand = $combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        if ($expand) {
            $expand.Expand()
            Start-Sleep -Milliseconds 200
        }
    } catch {}
    $list = $combo.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($item in $list) {
        try {
            $n = [string]$item.Current.Name
            if (-not $n) { continue }
            if ($n -eq $targetText -or $n -match [regex]::Escape($targetText)) {
                $itemPattern = $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                if ($itemPattern) {
                    $itemPattern.Select()
                    Start-Sleep -Milliseconds 150
                    return $true
                }
                $invoke = $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                if ($invoke) {
                    $invoke.Invoke()
                    Start-Sleep -Milliseconds 150
                    return $true
                }
            }
        } catch {}
    }
    return $false
}

function Select-ComboByLabels([System.Windows.Automation.AutomationElement]$root, [string[]]$labels, [string]$value) {
    $combos = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ComboBox
        )))
    $labelEls = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text
        )))
    $labelRects = @()
    foreach ($le in $labelEls) {
        try {
            $t = [string]$le.Current.Name
            if (-not $t) { continue }
            foreach ($lab in $labels) {
                if ($t -match $lab) {
                    $labelRects += @{ El = $le; Text = $t; Rect = $le.Current.BoundingRectangle }
                    break
                }
            }
        } catch {}
    }
    foreach ($combo in $combos) {
        try {
            $cr = $combo.Current.BoundingRectangle
            foreach ($lr in $labelRects) {
                $dy = [Math]::Abs($cr.Top - $lr.Rect.Top)
                $dx = $cr.Left - $lr.Rect.Right
                if ($dy -lt 80 -and $dx -gt -40 -and $dx -lt 400) {
                    if (Invoke-SelectionItemPattern $combo $value) { return $true }
                }
            }
        } catch {}
    }
    $idx = 0
    foreach ($combo in $combos) {
        $idx++
        if ($idx -eq 1 -and ($labels -contains 'GPU' -or $labels -match 'device|périph|périp')) {
            if (Invoke-SelectionItemPattern $combo $value) { return $true }
        }
        if ($idx -eq 2 -and ($labels -match 'vendor|fabricant')) {
            if (Invoke-SelectionItemPattern $combo $value) { return $true }
        }
    }
    return $false
}

function Test-RestartOnlyButton([string]$name) {
    if (-not $name) { return $true }
    $u = $name.ToUpperInvariant()
    if (Test-AllowedCleanNoRestart $name) { return $false }
    if ($u -match 'CLEAN AND RESTART|NETTOYER ET RED|RESTART|REDEMARR|SHUTDOWN|ETEINDRE|ÉTEINDRE|REBOOT') { return $true }
    return $false
}

function Click-CleanNoRestartButton([System.Windows.Automation.AutomationElement]$root) {
    $buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        )))
    foreach ($btn in $buttons) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            if (Test-RestartOnlyButton $n) { continue }
            if (-not (Test-AllowedCleanNoRestart $n)) { continue }
            $invoke = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            if ($invoke) {
                $invoke.Invoke()
                return $true
            }
        } catch {}
    }
    return $false
}

$vendorUi = switch ($Vendor) {
    'NVIDIA' { 'NVIDIA' }
    'AMD'    { 'AMD' }
    'INTEL'  { 'Intel' }
}

$result = @{
    deviceTypeSelected = 'non'
    vendorSelected     = 'non'
    cleanFound         = 'non'
    cleanClicked       = 'non'
    result             = 'fail'
    error              = ''
}

try {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
} catch {
    if ($WatchPopupsOnly) {
        Write-LogLine 'DDU_POPUP_WATCHER_UIA_FAIL=oui'
        exit 2
    }
    $result.error = 'uia_assembly'
    Write-LogLine ('ERROR=' + $_.Exception.Message)
    Write-LiveStatus 'DDU lancé — surveillance du nettoyage en cours...'
    Write-LogLine 'RESULT=uia_assembly_fail'
    exit 2
}

$script:hasHandledDduSafeModePopup = $false
$script:hasHandledDduInterferingProgramsPopup = $false

function Start-DduPopupWatchSession {
    $script:hasHandledDduSafeModePopup = $false
    $script:hasHandledDduInterferingProgramsPopup = $false
    Write-LogLine '[DDU] Surveillance pop-ups DDU démarrée.'
    Write-LiveStatus '[DDU] Surveillance pop-ups DDU démarrée.'
}

function Stop-DduPopupWatchSession {
    Write-LogLine '[DDU] Surveillance pop-ups DDU arrêtée.'
    Write-LiveStatus '[DDU] Surveillance pop-ups DDU arrêtée.'
}

if ($WatchPopupsOnly) {
    Start-DduPopupWatchSession
    Write-LogLine 'DDU_POPUP_WATCHER_STARTED=oui'
    $interval = [Math]::Max(200, [Math]::Min(300, $PollMs))
    $deadline = (Get-Date).AddSeconds(120)
    $noWinStreak = 0
    while ((Get-Date) -lt $deadline) {
        $anyWin = $false
        foreach ($w in (Get-DduWindowsByTitle)) {
            $anyWin = $true
            break
        }
        if ($anyWin) { $noWinStreak = 0 } else { $noWinStreak++ }
        Invoke-DduPopupWatchTick
        if ($noWinStreak -ge 15) { break }
        Start-Sleep -Milliseconds $interval
    }
    Write-LogLine 'DDU_POPUP_WATCHER_STOPPED=oui'
    Stop-DduPopupWatchSession
    exit 0
}

$suppressed = if ($NoSafeModeArg -match '^(oui|yes|1|true)$') { 'oui' } else { 'non' }
Write-LogLine ('SAFE_MODE_MSG_SUPPRESSED_BY_ARG=' + $suppressed)
Write-LogLine 'LONG_SLEEP_REMOVED=oui'

Start-DduPopupWatchSession

$flowStart = [DateTime]::UtcNow
$script:flowStartUtc = $flowStart

Wait-DduOptionalOkPopup | Out-Null

Invoke-DduKnownOkDialog | Out-Null
Write-LogLine '[DDU] Sélection type périphérique GPU...'
Write-LiveStatus '[DDU] Sélection type périphérique GPU...'
$win = Wait-DduMainWindowReady 5
if (-not $win) {
    $result.error = 'ddu_main_window'
    Write-LiveStatus 'DDU semble prendre trop de temps, vérifie la fenêtre DDU'
    Write-LogLine 'RESULT=ddu_main_timeout'
    Stop-DduPopupWatchSession
    exit 3
}
Write-LogLine ('MAIN_DDU_READY_AFTER_MS=' + [int](([DateTime]::UtcNow - $flowStart).TotalMilliseconds))

$tGpu = [DateTime]::UtcNow
$gpuOk = Try-SelectComboFast $win @('GPU', 'Device type', 'Type de périph', 'périphérique', 'périp') 'GPU' 5000
if ($gpuOk) { $result.deviceTypeSelected = 'oui' }
Write-LogLine ('DEVICE_TYPE_SELECTED=' + $(if ($gpuOk) { 'GPU' } else { 'non' }))
Write-LogLine ('DEVICE_TYPE_SELECTED_AFTER_MS=' + [int](([DateTime]::UtcNow - $tGpu).TotalMilliseconds))

$tVendor = [DateTime]::UtcNow
$vendorOk = Try-SelectComboFast $win @('GPU Manufacturer', 'Manufacturer', 'Fabricant', 'Vendor') $vendorUi 5000
if (-not $vendorOk -and $Vendor -eq 'INTEL') {
    $vendorOk = Try-SelectComboFast $win @('GPU Manufacturer', 'Manufacturer', 'Fabricant', 'Vendor') 'INTEL' 3000
}
if ($vendorOk) {
    $result.vendorSelected = 'oui'
    Write-LogLine ('VENDOR_SELECTED=' + $Vendor)
} else {
    Write-LogLine ('VENDOR_SELECTED=non')
}
Write-LogLine ('VENDOR_SELECTED_AFTER_MS=' + [int](([DateTime]::UtcNow - $tVendor).TotalMilliseconds))

Write-LiveStatus ('Sélection GPU / ' + $Vendor + '…')

Invoke-DduKnownOkDialog | Out-Null
$tClean = [DateTime]::UtcNow
$clicked = Try-ClickCleanNoRestart $win 2000
Write-LogLine ('CLEAN_BUTTON_CLICKED_AFTER_MS=' + [int](([DateTime]::UtcNow - $tClean).TotalMilliseconds))

if (-not $clicked) {
    $result.error = 'clean_button_not_found'
    Write-LogLine 'CLEAN_NO_RESTART_BUTTON_FOUND=non'
    Write-LogLine 'CLEAN_NO_RESTART_CLICKED=non'
    Write-LogLine 'RESULT=clean_button_not_found'
    Write-LiveStatus 'Action manuelle requise — clique « Nettoyer et NE PAS redémarrer » dans DDU.'
    Stop-DduPopupWatchSession
    exit 4
}

$result.cleanFound = 'oui'
$result.cleanClicked = 'oui'
Write-LogLine 'CLEAN_NO_RESTART_BUTTON_FOUND=oui'
Write-LogLine 'CLEAN_NO_RESTART_CLICKED=oui'
Write-LiveStatus 'Nettoyage GPU en cours...'
Invoke-DduKnownOkDialog | Out-Null

$cleanWatchDeadline = (Get-Date).AddSeconds(120)
$cleanDone = $false
while ((Get-Date) -lt $cleanWatchDeadline) {
    Invoke-DduPopupWatchTick
    $still = Get-DduRootWindow
    if (-not $still) {
        $any = $false
        foreach ($w in (Get-DduWindowsByTitle)) { $any = $true; break }
        if (-not $any) {
            $cleanDone = $true
            break
        }
    }
    Start-Sleep -Milliseconds $script:DduPopupPollMs
}

Stop-DduPopupWatchSession
if ($cleanDone) {
    Write-LiveStatus 'Nettoyage GPU terminé — redémarrage conseillé'
    Write-LogLine 'RESULT=ok'
    exit 0
}

Write-LiveStatus 'DDU semble prendre trop de temps, vérifie la fenêtre DDU'
Write-LogLine 'RESULT=clean_watch_timeout'
exit 5
