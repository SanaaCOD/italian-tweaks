# Elevated NVIDIA Installer wizard relay � HWND + GetWindowRect + real mouse click only.
# Targets "Programme d'installation NVIDIA" only; never NVCleanstall.
#Requires -Version 5.1
#Requires -RunAsAdministrator
param(
    [string]$LogPath = '',
    [string]$LiveStatusPath = '',
    [string]$HelperLogPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:HelperCs = Join-Path $PSScriptRoot 'NvidiaWin32Msaa-helper.cs'
$script:PollMs = 450
$script:MaxRuntimeSec = 3600
$script:SawWindow = $false
$script:LastInstallLogUtc = $null
$script:LastLoggedState = ''
$script:OptionsDone = $false
$script:CustomDone = $false

if (-not $HelperLogPath) {
    $logsDir = if ($LogPath) { Split-Path -Parent $LogPath } else { Join-Path $PSScriptRoot '..\logs' }
    $HelperLogPath = Join-Path $logsDir 'nvidia-installer-elevated-helper.log'
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-ElevatedLog([string]$Message) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message
    Write-Host $Message
    try {
        $dir = Split-Path -Parent $HelperLogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $HelperLogPath -Value $line -Encoding UTF8
    } catch {}
    if ($LogPath) {
        try { Add-Content -LiteralPath $LogPath -Value $Message -Encoding UTF8 } catch {}
    }
    if ($LiveStatusPath) {
        try {
            $liveDir = Split-Path -Parent $LiveStatusPath
            if ($liveDir -and -not (Test-Path -LiteralPath $liveDir)) {
                New-Item -ItemType Directory -Path $liveDir -Force | Out-Null
            }
            Add-Content -LiteralPath $LiveStatusPath -Value ('STATUS=' + $Message) -Encoding UTF8
        } catch {}
    }
}

function Set-MainLogField([string]$Key, [string]$Value) {
    if (-not $LogPath) { return }
    try { Add-Content -LiteralPath $LogPath -Value ($Key + '=' + $Value) -Encoding UTF8 } catch {}
}

function Ensure-HelperTypes {
    if (-not (Test-Path -LiteralPath $script:HelperCs)) {
        throw "Missing helper: $($script:HelperCs)"
    }
    if (-not ([System.Management.Automation.PSTypeName]'NvidiaWin32Msaa').Type) {
        Add-Type -Path $script:HelperCs -ErrorAction Stop | Out-Null
    }
    if (-not ([System.Management.Automation.PSTypeName]'NvidiaElevatedInput').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NvidiaElevatedInput {
    public static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);
    public const int INPUT_MOUSE = 0;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_MOVE = 0x0001;
    public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public int type; public MOUSEINPUT mi; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx; public int dy; public uint mouseData;
        public uint dwFlags; public uint time; public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

    public const int BM_CLICK = 0x00F5;
    public const int BM_GETCHECK = 0x00F0;
    public const int BM_SETCHECK = 0x00F1;
    public const int BST_CHECKED = 1;
    public const int BST_UNCHECKED = 0;
    public const int WM_COMMAND = 0x0111;
    public const int BN_CLICKED = 0;

    public static int GetButtonCheck(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero) return -1;
        try { return (int)SendMessage(hwnd, BM_GETCHECK, IntPtr.Zero, IntPtr.Zero); }
        catch { return -1; }
    }

    public static void SendBmClick(IntPtr hwnd) {
        SendMessage(hwnd, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
    }

    public static void SetButtonCheck(IntPtr hwnd, int state) {
        SendMessage(hwnd, BM_SETCHECK, new IntPtr(state), IntPtr.Zero);
    }

    public static void SendWmCommandClicked(IntPtr parentHwnd, IntPtr controlHwnd) {
        if (parentHwnd == IntPtr.Zero || controlHwnd == IntPtr.Zero) return;
        int id = GetDlgCtrlID(controlHwnd);
        if (id <= 0) return;
        int code = BN_CLICKED | (id << 16);
        SendMessage(parentHwnd, WM_COMMAND, new IntPtr(code), controlHwnd);
    }

    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

    public static string GetWndTextLocal(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero) return "";
        var sb = new System.Text.StringBuilder(1024);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static void EnableDpiAwareness() {
        try {
            if (SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) != IntPtr.Zero) return;
        } catch { }
        try { SetProcessDPIAware(); } catch { }
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

    public static void RealLeftClickAtScreen(int x, int y) {
        if (SetCursorPos(x, y)) {
            var down = new INPUT { type = INPUT_MOUSE, mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_LEFTDOWN } };
            var up = new INPUT { type = INPUT_MOUSE, mi = new MOUSEINPUT { dwFlags = MOUSEEVENTF_LEFTUP } };
            var inputs = new INPUT[] { down, up };
            uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
            if (sent == inputs.Length) return;
            throw new InvalidOperationException("SendInput relative returned " + sent);
        }

        int sw = GetSystemMetrics(78);
        int sh = GetSystemMetrics(79);
        int sx = GetSystemMetrics(76);
        int sy = GetSystemMetrics(77);
        if (sw <= 0) sw = GetSystemMetrics(0);
        if (sh <= 0) sh = GetSystemMetrics(1);
        int ax = (int)(((long)(x - sx) * 65535L) / Math.Max(1, sw - 1));
        int ay = (int)(((long)(y - sy) * 65535L) / Math.Max(1, sh - 1));
        if (ax < 0) ax = 0; if (ax > 65535) ax = 65535;
        if (ay < 0) ay = 0; if (ay > 65535) ay = 65535;

        var move = new INPUT { type = INPUT_MOUSE, mi = new MOUSEINPUT { dx = ax, dy = ay, dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE } };
        var downAbs = new INPUT { type = INPUT_MOUSE, mi = new MOUSEINPUT { dx = ax, dy = ay, dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTDOWN } };
        var upAbs = new INPUT { type = INPUT_MOUSE, mi = new MOUSEINPUT { dx = ax, dy = ay, dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTUP } };
        var absInputs = new INPUT[] { move, downAbs, upAbs };
        uint sentAbs = SendInput((uint)absInputs.Length, absInputs, Marshal.SizeOf(typeof(INPUT)));
        if (sentAbs != absInputs.Length) {
            throw new InvalidOperationException("SendInput absolute returned " + sentAbs);
        }
    }
}
"@ -ErrorAction Stop | Out-Null
    }
}

function Normalize-Text([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return '' }
    $t = $text.Trim()
    if ($t.StartsWith('&')) { $t = $t.Substring(1).Trim() }
    $t = $t.ToLowerInvariant()
    $t = $t -replace [char]0x2019, [string]::Empty
    $t = $t -replace "'", [string]::Empty
    while ($t.Contains('  ')) { $t = $t.Replace('  ', ' ') }
    return $t.Trim()
}

function Get-VisibleChildren([IntPtr]$rootHwnd) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        if (-not [NvidiaElevatedInput]::IsDescendantOf($c.Hwnd, $rootHwnd)) { continue }
        $list.Add($c) | Out-Null
    }
    return $list
}

function Normalize-InstallOptionText([string]$text) {
    $t = Normalize-Text $text
    $t = $t -replace 'é', 'e' -replace 'è', 'e' -replace 'ê', 'e' -replace 'ë', 'e'
    $t = $t -replace 'à', 'a' -replace 'â', 'a'
    $t = $t -replace 'ù', 'u' -replace 'û', 'u'
    return $t.Trim()
}

function Format-ControlRect([object]$childInfo) {
    if (-not $childInfo) { return 'n/a' }
    return "L=$($childInfo.Rect.Left),T=$($childInfo.Rect.Top),R=$($childInfo.Rect.Right),B=$($childInfo.Rect.Bottom)"
}

function Test-IsExpressControlText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    $norm = Normalize-InstallOptionText $text
    if ($norm -match 'express') { return $true }
    return ($text -match '(?i)express|expresse')
}

function Test-IsStrictCustomControlText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if (Test-IsExpressControlText $text) { return $false }
    $norm = Normalize-InstallOptionText $text
    if ($norm.StartsWith('personnalisee')) { return $true }
    if ($norm.StartsWith('custom')) { return $true }
    return ($text -match '(?i)Personnalisée|Personnalisee|Custom \(Advanced\)')
}

function Test-IsNextControlText([string]$text) {
    return ($text -match '(?i)^&?SUIVANT$|^&?Suivant$|^&Next$|^Next$')
}

function Test-CustomTargetTextValid([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if (Test-IsExpressControlText $text) { return $false }
    return ($text -match '(?i)Personnalisée|Personnalisee|Custom')
}

function Get-ChildCheckState([IntPtr]$hwnd) {
    if ($hwnd -eq [IntPtr]::Zero) { return $null }
    $v = [NvidiaElevatedInput]::GetButtonCheck($hwnd)
    if ($v -lt 0) { return $null }
    return $v
}

function Test-IsWin32RadioCandidate([object]$childInfo) {
    if (-not $childInfo) { return $false }
    $btnType = $childInfo.Style -band 0xF
    if ($btnType -in 4, 9) { return $true }
    if ($childInfo.ClassName -eq 'Button') { return $true }
    $chk = Get-ChildCheckState $childInfo.Hwnd
    if ($null -ne $chk -and $chk -in 0, 1) { return $true }
    return $false
}

function Get-UiaInfoForHwnd([IntPtr]$hwnd) {
    $info = @{
        ControlType = ''
        IsSelected  = $null
        Name        = ''
    }
    if ($hwnd -eq [IntPtr]::Zero) { return $info }
    try {
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
        if (-not $el) { return $info }
        try { $info.Name = [string]$el.Current.Name } catch {}
        try { $info.ControlType = [string]$el.Current.ControlType.ProgrammaticName } catch {}
        try {
            $sp = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            $info.IsSelected = [bool]$sp.Current.IsSelected
        } catch {}
    } catch {}
    return $info
}

function Find-NearestRadioForLabel([object]$labelChild, [object[]]$allChildren) {
    if (-not $labelChild) { return $null }
    $labelTop = $labelChild.Rect.Top
    $labelLeft = $labelChild.Rect.Left
    $best = $null
    $bestScore = [int]::MaxValue
    foreach ($c in $allChildren) {
        if (-not $c.Visible -or -not $c.Enabled) { continue }
        if ($c.Hwnd.ToInt64() -eq $labelChild.Hwnd.ToInt64()) { continue }
        if (-not (Test-IsWin32RadioCandidate $c)) { continue }
        $dy = [Math]::Abs($c.Rect.Top - $labelTop)
        if ($dy -gt 24) { continue }
        if ($c.Rect.Right -gt ($labelLeft + 100)) { continue }
        $score = [Math]::Abs($labelLeft - $c.Rect.Right) + ($dy * 4)
        if ($score -lt $bestScore) {
            $best = $c
            $bestScore = $score
        }
    }
    return $best
}

function Resolve-RadioForLabelText(
    [object[]]$allChildren,
    [scriptblock]$TextMatcher
) {
    $labelCandidate = $null
    $radioCandidate = $null
    foreach ($c in $allChildren) {
        if (-not $c.Visible -or -not $c.Enabled) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not (& $TextMatcher $text)) { continue }
        if (Test-IsWin32RadioCandidate $c) {
            if (-not $radioCandidate -or $text.Length -le [string]$radioCandidate.Text.Length) {
                $radioCandidate = $c
            }
        } else {
            if (-not $labelCandidate -or $text.Length -le [string]$labelCandidate.Text.Length) {
                $labelCandidate = $c
            }
        }
    }
    if ($radioCandidate) { return $radioCandidate }
    if ($labelCandidate) {
        $near = Find-NearestRadioForLabel $labelCandidate $allChildren
        if ($near) { return $near }
    }
    return $null
}

function Get-InstallOptionsChildren([IntPtr]$rootHwnd) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        if (-not [NvidiaElevatedInput]::IsDescendantOf($c.Hwnd, $rootHwnd)) { continue }
        if (Test-IsSidebarStepLabel $c $rootHwnd) { continue }
        $list.Add($c) | Out-Null
    }
    return $list.ToArray()
}

function Get-InstallOptionsRadioMap([IntPtr]$rootHwnd) {
    $all = Get-InstallOptionsChildren $rootHwnd
    $expressRadio = Resolve-RadioForLabelText $all { param($t) Test-IsExpressControlText $t }
    $customRadio = Resolve-RadioForLabelText $all { param($t) Test-IsStrictCustomControlText $t }
    $next = $null
    foreach ($c in $all) {
        if (-not $c.Enabled) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (Test-IsNextControlText $text) {
            if (-not $next -or $text.Length -le [string]$next.Text.Length) { $next = $c }
        }
    }
    return @{
        ExpressRadio = $expressRadio
        CustomRadio  = $customRadio
        Next         = $next
        All          = $all
    }
}

function Format-CheckState([object]$value) {
    if ($null -eq $value) { return 'unknown' }
    return [string]$value
}

function Write-InstallOptionsRadioDump([IntPtr]$rootHwnd, [hashtable]$map) {
    $logsDir = Split-Path -Parent $HelperLogPath
    $path = Join-Path $logsDir 'nvidia-installer-installoptions-radio-dump.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    $lines.Add('--- RESOLVED ---') | Out-Null
    foreach ($key in @('ExpressRadio', 'CustomRadio', 'Next')) {
        $c = $map[$key]
        if ($c) {
            $chk = Get-ChildCheckState $c.Hwnd
            $uia = Get-UiaInfoForHwnd $c.Hwnd
            $lines.Add("$key`: hwnd=$($c.Hwnd.ToInt64()) class='$($c.ClassName)' text='$($c.Text)' style=$($c.Style) rect=$(Format-ControlRect $c) checked=$(Format-CheckState $chk) uiaType=$($uia.ControlType) uiaSelected=$($uia.IsSelected)") | Out-Null
        } else {
            $lines.Add("$key`: none") | Out-Null
        }
    }
    $lines.Add('--- ALL CHILDREN ---') | Out-Null
    foreach ($c in $map.All) {
        $chk = Get-ChildCheckState $c.Hwnd
        $uia = Get-UiaInfoForHwnd $c.Hwnd
        $lines.Add("HWND=$($c.Hwnd.ToInt64()) | class='$($c.ClassName)' | text='$($c.Text)' | style=$($c.Style) | enabled=$($c.Enabled) | rect=$(Format-ControlRect $c) | parent=$($c.ParentHwnd) | checked=$(Format-CheckState $chk) | uiaType=$($uia.ControlType) | uiaSelected=$($uia.IsSelected)") | Out-Null
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
    Write-ElevatedLog "[NVIDIA-ELEVATED] InstallOptions radio dump: $path"
}

function Write-InstallOptionsRadioLog([hashtable]$map) {
    Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions radio dump:'
    foreach ($pair in @(
            @{ Key = 'ExpressRadio'; Label = 'Express radio' },
            @{ Key = 'CustomRadio'; Label = 'Custom radio' },
            @{ Key = 'Next'; Label = 'Next' }
        )) {
        $c = $map[$pair.Key]
        if ($c) {
            $chk = Get-ChildCheckState $c.Hwnd
            Write-ElevatedLog ("$($pair.Label): hwnd=$($c.Hwnd.ToInt64()) class='$($c.ClassName)' text='$($c.Text)' checked=$(Format-CheckState $chk)")
        } else {
            Write-ElevatedLog ("$($pair.Label): none")
        }
    }
}

function Test-CustomSelectedInUiaTree([IntPtr]$rootHwnd) {
    try {
        $rootEl = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd)
        if (-not $rootEl) { return $false }
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::RadioButton)
        $radios = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        foreach ($r in $radios) {
            $name = ''
            try { $name = [string]$r.Current.Name } catch {}
            if (-not (Test-IsStrictCustomControlText $name)) { continue }
            try {
                $sp = $r.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                if ($sp.Current.IsSelected) { return $true }
            } catch {}
        }
    } catch {}
    return $false
}

function Test-ExpressSelectedInUiaTree([IntPtr]$rootHwnd) {
    try {
        $rootEl = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd)
        if (-not $rootEl) { return $false }
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::RadioButton)
        $radios = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        foreach ($r in $radios) {
            $name = ''
            try { $name = [string]$r.Current.Name } catch {}
            if (-not (Test-IsExpressControlText $name)) { continue }
            try {
                $sp = $r.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                if ($sp.Current.IsSelected) { return $true }
            } catch {}
        }
    } catch {}
    return $false
}

function Test-CustomRadioSelected([object]$customRadio, [object]$expressRadio, [IntPtr]$rootHwnd) {
    if (Test-CustomSelectedInUiaTree $rootHwnd) {
        if (-not (Test-ExpressSelectedInUiaTree $rootHwnd)) { return $true }
    }

    if (-not $customRadio) { return $false }
    $customChecked = Get-ChildCheckState $customRadio.Hwnd
    $expressChecked = if ($expressRadio) { Get-ChildCheckState $expressRadio.Hwnd } else { $null }

    if ($customChecked -eq [NvidiaElevatedInput]::BST_CHECKED) {
        if ($null -eq $expressChecked -or $expressChecked -ne [NvidiaElevatedInput]::BST_CHECKED) {
            return $true
        }
    }

    $uiaCustom = Get-UiaInfoForHwnd $customRadio.Hwnd
    if ($uiaCustom.IsSelected -eq $true) {
        if ($expressRadio) {
            $uiaExpress = Get-UiaInfoForHwnd $expressRadio.Hwnd
            if ($uiaExpress.IsSelected -eq $true) { return $false }
        }
        return $true
    }
    return $false
}

function Get-InstallOptionsCheckSummary([object]$customRadio, [object]$expressRadio) {
  return @{
        ExpressChecked = if ($expressRadio) { Get-ChildCheckState $expressRadio.Hwnd } else { $null }
        CustomChecked  = if ($customRadio) { Get-ChildCheckState $customRadio.Hwnd } else { $null }
    }
}

function Invoke-SelectCustomRadioViaBmClick([IntPtr]$rootHwnd, [object]$customRadio) {
    [NvidiaWin32Msaa]::SetForegroundWindow($rootHwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    [NvidiaWin32Msaa]::SetFocus($customRadio.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 100
    Write-ElevatedLog "[NVIDIA-ELEVATED] Selecting Custom via BM_CLICK hwnd=$($customRadio.Hwnd.ToInt64())"
    [NvidiaElevatedInput]::SendBmClick($customRadio.Hwnd)
    Start-Sleep -Milliseconds 500
}

function Invoke-SelectCustomRadioViaUia([object]$customRadio) {
    if (-not $customRadio) { return $false }
    try {
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($customRadio.Hwnd)
        if (-not $el) { return $false }
        try {
            $sp = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            $sp.Select()
            Write-ElevatedLog "[NVIDIA-ELEVATED] Selecting Custom via UIA SelectionItemPattern hwnd=$($customRadio.Hwnd.ToInt64())"
            Start-Sleep -Milliseconds 500
            return $true
        } catch {}
        try {
            $ip = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $ip.Invoke()
            Write-ElevatedLog "[NVIDIA-ELEVATED] Selecting Custom via UIA InvokePattern hwnd=$($customRadio.Hwnd.ToInt64())"
            Start-Sleep -Milliseconds 500
            return $true
        } catch {}
    } catch {}
    return $false
}

function Invoke-SelectCustomRadioFromUiaTree([IntPtr]$rootHwnd) {
    try {
        $rootEl = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd)
        if (-not $rootEl) { return $false }
        $cond = New-Object System.Windows.Automation.AndCondition @(
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::RadioButton)),
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::IsEnabledProperty, $true))
        )
        $radios = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        foreach ($r in $radios) {
            $name = ''
            try { $name = [string]$r.Current.Name } catch {}
            if (-not (Test-IsStrictCustomControlText $name)) { continue }
            try {
                $sp = $r.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                $sp.Select()
                Write-ElevatedLog "[NVIDIA-ELEVATED] Selecting Custom via UIA tree RadioButton name='$name'"
                Start-Sleep -Milliseconds 500
                return $true
            } catch {}
            try {
                $ip = $r.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                $ip.Invoke()
                Write-ElevatedLog "[NVIDIA-ELEVATED] Selecting Custom via UIA tree Invoke name='$name'"
                Start-Sleep -Milliseconds 500
                return $true
            } catch {}
        }
    } catch {}
    return $false
}

function Invoke-NextButtonBmClick([IntPtr]$rootHwnd, [object]$nextBtn) {
    [NvidiaWin32Msaa]::SetForegroundWindow($rootHwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    [NvidiaWin32Msaa]::SetFocus($nextBtn.Hwnd) | Out-Null
    [NvidiaElevatedInput]::SendBmClick($nextBtn.Hwnd)
    Start-Sleep -Milliseconds 300
}

function Get-InstallOptionsCandidates([IntPtr]$rootHwnd) {
    $map = Get-InstallOptionsRadioMap $rootHwnd
    return @{
        Express = $map.ExpressRadio
        Custom  = $map.CustomRadio
        Next    = $map.Next
        Map     = $map
    }
}

function Write-InstallOptionsCandidatesLog([hashtable]$candidates) {
    $ex = $candidates.Express
    $cu = $candidates.Custom
    $nx = $candidates.Next
    Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions candidates:'
    if ($ex) {
        Write-ElevatedLog ("Express: hwnd=$($ex.Hwnd.ToInt64()) text='$($ex.Text)' rect=$(Format-ControlRect $ex)")
    } else {
        Write-ElevatedLog 'Express: hwnd=none text=none rect=n/a'
    }
    if ($cu) {
        Write-ElevatedLog ("Custom: hwnd=$($cu.Hwnd.ToInt64()) text='$($cu.Text)' rect=$(Format-ControlRect $cu)")
    } else {
        Write-ElevatedLog 'Custom: hwnd=none text=none rect=n/a'
    }
    if ($nx) {
        Write-ElevatedLog ("Next: hwnd=$($nx.Hwnd.ToInt64()) text='$($nx.Text)' rect=$(Format-ControlRect $nx)")
    } else {
        Write-ElevatedLog 'Next: hwnd=none text=none rect=n/a'
    }
}

function Write-InstallOptionsCandidatesDump([IntPtr]$rootHwnd, [hashtable]$candidates) {
    $logsDir = Split-Path -Parent $HelperLogPath
    $path = Join-Path $logsDir 'nvidia-installer-installoptions-candidates-dump.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    Write-InstallOptionsCandidatesLog $candidates
    $lines.Add('--- CANDIDATES ---') | Out-Null
    foreach ($key in @('Express', 'Custom', 'Next')) {
        $c = $candidates[$key]
        if ($c) {
            $lines.Add("$key`: hwnd=$($c.Hwnd.ToInt64()) text='$($c.Text)' rect=$(Format-ControlRect $c) class='$($c.ClassName)'") | Out-Null
        } else {
            $lines.Add("$key`: none") | Out-Null
        }
    }
    $lines.Add('--- ALL VISIBLE CHILDREN ---') | Out-Null
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        $lines.Add("HWND=$($c.Hwnd.ToInt64()) | text='$($c.Text)' | enabled=$($c.Enabled) | rect=$(Format-ControlRect $c) | class='$($c.ClassName)'") | Out-Null
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
    Write-ElevatedLog "[NVIDIA-ELEVATED] InstallOptions candidates dump: $path"
}

function Invoke-InstallOptionsStep([IntPtr]$rootHwnd) {
    return (Invoke-NvidiaInstallOptionsHwndClickMode $rootHwnd)
}

function Test-PointInsideRect([int]$x, [int]$y, [object]$rect) {
    if (-not $rect) { return $false }
    return ($x -ge $rect.Left -and $x -lt $rect.Right -and $y -ge $rect.Top -and $y -lt $rect.Bottom)
}

function Format-RawRect([object]$rect) {
    if (-not $rect) { return 'n/a' }
    return "L=$($rect.Left),T=$($rect.Top),R=$($rect.Right),B=$($rect.Bottom)"
}

function Get-CustomInstallOptionsClickPoint([object]$custom, [object]$express) {
    if (-not $custom) { return $null }
    $r = $custom.Rect
    $cy = [int](($r.Top + $r.Bottom) / 2)
    $cx = [int](($r.Left + $r.Right) / 2)
    $useLabelOffset = $false
    if (-not (Test-IsWin32RadioCandidate $custom)) {
        $useLabelOffset = $true
    } elseif ($express) {
        if ($express.Rect.Right -gt 0) {
            $labelTooFarRight = ($r.Left -gt ($express.Rect.Right + 40))
            if ($labelTooFarRight) { $useLabelOffset = $true }
        }
    }
    if ($useLabelOffset) {
        $cx = $r.Left - 18
        $cy = [int](($r.Top + $r.Bottom) / 2)
    }
    return @{ X = $cx; Y = $cy }
}

function Test-CustomClickTargetValid([hashtable]$candidates, [int]$clickX, [int]$clickY) {
    $express = $candidates.Express
    $custom = $candidates.Custom
    if (-not $custom) { return $false }
    if (-not (Test-CustomTargetTextValid ([string]$custom.Text))) { return $false }
    if (Test-IsExpressControlText ([string]$custom.Text)) { return $false }
    if ($express -and ($custom.Hwnd.ToInt64() -eq $express.Hwnd.ToInt64())) { return $false }
    if ($express -and $custom.Rect.Top -le $express.Rect.Top) { return $false }
    if ($express -and (Test-PointInsideRect $clickX $clickY $express.Rect)) { return $false }
    return $true
}

function Write-HwndClickInstallOptionsCandidatesLog([hashtable]$candidates) {
    Write-ElevatedLog '[NVIDIA-ELEVATED] Candidates:'
    foreach ($pair in @(
            @{ Key = 'Express'; Label = 'Express' },
            @{ Key = 'Custom'; Label = 'Custom' },
            @{ Key = 'Next'; Label = 'Next' }
        )) {
        $c = $candidates[$pair.Key]
        if ($c) {
            Write-ElevatedLog ("$($pair.Label): hwnd=$($c.Hwnd.ToInt64()) text='$($c.Text)' rect=$(Format-ControlRect $c)")
        } else {
            Write-ElevatedLog ("$($pair.Label): hwnd=none text='' rect=n/a")
        }
    }
}

function Invoke-TrustedHwndClick(
    [IntPtr]$rootHwnd,
    [IntPtr]$hwnd,
    [object]$rect,
    [string]$label,
    [int]$ClickX,
    [int]$ClickY
) {
    if ($hwnd -eq [IntPtr]::Zero) { return $false }
    if ($ClickX -lt 0 -or $ClickY -lt 0) {
        if (-not $rect) { return $false }
        $ClickX = [int](($rect.Left + $rect.Right) / 2)
        $ClickY = [int](($rect.Top + $rect.Bottom) / 2)
    }
    [NvidiaElevatedInput]::SetForegroundWindow($rootHwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    try {
        [NvidiaElevatedInput]::RealLeftClickAtScreen($ClickX, $ClickY)
    } catch {
        Write-ElevatedLog "[NVIDIA-ELEVATED] LEGACY CLICK failed ($label): $($_.Exception.Message)"
        return $false
    }
    Start-Sleep -Milliseconds 500
    Write-ElevatedLog "[NVIDIA-ELEVATED] LEGACY CLICK: label=$label hwnd=$($hwnd.ToInt64()) x=$ClickX y=$ClickY rect=$(Format-RawRect $rect)"
    return $true
}

function Test-BmGetCheckReliable([object]$control) {
    if (-not $control) { return $false }
    $chk = Get-ChildCheckState $control.Hwnd
    return ($null -ne $chk -and $chk -in 0, 1)
}

function Invoke-NvidiaInstallOptionsHwndClickMode([IntPtr]$rootHwnd) {
    Write-ElevatedLog '[NVIDIA-ELEVATED] LEGACY HWND CLICK MODE - no keyboard'

    $scriptDir = Split-Path -Parent $PSCommandPath
    $rootDir = Split-Path -Parent $scriptDir
    $logsDir = Join-Path $rootDir 'logs'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }
    $dumpPath = Join-Path $logsDir 'nvidia-installer-installoptions-radio-dump.txt'
    $script:InstallOptionsRadioDumpPath = [System.IO.Path]::GetFullPath($dumpPath)
    Write-ElevatedLog "[NVIDIA-ELEVATED] InstallOptions dump path: $script:InstallOptionsRadioDumpPath"

    if (-not (Invoke-ClassicNvidiaForeground $rootHwnd)) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions: NVIDIA window not foreground'
    }

    $candidates = Get-ClassicInstallOptionsCandidates $rootHwnd
    Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
    Write-HwndClickInstallOptionsCandidatesLog $candidates

    if (-not (Test-ClassicInstallOptionsGuards $rootHwnd $candidates)) {
        return $false
    }

    $express = $candidates.Express
    $custom = $candidates.Custom
    $next = $candidates.Next

    if (-not (Test-CustomTargetTextValid ([string]$custom.Text))) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] STOP safety: custom target invalid'
        Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
        Fail-Manual 'hwnd click custom target text invalid'
        return $false
    }

    $verified = Test-ClassicCustomSelected $custom $express
    if (-not $verified) {
        $clickPt = Get-CustomInstallOptionsClickPoint $custom $express
        if (-not $clickPt) {
            Write-ElevatedLog '[NVIDIA-ELEVATED] STOP safety: custom target invalid'
            Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
            Fail-Manual 'hwnd click custom click point unavailable'
            return $false
        }

        $clickX = $clickPt.X
        $clickY = $clickPt.Y
        Write-ElevatedLog "[NVIDIA-ELEVATED] Custom click point: x=$clickX y=$clickY"

        $insideExpress = if ($express) { Test-PointInsideRect $clickX $clickY $express.Rect } else { $false }
        Write-ElevatedLog "[NVIDIA-ELEVATED] Safety: custom point inside express rect = $insideExpress"

        if (-not (Test-CustomClickTargetValid $candidates $clickX $clickY)) {
            Write-ElevatedLog '[NVIDIA-ELEVATED] STOP safety: custom target invalid'
            Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
            Fail-Manual 'hwnd click custom target guards failed'
            return $false
        }

        if (-not (Invoke-TrustedHwndClick $rootHwnd $custom.Hwnd $custom.Rect 'Custom' $clickX $clickY)) {
            Write-ElevatedLog '[NVIDIA-ELEVATED] STOP safety: custom target invalid'
            Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
            Fail-Manual 'hwnd click custom mouse click failed'
            return $false
        }

        $expressChecked = if ($express) { Get-ChildCheckState $express.Hwnd } else { $null }
        $customChecked = Get-ChildCheckState $custom.Hwnd
        Write-ElevatedLog ("[NVIDIA-ELEVATED] After custom click: expressChecked=$(Format-CheckState $expressChecked) customChecked=$(Format-CheckState $customChecked)")

        $verified = Test-ClassicCustomSelected $custom $express
        if (-not $verified) {
            if (-not (Test-BmGetCheckReliable $custom) -and (Test-CustomTargetTextValid ([string]$custom.Text))) {
                Write-ElevatedLog '[NVIDIA-ELEVATED] BM_GETCHECK unreliable - second identical Custom click'
                if (-not (Invoke-TrustedHwndClick $rootHwnd $custom.Hwnd $custom.Rect 'Custom-retry' $clickX $clickY)) {
                    Write-ElevatedLog '[NVIDIA-ELEVATED] STOP safety: custom target invalid'
                    Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
                    Fail-Manual 'hwnd click custom retry failed'
                    return $false
                }
                Start-Sleep -Milliseconds 300
                $expressChecked = if ($express) { Get-ChildCheckState $express.Hwnd } else { $null }
                $customChecked = Get-ChildCheckState $custom.Hwnd
                Write-ElevatedLog ("[NVIDIA-ELEVATED] After custom retry: expressChecked=$(Format-CheckState $expressChecked) customChecked=$(Format-CheckState $customChecked)")
                $verified = Test-ClassicCustomSelected $custom $express
            }
        }
    } else {
        $expressChecked = if ($express) { Get-ChildCheckState $express.Hwnd } else { $null }
        $customChecked = Get-ChildCheckState $custom.Hwnd
        Write-ElevatedLog ("[NVIDIA-ELEVATED] After custom click: expressChecked=$(Format-CheckState $expressChecked) customChecked=$(Format-CheckState $customChecked)")
        Write-ElevatedLog '[NVIDIA-ELEVATED] Custom already selected before click'
    }

    if (-not $verified) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] STOP safety: custom target invalid'
        Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
        Fail-Manual 'hwnd click custom not verified'
        return $false
    }

    Write-ElevatedLog '[NVIDIA-ELEVATED] Click Next by hwnd/rect'
    $nextX = [int](($next.Rect.Left + $next.Rect.Right) / 2)
    $nextY = [int](($next.Rect.Top + $next.Rect.Bottom) / 2)
    if (-not (Invoke-TrustedHwndClick $rootHwnd $next.Hwnd $next.Rect 'Next' $nextX $nextY)) {
        Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
        Fail-Manual 'hwnd click next mouse click failed'
        return $false
    }

    Write-ElevatedLog '[NVIDIA-ELEVATED] Options next clicked'
    return $true
}

function Initialize-InstallOptionsDumpPath {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $rootDir = Split-Path -Parent $scriptDir
    $logsDir = Join-Path $rootDir 'logs'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }
    $dumpPath = Join-Path $logsDir 'nvidia-installer-installoptions-radio-dump.txt'
    $script:InstallOptionsRadioDumpPath = [System.IO.Path]::GetFullPath($dumpPath)
    Write-ElevatedLog "[NVIDIA-ELEVATED] InstallOptions dump path: $script:InstallOptionsRadioDumpPath"
}

function Test-LegacyInstallOptionsPageText([IntPtr]$rootHwnd) {
    $hasOptions = $false
    $hasExpress = $false
    $hasCustom = $false
    foreach ($c in (Get-ClassicInstallOptionsChildren $rootHwnd)) {
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if ($text -match '(?i)Options d''installation|Options d installation|Installation Options') { $hasOptions = $true }
        if ($text -match '(?i)Expresse|Express') { $hasExpress = $true }
        if ($text -match '(?i)Personnalisée|Personnalisee|Custom') { $hasCustom = $true }
    }
    return @{
        HasOptions = $hasOptions
        HasExpress = $hasExpress
        HasCustom  = $hasCustom
        Ok         = ($hasOptions -and $hasExpress -and $hasCustom)
    }
}

function Invoke-LegacyActivateNvidiaWindow([IntPtr]$rootHwnd, [string]$title) {
    [NvidiaWin32Msaa]::SetForegroundWindow($rootHwnd) | Out-Null
    Start-Sleep -Milliseconds 250
    if (-not [NvidiaElevatedInput]::IsRootOrDescendantForeground($rootHwnd)) {
        try {
            $ws = New-Object -ComObject WScript.Shell
            if ($title) { [void]$ws.AppActivate($title) }
            Start-Sleep -Milliseconds 250
        } catch {}
    }
    return [NvidiaElevatedInput]::IsRootOrDescendantForeground($rootHwnd)
}

function Invoke-LegacySendAltP([IntPtr]$rootHwnd) {
    if (-not (Invoke-LegacyActivateNvidiaWindow $rootHwnd ([NvidiaWin32Msaa]::GetWndText($rootHwnd)))) {
        return $false
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
        Write-ElevatedLog '[NVIDIA-ELEVATED] LEGACY send ALT+P'
        [System.Windows.Forms.SendKeys]::SendWait('%P')
        Start-Sleep -Milliseconds 500
        return $true
    } catch {
        Write-ElevatedLog "[NVIDIA-ELEVATED] LEGACY ALT+P failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-LegacyFocusedControlText([IntPtr]$rootHwnd) {
    $focus = [NvidiaElevatedInput]::GetFocus()
    if ($focus -eq [IntPtr]::Zero) { return '' }
    if (-not [NvidiaElevatedInput]::IsDescendantOf($focus, $rootHwnd)) { return '' }
    return [NvidiaElevatedInput]::GetWndTextLocal($focus)
}

function Test-LegacyFocusIsSuivant([IntPtr]$rootHwnd) {
    $text = Get-LegacyFocusedControlText $rootHwnd
    if (-not $text) { return $false }
    return (Test-IsNextControlText $text)
}

function Invoke-LegacyClickSuivant([IntPtr]$rootHwnd, [object]$nextBtn) {
    if (-not (Invoke-LegacyActivateNvidiaWindow $rootHwnd ([NvidiaWin32Msaa]::GetWndText($rootHwnd)))) {
        return $false
    }

    if ($nextBtn) {
        $nextText = [string]$nextBtn.Text
        [NvidiaWin32Msaa]::SetFocus($nextBtn.Hwnd) | Out-Null
        Start-Sleep -Milliseconds 100
        [NvidiaElevatedInput]::SendBmClick($nextBtn.Hwnd)
        $parent = [NvidiaWin32Msaa]::GetParent($nextBtn.Hwnd)
        if ($parent -eq [IntPtr]::Zero) { $parent = $rootHwnd }
        [NvidiaElevatedInput]::SendWmCommandClicked($parent, $nextBtn.Hwnd)
        Start-Sleep -Milliseconds 400
        return $true
    }

    $nextFromScan = Find-ClassicInstallOptionsControl (Get-ClassicInstallOptionsChildren $rootHwnd) { param($t) Test-IsNextControlText $t } -PreferLongest
    if ($nextFromScan) {
        return (Invoke-LegacyClickSuivant $rootHwnd $nextFromScan)
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
        if ($nextBtn -and [string]$nextBtn.Text -match '^&') {
            Write-ElevatedLog '[NVIDIA-ELEVATED] LEGACY send ALT+S for SUIVANT'
            [System.Windows.Forms.SendKeys]::SendWait('%S')
            Start-Sleep -Milliseconds 400
            return $true
        }
        if (Test-LegacyFocusIsSuivant $rootHwnd) {
            Write-ElevatedLog '[NVIDIA-ELEVATED] LEGACY send Enter on focused SUIVANT'
            [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
            Start-Sleep -Milliseconds 400
            return $true
        }
    } catch {
        Write-ElevatedLog "[NVIDIA-ELEVATED] LEGACY SUIVANT keyboard failed: $($_.Exception.Message)"
    }
    return $false
}

function Invoke-NvidiaInstallOptionsLegacyStandalone([IntPtr]$rootHwnd) {
    Write-ElevatedLog '[NVIDIA-ELEVATED] LEGACY InstallOptions standalone mode'
    Initialize-InstallOptionsDumpPath

    if ($rootHwnd -eq [IntPtr]::Zero) {
        $waitDeadline = (Get-Date).AddSeconds(45)
        while ((Get-Date) -lt $waitDeadline -and $rootHwnd -eq [IntPtr]::Zero) {
            $rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
            if ($rootHwnd -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 300 }
        }
    }

    if ($rootHwnd -eq [IntPtr]::Zero) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] LEGACY: Personnalisee non verifiee, stop securite'
        Fail-Manual 'legacy nvidia installer window not found'
        return $false
    }

    $title = [NvidiaWin32Msaa]::GetWndText($rootHwnd)
    Write-ElevatedLog "[NVIDIA-ELEVATED] LEGACY window found: hwnd=$($rootHwnd.ToInt64()) title='$title'"

    if (-not (Invoke-LegacyActivateNvidiaWindow $rootHwnd $title)) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] LEGACY: could not activate NVIDIA window'
    }

    $pageCheck = Test-LegacyInstallOptionsPageText $rootHwnd
    Write-ElevatedLog "[NVIDIA-ELEVATED] LEGACY page text contains Options/Express/Personnalisee = $($pageCheck.Ok)"
    if (-not $pageCheck.Ok) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] STOP safety: custom target invalid'
        Fail-Manual 'legacy install options page text missing'
        return $false
    }

    return (Invoke-NvidiaInstallOptionsHwndClickMode $rootHwnd)
}

function Get-ClassicInstallOptionsChildren([IntPtr]$rootHwnd) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        if (-not [NvidiaElevatedInput]::IsDescendantOf($c.Hwnd, $rootHwnd)) { continue }
        if (Test-IsSidebarStepLabel $c $rootHwnd) { continue }
        $list.Add($c) | Out-Null
    }
    return $list.ToArray()
}

function Find-ClassicInstallOptionsControl(
    [object[]]$allChildren,
    [scriptblock]$TextMatcher,
    [switch]$PreferLongest
) {
    $best = $null
    $bestLen = if ($PreferLongest) { -1 } else { [int]::MaxValue }
    foreach ($c in $allChildren) {
        if (-not $c.Visible -or -not $c.Enabled) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not $text) { continue }
        if (-not (& $TextMatcher $text)) { continue }
        if ($PreferLongest) {
            if ($text.Length -gt $bestLen) { $best = $c; $bestLen = $text.Length }
        } elseif ($text.Length -le $bestLen) {
            $best = $c; $bestLen = $text.Length
        }
    }
    return $best
}

function Get-ClassicInstallOptionsCandidates([IntPtr]$rootHwnd) {
    $all = Get-ClassicInstallOptionsChildren $rootHwnd
    $express = Find-ClassicInstallOptionsControl $all { param($t) Test-IsExpressControlText $t } -PreferLongest
    $custom = Find-ClassicInstallOptionsControl $all { param($t) Test-IsStrictCustomControlText $t } -PreferLongest
    $next = Find-ClassicInstallOptionsControl $all { param($t) Test-IsNextControlText $t } -PreferLongest
    return @{
        Express = $express
        Custom  = $custom
        Next    = $next
        All     = $all
    }
}

function Write-ClassicInstallOptionsCandidatesLog([hashtable]$candidates) {
    Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions candidates:'
    foreach ($pair in @(
            @{ Key = 'Express'; Label = 'Express' },
            @{ Key = 'Custom'; Label = 'Custom' },
            @{ Key = 'Next'; Label = 'Next' }
        )) {
        $c = $candidates[$pair.Key]
        if ($c) {
            $chk = Get-ChildCheckState $c.Hwnd
            Write-ElevatedLog ("$($pair.Label): hwnd=$($c.Hwnd.ToInt64()) class='$($c.ClassName)' text='$($c.Text)' rect=$(Format-ControlRect $c) checked=$(Format-CheckState $chk)")
        } else {
            Write-ElevatedLog ("$($pair.Label): hwnd=none class=none text=none rect=n/a checked=unknown")
        }
    }
}

function Write-ClassicInstallOptionsRadioDump([IntPtr]$rootHwnd, [hashtable]$candidates) {
    if ($script:InstallOptionsRadioDumpPath) {
        $path = $script:InstallOptionsRadioDumpPath
    } else {
        $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        $scriptDir = Split-Path -Parent $scriptPath
        $rootDir = Split-Path -Parent $scriptDir
        $logsDir = Join-Path $rootDir 'logs'
        if (-not (Test-Path -LiteralPath $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }
        $path = Join-Path $logsDir 'nvidia-installer-installoptions-radio-dump.txt'
    }
    $dumpDir = Split-Path -Parent $path
    if ($dumpDir -and -not (Test-Path -LiteralPath $dumpDir)) {
        New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('MODE=classic-powershell-win32') | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    $lines.Add('--- CANDIDATES ---') | Out-Null
    foreach ($key in @('Express', 'Custom', 'Next')) {
        $c = $candidates[$key]
        if ($c) {
            $chk = Get-ChildCheckState $c.Hwnd
            $lines.Add("$key`: hwnd=$($c.Hwnd.ToInt64()) class='$($c.ClassName)' text='$($c.Text)' rect=$(Format-ControlRect $c) visible=$($c.Visible) enabled=$($c.Enabled) checked=$(Format-CheckState $chk)") | Out-Null
        } else {
            $lines.Add("$key`: none") | Out-Null
        }
    }
    $lines.Add('--- ALL VISIBLE CHILDREN ---') | Out-Null
    foreach ($c in $candidates.All) {
        $chk = Get-ChildCheckState $c.Hwnd
        $lines.Add("HWND=$($c.Hwnd.ToInt64()) | class='$($c.ClassName)' | text='$($c.Text)' | rect=$(Format-ControlRect $c) | visible=$($c.Visible) | enabled=$($c.Enabled) | style=$($c.Style) | checked=$(Format-CheckState $chk) | parent=$($c.ParentHwnd)") | Out-Null
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
    Write-ElevatedLog "[NVIDIA-ELEVATED] InstallOptions dump path: $path"
    Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions radio dump written'
}

function Test-ClassicCustomSelected([object]$customHwnd, [object]$expressHwnd) {
    if (-not $customHwnd) { return $false }
    $customChecked = Get-ChildCheckState $customHwnd.Hwnd
    $expressChecked = if ($expressHwnd) { Get-ChildCheckState $expressHwnd.Hwnd } else { $null }
    return ($customChecked -eq [NvidiaElevatedInput]::BST_CHECKED -and
        ($null -eq $expressChecked -or $expressChecked -ne [NvidiaElevatedInput]::BST_CHECKED))
}

function Test-ClassicInstallOptionsGuards([IntPtr]$rootHwnd, [hashtable]$candidates) {
    $express = $candidates.Express
    $custom = $candidates.Custom
    $next = $candidates.Next

    if (-not $custom -or -not $next) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions: custom or next hwnd missing'
        Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
        Fail-Manual 'classic install options custom or next missing'
        return $false
    }

    $customText = [string]$custom.Text
    if (Test-IsExpressControlText $customText) {
        Write-ElevatedLog "[NVIDIA-ELEVATED] InstallOptions: custom text contains Express: '$customText'"
        Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
        Fail-Manual 'classic custom hwnd text contains Express'
        return $false
    }

    if ($express -and ($custom.Hwnd.ToInt64() -eq $express.Hwnd.ToInt64())) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions: custom hwnd equals express hwnd'
        Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
        Fail-Manual 'classic custom equals express'
        return $false
    }

    if ($express -and $custom.Rect.Top -le $express.Rect.Top) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions: custom rect not below express rect'
        Write-ClassicInstallOptionsRadioDump $rootHwnd $candidates
        Fail-Manual 'classic custom geometry invalid'
        return $false
    }

    return $true
}

function Invoke-ClassicNvidiaForeground([IntPtr]$rootHwnd) {
    [NvidiaWin32Msaa]::SetForegroundWindow($rootHwnd) | Out-Null
    Start-Sleep -Milliseconds 250
    return [NvidiaElevatedInput]::IsRootOrDescendantForeground($rootHwnd)
}

function Invoke-ClassicCustomBmClick([IntPtr]$rootHwnd, [object]$customHwnd) {
    if (-not (Invoke-ClassicNvidiaForeground $rootHwnd)) {
        Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions: NVIDIA window not foreground for BM_CLICK'
        return $false
    }
    [NvidiaWin32Msaa]::SetFocus($customHwnd.Hwnd) | Out-Null
    Start-Sleep -Milliseconds 100
    Write-ElevatedLog '[NVIDIA-ELEVATED] Try BM_CLICK custom'
    [NvidiaElevatedInput]::SendBmClick($customHwnd.Hwnd)
    Start-Sleep -Milliseconds 500
    return $true
}

function Invoke-ClassicCustomBmSetCheckWmCommand([IntPtr]$rootHwnd, [object]$customHwnd, [object]$expressHwnd) {
    if (-not (Invoke-ClassicNvidiaForeground $rootHwnd)) { return $false }
    Write-ElevatedLog '[NVIDIA-ELEVATED] Try BM_SETCHECK + WM_COMMAND custom'
    [NvidiaElevatedInput]::SetButtonCheck($customHwnd.Hwnd, [NvidiaElevatedInput]::BST_CHECKED)
    if ($expressHwnd) {
        [NvidiaElevatedInput]::SetButtonCheck($expressHwnd.Hwnd, [NvidiaElevatedInput]::BST_UNCHECKED)
    }
    $parent = [NvidiaWin32Msaa]::GetParent($customHwnd.Hwnd)
    if ($parent -eq [IntPtr]::Zero) { $parent = $rootHwnd }
    [NvidiaElevatedInput]::SendWmCommandClicked($parent, $customHwnd.Hwnd)
    Start-Sleep -Milliseconds 500
    return $true
}

function Invoke-ClassicCustomKeyboardAccessKey([IntPtr]$rootHwnd, [object]$customHwnd) {
    if (-not (Invoke-ClassicNvidiaForeground $rootHwnd)) { return $false }
    Write-ElevatedLog '[NVIDIA-ELEVATED] Try keyboard access key for Personnalisee (Alt+P)'
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
        [NvidiaWin32Msaa]::SetFocus($rootHwnd) | Out-Null
        Start-Sleep -Milliseconds 150
        $accessKey = 'P'
        if ($customHwnd.Text -match '^&(.).') { $accessKey = $Matches[1] }
        [System.Windows.Forms.SendKeys]::SendWait("%$accessKey")
        Start-Sleep -Milliseconds 500
        return $true
    } catch {
        Write-ElevatedLog "[NVIDIA-ELEVATED] Keyboard access key failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-ClassicCustomKeyboardDownEnter([IntPtr]$rootHwnd) {
    if (-not (Invoke-ClassicNvidiaForeground $rootHwnd)) { return $false }
    Write-ElevatedLog '[NVIDIA-ELEVATED] Try keyboard Down+Enter in NVIDIA window'
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
        [NvidiaWin32Msaa]::SetFocus($rootHwnd) | Out-Null
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.SendKeys]::SendWait('{DOWN}{ENTER}')
        Start-Sleep -Milliseconds 500
        return $true
    } catch {
        Write-ElevatedLog "[NVIDIA-ELEVATED] Keyboard Down+Enter failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-ClassicNextBmClick([IntPtr]$rootHwnd, [object]$nextHwnd) {
    if (-not (Invoke-ClassicNvidiaForeground $rootHwnd)) { return $false }
    [NvidiaWin32Msaa]::SetFocus($nextHwnd.Hwnd) | Out-Null
    [NvidiaElevatedInput]::SendBmClick($nextHwnd.Hwnd)
    $parent = [NvidiaWin32Msaa]::GetParent($nextHwnd.Hwnd)
    if ($parent -eq [IntPtr]::Zero) { $parent = $rootHwnd }
    [NvidiaElevatedInput]::SendWmCommandClicked($parent, $nextHwnd.Hwnd)
    Start-Sleep -Milliseconds 400
    return $true
}

function Invoke-NvidiaInstallOptionsClassicPowerShell([IntPtr]$rootHwnd) {
    Write-ElevatedLog '[NVIDIA-ELEVATED] InstallOptions classic PowerShell mode (delegating to HWND click mode)'
    return (Invoke-NvidiaInstallOptionsHwndClickMode $rootHwnd)
}

function Find-ChildByPatterns(
    [IntPtr]$rootHwnd,
    [string[]]$Patterns,
    [scriptblock]$ExtraFilter = $null,
    [switch]$PreferShortest
) {
    $best = $null
    $bestLen = [int]::MaxValue
    foreach ($c in (Get-VisibleChildren $rootHwnd)) {
        if (-not $c.Enabled) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not $text) { continue }
        $matched = $false
        foreach ($p in $Patterns) {
            if ($text -match $p) { $matched = $true; break }
        }
        if (-not $matched) { continue }
        if ($ExtraFilter -and -not (& $ExtraFilter $text $c)) { continue }
        if ($PreferShortest) {
            if ($text.Length -le $bestLen) { $best = $c; $bestLen = $text.Length }
        } else {
            return $c
        }
    }
    return $best
}

function Test-AcceptButtonText([string]$text) {
    $norm = Normalize-Text $text
    $hasAccept = ($norm -match 'accepter|accept') -or ($text -match '(?i)ACCEPTER|Accept')
    $hasContinue = ($norm -match 'continuer|continue') -or ($text -match '(?i)CONTINUER|Continue')
    return ($hasAccept -and $hasContinue)
}

function Get-RootWindowRect([IntPtr]$rootHwnd) {
    $rectType = [NvidiaElevatedInput+RECT]
    $r = New-Object $rectType
    if ([NvidiaElevatedInput]::GetWindowRect($rootHwnd, [ref]$r)) { return $r }
    return $null
}

function Test-IsSidebarStepLabel([object]$childInfo, [IntPtr]$rootHwnd) {
    if (-not $childInfo) { return $false }
    $text = if ($childInfo.Text) { [string]$childInfo.Text } else { '' }
    if (-not $text) { return $false }
    # NVIDIA wizard sidebar step labels use this ATL class (not action buttons).
    if ($childInfo.ClassName -match '6E016A48') { return $true }
    $rootRect = Get-RootWindowRect $rootHwnd
    if ($rootRect) {
        $rootW = $rootRect.Right - $rootRect.Left
        if ($rootW -gt 0) {
            $sidebarMaxRight = $rootRect.Left + [int]($rootW * 0.28)
            if ($childInfo.Rect.Right -le $sidebarMaxRight) { return $true }
        }
    }
    return $false
}

function Test-IsActionButton([object]$childInfo) {
    if (-not $childInfo -or -not $childInfo.Enabled) { return $false }
    if ($childInfo.ClassName -match '6E0165C8') { return $true }
    $text = if ($childInfo.Text) { [string]$childInfo.Text } else { '' }
    if ($text -match '^&') { return $true }
    return $false
}

function Test-ActiveNavButtonVisible([IntPtr]$rootHwnd) {
    if (Test-AcceptButtonVisible $rootHwnd) { return $true }
    $next = Find-ChildByPatterns $rootHwnd @('(?i)^&?SUIVANT$|^&?Suivant$|^&Next$|^Next$') -PreferShortest
    if ($next) { return $true }
    $custom = Find-ChildByPatterns $rootHwnd @('(?i)&Personnalis|Personnalisée|Custom \(Advanced\)|&Custom') -PreferShortest
    if ($custom) { return $true }
    return $false
}

function Test-LicensePage([IntPtr]$rootHwnd) {
    if (Test-AcceptButtonVisible $rootHwnd) { return $true }
    $hasLicense = $false
    foreach ($c in (Get-VisibleChildren $rootHwnd)) {
        if (Test-IsSidebarStepLabel $c $rootHwnd) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if ($text -match '(?i)Contrat de licence du logiciel NVIDIA|Contrat de licence|License Agreement|NVIDIA Driver License Agreement') {
            $hasLicense = $true
        }
    }
    return ($hasLicense -and (Test-AcceptButtonVisible $rootHwnd))
}

function Find-AcceptButton([IntPtr]$rootHwnd) {
    $best = $null
    $bestLen = [int]::MaxValue
    foreach ($c in (Get-VisibleChildren $rootHwnd)) {
        if (-not $c.Enabled) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not (Test-AcceptButtonText $text)) { continue }
        if ($text.Length -le $bestLen) { $best = $c; $bestLen = $text.Length }
    }
    return $best
}

function Test-AcceptButtonVisible([IntPtr]$rootHwnd) {
    return ($null -ne (Find-AcceptButton $rootHwnd))
}

function Test-OptionsPage([IntPtr]$rootHwnd) {
    if (Test-AcceptButtonVisible $rootHwnd) { return $false }
    if (Test-CustomOptionsPageMarkersOnly $rootHwnd) { return $false }
    $candidates = Get-ClassicInstallOptionsCandidates $rootHwnd
    return ($null -ne $candidates.Express -and $null -ne $candidates.Custom -and $null -ne $candidates.Next)
}

function Test-CustomOptionsPageMarkersOnly([IntPtr]$rootHwnd) {
    foreach ($c in (Get-VisibleChildren $rootHwnd)) {
        if (Test-IsSidebarStepLabel $c $rootHwnd) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if ($text -match '(?i)Options d''installation personnalisée|Options d installation personnalisée|Options personnalisées|Custom installation options|Pilote graphique|Effectuer une nouvelle installation|Perform a clean install|Graphics Driver') {
            return $true
        }
    }
    return $false
}

function Find-NextButton([IntPtr]$rootHwnd) {
    return Find-ChildByPatterns $rootHwnd @('(?i)^&?SUIVANT$|^&?Suivant$|^&Next$|^Next$') -PreferShortest
}

function Test-CustomOptionsPage([IntPtr]$rootHwnd) {
    if (Test-AcceptButtonVisible $rootHwnd) { return $false }
    if (Test-OptionsPage $rootHwnd) { return $false }
    $hasPageMarker = Test-CustomOptionsPageMarkersOnly $rootHwnd
    $hasNext = ($null -ne (Find-NextButton $rootHwnd))
    return ($hasPageMarker -and $hasNext)
}

function Test-InstallingPage([IntPtr]$rootHwnd) {
    if (Test-AcceptButtonVisible $rootHwnd) { return $false }
    if (Test-OptionsPage $rootHwnd) { return $false }
    if (Test-CustomOptionsPage $rootHwnd) { return $false }
    foreach ($c in (Get-VisibleChildren $rootHwnd)) {
        if (Test-IsSidebarStepLabel $c $rootHwnd) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if ($text -match '(?i)Installation en cours|Installing|Preparing to install|Installation du pilote') {
            return $true
        }
    }
    return $false
}

function Test-RealFinalPage([IntPtr]$rootHwnd) {
    # Never final while wizard navigation controls are still active.
    if (Test-AcceptButtonVisible $rootHwnd) { return $false }
    if (Test-OptionsPage $rootHwnd) { return $false }
    if (Test-CustomOptionsPage $rootHwnd) { return $false }
    if (Test-ActiveNavButtonVisible $rootHwnd) { return $false }

    foreach ($c in (Get-VisibleChildren $rootHwnd)) {
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not $text) { continue }
        if (Test-IsSidebarStepLabel $c $rootHwnd) { continue }

        if (Test-IsActionButton $c) {
            if ($text -match '(?i)^&?Terminer$|^&?Finish$') { return $true }
        }
        if ($text -match '(?i)Installation terminée|Installation terminee|Installation complete|The NVIDIA installer has finished|has finished installing') {
            return $true
        }
    }
    return $false
}

function Get-ElevatedPageState([IntPtr]$rootHwnd) {
    if (Test-LicensePage $rootHwnd) { return 'License' }
    if (Test-OptionsPage $rootHwnd) { return 'InstallOptions' }
    if (Test-CustomOptionsPage $rootHwnd) { return 'CustomOptions' }
    if (Test-InstallingPage $rootHwnd) { return 'Installing' }
    if (Test-RealFinalPage $rootHwnd) { return 'Final' }
    return 'Unknown'
}

function Write-StateChangeLog([string]$State) {
    if ($State -eq $script:LastLoggedState) { return }
    $script:LastLoggedState = $State
    Write-ElevatedLog "[NVIDIA-ELEVATED] State detected = $State"
}

function Write-StateDump([IntPtr]$rootHwnd) {
    $logsDir = Split-Path -Parent $HelperLogPath
    $path = Join-Path $logsDir 'nvidia-installer-elevated-state-dump.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    $lines.Add('DETECTED_STATE=' + (Get-ElevatedPageState $rootHwnd)) | Out-Null
    $lines.Add('--- VISIBLE CHILDREN ---') | Out-Null
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        $rect = "L$($c.Rect.Left),T$($c.Rect.Top),R$($c.Rect.Right),B$($c.Rect.Bottom)"
        $sidebar = Test-IsSidebarStepLabel $c $rootHwnd
        $lines.Add(
            "HWND=$($c.Hwnd.ToInt64()) | class='$($c.ClassName)' | text='$($c.Text)' | visible=$($c.Visible) | enabled=$($c.Enabled) | rect=$rect | parent=$($c.ParentHwnd) | sidebar=$sidebar"
        ) | Out-Null
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
    Write-ElevatedLog "[NVIDIA-ELEVATED] State dump written: $path"
}

function Write-Win32Dump([IntPtr]$rootHwnd, [string]$suffix) {
    $logsDir = Split-Path -Parent $HelperLogPath
    $path = Join-Path $logsDir ("nvidia-installer-elevated-$suffix-win32-dump.txt")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        $rect = "L$($c.Rect.Left),T$($c.Rect.Top),R$($c.Rect.Right),B$($c.Rect.Bottom)"
        $lines.Add("HWND=$($c.Hwnd.ToInt64()) | class='$($c.ClassName)' | text='$($c.Text)' | enabled=$($c.Enabled) | rect=$rect | id=$($c.ControlId)") | Out-Null
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
    Write-ElevatedLog "[NVIDIA-ELEVATED] Win32 dump written: $path"
}

function Invoke-ElevatedRealClick([IntPtr]$rootHwnd, [object]$childInfo, [string]$label) {
    if (-not $childInfo) { return $false }
    [NvidiaElevatedInput]::SetForegroundWindow($rootHwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    if (-not [NvidiaElevatedInput]::IsRootOrDescendantForeground($rootHwnd)) {
        Write-ElevatedLog "[NVIDIA-ELEVATED] Foreground check failed before click: $label"
        return $false
    }
    $rectType = [NvidiaElevatedInput+RECT]
    $r = New-Object $rectType
    if (-not [NvidiaElevatedInput]::GetWindowRect($childInfo.Hwnd, [ref]$r)) {
        Write-ElevatedLog "[NVIDIA-ELEVATED] GetWindowRect failed: $label"
        return $false
    }
    $cx = [int](($r.Left + $r.Right) / 2)
    $cy = [int](($r.Top + $r.Bottom) / 2)
    Write-ElevatedLog "[NVIDIA-ELEVATED] Click target $label hwnd=$($childInfo.Hwnd.ToInt64()) text='$($childInfo.Text)' center=$cx,$cy"
    try {
        [NvidiaElevatedInput]::RealLeftClickAtScreen($cx, $cy)
    } catch {
        Write-ElevatedLog "[NVIDIA-ELEVATED] Real click failed ($label): $($_.Exception.Message)"
        return $false
    }
    return $true
}

function Complete-InstallSuccess {
    Write-ElevatedLog '[NVIDIA-ELEVATED] Installation final state detected'
    Write-ElevatedLog 'Installation NVIDIA terminée � validation finale manuelle si demandée.'
    Set-MainLogField 'NV_PROGRESS_PCT' '100'
    Set-MainLogField 'NVIDIA_INSTALL_FINAL' 'oui'
    Set-MainLogField 'NVIDIA_TICK_RESULT' 'finished'
    Set-MainLogField 'NVIDIA_ELEVATED_RESULT' 'finished'
}

function Fail-Manual([string]$Reason) {
    Write-ElevatedLog "[NVIDIA-ELEVATED] Manual required: $Reason"
    Set-MainLogField 'NVIDIA_TICK_RESULT' 'manual'
    Set-MainLogField 'NVIDIA_ELEVATED_RESULT' 'manual'
}

# --- Main ---
Write-ElevatedLog '[NVIDIA-ELEVATED] Helper started'
Write-ElevatedLog ("[NVIDIA-ELEVATED] Running as admin=" + (Test-IsAdmin))

if (-not (Test-IsAdmin)) {
    Write-ElevatedLog '[NVIDIA-ELEVATED] Not running as admin � aborting'
    Fail-Manual 'helper not elevated'
    exit 3
}

try {
    Ensure-HelperTypes
    [NvidiaElevatedInput]::EnableDpiAwareness()
} catch {
    Write-ElevatedLog "[NVIDIA-ELEVATED] Init failed: $($_.Exception.Message)"
    Fail-Manual 'helper init failed'
    exit 4
}

Set-MainLogField 'NVIDIA_ELEVATED_HELPER' 'started'
Write-ElevatedLog 'Installation NVIDIA en cours...'
Set-MainLogField 'NV_PROGRESS_PCT' '90'

$deadline = (Get-Date).AddSeconds($script:MaxRuntimeSec)
while ((Get-Date) -lt $deadline) {
    $rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
    if ($rootHwnd -eq [IntPtr]::Zero) {
        if ($script:SawWindow -and ($script:CustomDone -or $script:LastLoggedState -in @('Installing', 'Final'))) {
            Complete-InstallSuccess
            exit 0
        }
        Start-Sleep -Milliseconds $script:PollMs
        continue
    }

    if (-not $script:SawWindow) {
        $script:SawWindow = $true
        $title = [NvidiaWin32Msaa]::GetWndText($rootHwnd)
        Write-ElevatedLog "[NVIDIA-ELEVATED] NVIDIA installer window found: title='$title' hwnd=$($rootHwnd.ToInt64())"
        Write-ElevatedLog '[NVIDIA-INSTALLER] Wizard relay active � Programme d''installation NVIDIA detected after NVCleanstall'
    }

    $pageState = Get-ElevatedPageState $rootHwnd
    $prevState = $script:LastLoggedState
    Write-StateChangeLog $pageState
    if ($pageState -eq 'Unknown' -and $prevState -ne 'Unknown') {
        Write-StateDump $rootHwnd
    }

    switch ($pageState) {
        'License' {
            Write-ElevatedLog '[NVIDIA-ELEVATED] License page detected'
            $accept = Find-AcceptButton $rootHwnd
            if (-not $accept) {
                Write-Win32Dump $rootHwnd 'license'
                Fail-Manual 'license accept button not found'
                exit 16
            }
            if (Invoke-ElevatedRealClick $rootHwnd $accept 'license-accept') {
                Start-Sleep -Milliseconds 700
                Write-ElevatedLog '[NVIDIA-ELEVATED] License accept clicked'
            } else {
                Write-Win32Dump $rootHwnd 'license'
                Fail-Manual 'license accept click failed'
                exit 16
            }
            Start-Sleep -Milliseconds $script:PollMs
            continue
        }
        'InstallOptions' {
            if (-not $script:OptionsDone) {
                Write-ElevatedLog '[NVIDIA-ELEVATED] Options page detected'
                if (Invoke-InstallOptionsStep $rootHwnd) {
                    $script:OptionsDone = $true
                } else {
                    exit 16
                }
            }
            Start-Sleep -Milliseconds $script:PollMs
            continue
        }
        'CustomOptions' {
            if (-not $script:CustomDone) {
                Write-ElevatedLog '[NVIDIA-ELEVATED] Custom options page detected'
                $next = Find-NextButton $rootHwnd
                if (-not $next) {
                    Write-Win32Dump $rootHwnd 'custom-options'
                    Fail-Manual 'custom options next not found'
                    exit 16
                }
                if (-not (Invoke-ElevatedRealClick $rootHwnd $next 'custom-options-next')) {
                    Write-Win32Dump $rootHwnd 'custom-options'
                    Fail-Manual 'custom options next click failed'
                    exit 16
                }
                Write-ElevatedLog '[NVIDIA-ELEVATED] Custom options next clicked'
                $script:CustomDone = $true
                Set-MainLogField 'NV_PROGRESS_PCT' '95'
                Start-Sleep -Milliseconds 700
            }
            Start-Sleep -Milliseconds $script:PollMs
            continue
        }
        'Installing' {
            $now = [DateTime]::UtcNow
            if (-not $script:LastInstallLogUtc -or (($now - $script:LastInstallLogUtc).TotalSeconds -ge 10)) {
                $script:LastInstallLogUtc = $now
                Write-ElevatedLog '[NVIDIA-ELEVATED] Installation running'
                Set-MainLogField 'NVIDIA_TICK_RESULT' 'installing'
            }
            Start-Sleep -Milliseconds $script:PollMs
            continue
        }
        'Final' {
            Complete-InstallSuccess
            exit 0
        }
        default {
            Start-Sleep -Milliseconds $script:PollMs
            continue
        }
    }
}

Write-ElevatedLog '[NVIDIA-ELEVATED] Timeout waiting for NVIDIA installer completion'
Set-MainLogField 'NVIDIA_ELEVATED_RESULT' 'timeout'
Set-MainLogField 'NVIDIA_TICK_RESULT' 'manual'
exit 17
