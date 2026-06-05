# One-shot: real mouse click at GetWindowRect center of dynamically found NVIDIA license Accept button.
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PurpleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LogsDir = Join-Path $PurpleRoot 'logs'
$ResultPath = Join-Path $LogsDir 'nvidia-license-realinput-once-result.txt'
$HelperCs = Join-Path $PurpleRoot 'Scripts\NvidiaWin32Msaa-helper.cs'

$script:LogLines = New-Object System.Collections.Generic.List[string]

function Write-RealLog([string]$Message) {
    Write-Host $Message
    $script:LogLines.Add($Message) | Out-Null
}

function Flush-ResultLog {
    if (-not (Test-Path -LiteralPath $LogsDir)) {
        New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
    }
    $script:LogLines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    Set-Content -LiteralPath $ResultPath -Value $script:LogLines -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $HelperCs)) {
    Write-RealLog "[ONE-SHOT-REAL] Helper missing: $HelperCs"
    Flush-ResultLog
    exit 1
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'NvidiaWin32Msaa').Type) {
        Add-Type -Path $HelperCs -ErrorAction Stop | Out-Null
    }
} catch {
    Write-RealLog "[ONE-SHOT-REAL] Helper compile failed: $($_.Exception.Message)"
    Flush-ResultLog
    exit 1
}

if (-not ([System.Management.Automation.PSTypeName]'NvidiaLicenseRealInput').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NvidiaLicenseRealInput {
    public const int INPUT_MOUSE = 0;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_MOVE = 0x0001;
    public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public int type;
        public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);

    public static void RealLeftClickAtScreen(int x, int y) {
        if (SetCursorPos(x, y)) {
            var down = new INPUT { type = INPUT_MOUSE, mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_LEFTDOWN } };
            var up = new INPUT { type = INPUT_MOUSE, mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_LEFTUP } };
            var inputs = new INPUT[] { down, up };
            uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
            if (sent == inputs.Length) return;
            throw new InvalidOperationException("SendInput relative returned " + sent);
        }

        int sw = GetSystemMetrics(78); // SM_CXVIRTUALSCREEN
        int sh = GetSystemMetrics(79); // SM_CYVIRTUALSCREEN
        int sx = GetSystemMetrics(76); // SM_XVIRTUALSCREEN
        int sy = GetSystemMetrics(77); // SM_YVIRTUALSCREEN
        if (sw <= 0) sw = GetSystemMetrics(0);
        if (sh <= 0) sh = GetSystemMetrics(1);
        int ax = (int)(((long)(x - sx) * 65535L) / Math.Max(1, sw - 1));
        int ay = (int)(((long)(y - sy) * 65535L) / Math.Max(1, sh - 1));
        if (ax < 0) ax = 0; if (ax > 65535) ax = 65535;
        if (ay < 0) ay = 0; if (ay > 65535) ay = 65535;

        var move = new INPUT {
            type = INPUT_MOUSE,
            mi = new MOUSEINPUT { dx = ax, dy = ay, dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE }
        };
        var downAbs = new INPUT {
            type = INPUT_MOUSE,
            mi = new MOUSEINPUT { dx = ax, dy = ay, dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTDOWN }
        };
        var upAbs = new INPUT {
            type = INPUT_MOUSE,
            mi = new MOUSEINPUT { dx = ax, dy = ay, dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTUP }
        };
        var absInputs = new INPUT[] { move, downAbs, upAbs };
        uint sentAbs = SendInput((uint)absInputs.Length, absInputs, Marshal.SizeOf(typeof(INPUT)));
        if (sentAbs != absInputs.Length) {
            throw new InvalidOperationException("SendInput absolute returned " + sentAbs);
        }
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

    public static bool IsRootOrDescendantForeground(IntPtr root) {
        var fg = GetForegroundWindow();
        if (fg == IntPtr.Zero) return false;
        if (fg == root) return true;
        return IsDescendantOf(fg, root);
    }

    public static string GetWndText(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero) return "";
        var sb = new System.Text.StringBuilder(1024);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }
}
"@ -ErrorAction Stop | Out-Null
}

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

function Test-LicensePageConfirmed([IntPtr]$rootHwnd) {
    $hasLicenseText = $false
    $hasAccept = $false
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if ($text -match '(?i)Contrat de licence|License Agreement|NVIDIA Driver License Agreement') {
            $hasLicenseText = $true
        }
        if (Test-AcceptButtonText $text) { $hasAccept = $true }
    }
    return ($hasLicenseText -and $hasAccept)
}

function Find-AcceptButtonInfo([IntPtr]$rootHwnd) {
    $best = $null
    $bestLen = [int]::MaxValue
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible -or -not $c.Enabled) { continue }
        if (-not [NvidiaLicenseRealInput]::IsDescendantOf($c.Hwnd, $rootHwnd)) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not (Test-AcceptButtonText $text)) { continue }
        if ($text.Length -le $bestLen) {
            $best = $c
            $bestLen = $text.Length
        }
    }
    return $best
}

function Test-AcceptButtonStillVisible([IntPtr]$rootHwnd) {
    return ($null -ne (Find-AcceptButtonInfo $rootHwnd))
}

function Test-OptionsPageVisible([IntPtr]$rootHwnd) {
    $hasExpress = $false
    $hasCustom = $false
    $hasOptionsTitle = $false
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not $text) { continue }
        if ($text -match '(?i)Options d''installation|Installation Options|Choose Installation') {
            $hasOptionsTitle = $true
        }
        if ($text -match '(?i)&Expresse|&Express|Express installation') { $hasExpress = $true }
        if ($text -match '(?i)&Personnalis|&Custom|Custom \(Advanced\)|Personnalisée') { $hasCustom = $true }
    }
    if ($hasOptionsTitle) { return $true }
    if ($hasExpress -and $hasCustom) { return $true }
    return $false
}

$rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
if ($rootHwnd -eq [IntPtr]::Zero) {
    Write-RealLog '[ONE-SHOT-REAL] NVIDIA root not found'
    Flush-ResultLog
    exit 2
}

$rootTitle = [NvidiaWin32Msaa]::GetWndText($rootHwnd)
Write-RealLog "[ONE-SHOT-REAL] NVIDIA root found: HWND=$($rootHwnd.ToInt64()) title='$rootTitle'"

if (-not (Test-LicensePageConfirmed $rootHwnd)) {
    Write-RealLog '[ONE-SHOT-REAL] License page not confirmed — aborting (no click)'
    Flush-ResultLog
    exit 3
}

$acceptInfo = Find-AcceptButtonInfo $rootHwnd
if (-not $acceptInfo) {
    Write-RealLog '[ONE-SHOT-REAL] Accept hwnd not found — aborting (no click)'
    Flush-ResultLog
    exit 4
}

Write-RealLog "[ONE-SHOT-REAL] Accept hwnd found: text='$($acceptInfo.Text)' HWND=$($acceptInfo.Hwnd.ToInt64()) id=$($acceptInfo.ControlId) class='$($acceptInfo.ClassName)'"

$rectType = [NvidiaLicenseRealInput+RECT]
$acceptRect = New-Object $rectType
$gotRect = [NvidiaLicenseRealInput]::GetWindowRect($acceptInfo.Hwnd, [ref]$acceptRect)
if (-not $gotRect) {
    Write-RealLog '[ONE-SHOT-REAL] GetWindowRect failed — aborting (no click)'
    Flush-ResultLog
    exit 5
}

Write-RealLog "[ONE-SHOT-REAL] Accept rect: L=$($acceptRect.Left) T=$($acceptRect.Top) R=$($acceptRect.Right) B=$($acceptRect.Bottom)"

$centerX = [int](($acceptRect.Left + $acceptRect.Right) / 2)
$centerY = [int](($acceptRect.Top + $acceptRect.Bottom) / 2)
Write-RealLog "[ONE-SHOT-REAL] Accept center (screen): X=$centerX Y=$centerY"

[NvidiaLicenseRealInput]::SetForegroundWindow($rootHwnd) | Out-Null
Start-Sleep -Milliseconds 300

if (-not [NvidiaLicenseRealInput]::IsRootOrDescendantForeground($rootHwnd)) {
    $fg = [NvidiaLicenseRealInput]::GetForegroundWindow()
    $fgTitle = [NvidiaLicenseRealInput]::GetWndText($fg)
    Write-RealLog "[ONE-SHOT-REAL] SetForegroundWindow failed - foreground is HWND=$($fg.ToInt64()) title='$fgTitle', not NVIDIA root - aborting (no click)"
    Flush-ResultLog
    exit 6
}

Write-RealLog '[ONE-SHOT-REAL] SetForegroundWindow OK'

try {
    [NvidiaLicenseRealInput]::RealLeftClickAtScreen($centerX, $centerY)
    Write-RealLog '[ONE-SHOT-REAL] Real mouse click sent to center of accept hwnd'
} catch {
    Write-RealLog "[ONE-SHOT-REAL] Real mouse click failed: $($_.Exception.Message)"
    Flush-ResultLog
    exit 7
}

Start-Sleep -Milliseconds 700

if (-not (Test-AcceptButtonStillVisible $rootHwnd)) {
    Write-RealLog '[ONE-SHOT-REAL] Accept button disappeared'
    Flush-ResultLog
    exit 0
}

if (Test-OptionsPageVisible $rootHwnd) {
    Write-RealLog '[ONE-SHOT-REAL] Options page detected'
    Flush-ResultLog
    exit 0
}

Write-RealLog '[ONE-SHOT-REAL] Still on license page'
Flush-ResultLog
exit 8
