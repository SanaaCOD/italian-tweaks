# One-shot: move visible cursor to NVIDIA license Accept button center — NO click.
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PurpleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$HelperCs = Join-Path $PurpleRoot 'Scripts\NvidiaWin32Msaa-helper.cs'

function Write-MoveTestLog([string]$Message) {
    Write-Host $Message
}

if (-not (Test-Path -LiteralPath $HelperCs)) {
    Write-MoveTestLog "[MOVE-TEST] Helper missing: $HelperCs"
    exit 1
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'NvidiaWin32Msaa').Type) {
        Add-Type -Path $HelperCs -ErrorAction Stop | Out-Null
    }
} catch {
    Write-MoveTestLog "[MOVE-TEST] Helper compile failed: $($_.Exception.Message)"
    exit 1
}

if (-not ([System.Management.Automation.PSTypeName]'NvidiaMoveCursorTest').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class NvidiaMoveCursorTest {
    public static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);

    public static string EnableDpiAwareness() {
        try {
            if (SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) != IntPtr.Zero) {
                return "SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)=OK";
            }
        } catch { }
        try {
            if (SetProcessDPIAware()) return "SetProcessDPIAware()=OK";
        } catch { }
        return "DPI awareness not set (continuing)";
    }

    public static bool IsDescendantOf(IntPtr child, IntPtr root) {
        if (child == IntPtr.Zero || root == IntPtr.Zero) return false;
        var cur = child;
        for (int i = 0; i < 64; i++) {
            if (cur == root) return true;
            var p = GetParent(cur);
            if (p == IntPtr.Zero) return false;
            cur = p;
        }
        return false;
    }
}
"@ -ErrorAction Stop | Out-Null
}

Write-MoveTestLog "[MOVE-TEST] DPI: $([NvidiaMoveCursorTest]::EnableDpiAwareness())"

function Normalize-NeedleText([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return '' }
    $t = $text.Trim()
    if ($t.StartsWith('&')) { $t = $t.Substring(1).Trim() }
    $t = $t.ToLowerInvariant()
    $t = $t -replace [char]0x2019, [string]::Empty
    $t = $t -replace "'", [string]::Empty
    while ($t.Contains('  ')) { $t = $t.Replace('  ', ' ') }
    return $t.Trim()
}

function Test-AcceptButtonText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    $norm = Normalize-NeedleText $text
    $hasAccept = ($norm -match 'accepter|accept') -or ($text -match '(?i)ACCEPTER|Accept')
    $hasContinue = ($norm -match 'continuer|continue') -or ($text -match '(?i)CONTINUER|Continue')
    return ($hasAccept -and $hasContinue)
}

function Find-AcceptButtonInfo([IntPtr]$rootHwnd) {
    $best = $null
    $bestLen = [int]::MaxValue
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible -or -not $c.Enabled) { continue }
        if (-not [NvidiaMoveCursorTest]::IsDescendantOf($c.Hwnd, $rootHwnd)) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not (Test-AcceptButtonText $text)) { continue }
        if ($text.Length -le $bestLen) {
            $best = $c
            $bestLen = $text.Length
        }
    }
    return $best
}

$rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
if ($rootHwnd -eq [IntPtr]::Zero) {
    Write-MoveTestLog '[MOVE-TEST] NVIDIA root not found'
    exit 2
}

$acceptInfo = Find-AcceptButtonInfo $rootHwnd
if (-not $acceptInfo) {
    Write-MoveTestLog '[MOVE-TEST] Accept hwnd not found'
    exit 3
}

Write-MoveTestLog "[MOVE-TEST] Accept hwnd found: HWND=$($acceptInfo.Hwnd.ToInt64()) text='$($acceptInfo.Text)' id=$($acceptInfo.ControlId) class='$($acceptInfo.ClassName)'"

$rectType = [NvidiaMoveCursorTest+RECT]
$acceptRect = New-Object $rectType
$gotRect = [NvidiaMoveCursorTest]::GetWindowRect($acceptInfo.Hwnd, [ref]$acceptRect)
if (-not $gotRect) {
    Write-MoveTestLog '[MOVE-TEST] GetWindowRect failed'
    exit 4
}

Write-MoveTestLog "[MOVE-TEST] Accept rect: L=$($acceptRect.Left) T=$($acceptRect.Top) R=$($acceptRect.Right) B=$($acceptRect.Bottom)"

$centerX = [int](($acceptRect.Left + $acceptRect.Right) / 2)
$centerY = [int](($acceptRect.Top + $acceptRect.Bottom) / 2)
Write-MoveTestLog "[MOVE-TEST] Center: X=$centerX Y=$centerY"

$pointType = [NvidiaMoveCursorTest+POINT]
$before = New-Object $pointType
$beforeOk = [NvidiaMoveCursorTest]::GetCursorPos([ref]$before)
if ($beforeOk) {
    Write-MoveTestLog "[MOVE-TEST] Cursor before: X=$($before.X) Y=$($before.Y)"
} else {
    Write-MoveTestLog '[MOVE-TEST] Cursor before: GetCursorPos failed'
}

[NvidiaMoveCursorTest]::SetForegroundWindow($rootHwnd) | Out-Null
Start-Sleep -Milliseconds 300

$setOk = [NvidiaMoveCursorTest]::SetCursorPos($centerX, $centerY)
Write-MoveTestLog "[MOVE-TEST] SetCursorPos result=$setOk"

Start-Sleep -Milliseconds 100

$after = New-Object $pointType
$afterOk = [NvidiaMoveCursorTest]::GetCursorPos([ref]$after)
if ($afterOk) {
    Write-MoveTestLog "[MOVE-TEST] Cursor after: X=$($after.X) Y=$($after.Y)"
    $dx = [Math]::Abs($after.X - $centerX)
    $dy = [Math]::Abs($after.Y - $centerY)
    if ($dx -le 2 -and $dy -le 2) {
        Write-MoveTestLog '[MOVE-TEST] Cursor position matches target center (within 2px)'
    } else {
        Write-MoveTestLog "[MOVE-TEST] Cursor position differs from target by dx=$dx dy=$dy"
    }
} else {
    Write-MoveTestLog '[MOVE-TEST] Cursor after: GetCursorPos failed'
}

Write-MoveTestLog '[MOVE-TEST] Waiting 5 seconds, no click sent'
Start-Sleep -Seconds 5
Write-MoveTestLog '[MOVE-TEST] Done (no click was sent)'
