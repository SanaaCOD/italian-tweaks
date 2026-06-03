#Requires -Version 5.1
<#
.SYNOPSIS
  Automates HIDUSBF Setup.exe (/all) via Win32/UIA — no mouse coordinates.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$ParamFile = '',
    [string]$ResultPath = '',
    [string]$DeviceInstanceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = '',
    [ValidateSet(1000, 8000)]
    [int]$Rate = 1000,
    [ValidateSet('Apply', 'Restore')]
    [string]$Mode = 'Apply'
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

if (-not ([System.Management.Automation.PSTypeName]'HidusbfUiHelper').Type) {
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class HidusbfUiHelper
{
    public delegate bool EnumWndProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWndProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWndProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public const uint BM_CLICK = 0x00F5;
    public const uint BM_GETCHECK = 0x00F0;
    public const uint BM_SETCHECK = 0x00F1;
    public const int BST_CHECKED = 1;
    public const int BST_UNCHECKED = 0;

    public const uint CB_GETCOUNT = 0x0146;
    public const uint CB_GETLBTEXT = 0x0148;
    public const uint CB_GETLBTEXTLEN = 0x0149;
    public const uint CB_FINDSTRINGEXACT = 0x0158;
    public const uint CB_SELECTSTRING = 0x014D;
    public const uint CB_GETCURSEL = 0x0147;
    public const uint CB_SETCURSEL = 0x014E;
    public const uint CB_GETLBTEXTW = 0x0147 + 0x0400 - 0x0147 + 0x0148; // use unicode variants below
    public const uint CB_GETLBTEXTW_EX = 0x0148 + 0x0400;
    public const uint CB_FINDSTRINGEXACTW = 0x0158 + 0x0400;
    public const uint CB_SELECTSTRINGW = 0x014D + 0x0400;

    public const int LVM_FIRST = 0x1000;
    public const int LVM_GETITEMCOUNT = LVM_FIRST + 4;
    public const int LVM_GETITEMTEXTW = LVM_FIRST + 115;
    public const int LVM_SETITEMSTATE = LVM_FIRST + 43;
    public const int LVM_ENSUREVISIBLE = LVM_FIRST + 19;
    public const int LVM_GETHEADER = LVM_FIRST + 31;

    public const int LVIF_TEXT = 0x0001;
    public const int LVIS_SELECTED = 0x0002;
    public const int LVIS_FOCUSED = 0x0001;
    public const int SW_SHOW = 5;
    public const int SW_HIDE = 0;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct LVITEMW
    {
        public int mask;
        public int iItem;
        public int iSubItem;
        public int state;
        public int stateMask;
        public IntPtr pszText;
        public int cchTextMax;
        public int iImage;
        public IntPtr lParam;
        public int iIndent;
        public int iGroupId;
        public int cColumns;
        public IntPtr puColumns;
    }

    public static string GetWndText(IntPtr hWnd)
    {
        var sb = new StringBuilder(1024);
        GetWindowText(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string GetWndClass(IntPtr hWnd)
    {
        var sb = new StringBuilder(256);
        GetClassName(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static IntPtr FindSetupWindow()
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) =>
        {
            if (!IsWindowVisible(h)) return true;
            string t = GetWndText(h);
            if (t.IndexOf("USB Devices Rate Setup", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                found = h;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static IntPtr FindChildByClass(IntPtr parent, string className)
    {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(parent, (h, l) =>
        {
            if (GetWndClass(h).Equals(className, StringComparison.OrdinalIgnoreCase))
            {
                found = h;
                return false;
            }
            IntPtr inner = FindChildByClass(h, className);
            if (inner != IntPtr.Zero)
            {
                found = inner;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr hWnd);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    public static bool IsListClassName(string cls)
    {
        if (string.IsNullOrEmpty(cls)) return false;
        string c = cls.ToLowerInvariant();
        return c.Contains("syslistview32") || c.Contains("listview") || c.Contains("listbox")
            || c.Contains("thunder") || c.Contains("windowsforms10");
    }

    public static string FormatRect(IntPtr hWnd)
    {
        RECT r;
        if (!GetWindowRect(hWnd, out r)) return "";
        return r.Left + "," + r.Top + "," + r.Right + "," + r.Bottom;
    }

    public static void CollectDescendants(IntPtr root, int depth, int maxDepth, System.Collections.ArrayList output)
    {
        if (depth > maxDepth) return;
        EnumChildWindows(root, (h, l) =>
        {
            string cls = GetWndClass(h);
            string txt = GetWndText(h).Replace("|", "/");
            string line = "hwnd=" + h.ToInt64() + "|class=" + cls + "|text=" + txt
                + "|rect=" + FormatRect(h) + "|visible=" + IsWindowVisible(h) + "|enabled=" + IsWindowEnabled(h);
            output.Add(line);
            CollectDescendants(h, depth + 1, maxDepth, output);
            return true;
        }, IntPtr.Zero);
    }

    public static System.Collections.ArrayList FindListCandidates(IntPtr root)
    {
        var list = new System.Collections.ArrayList();
        CollectListCandidatesRecurse(root, list);
        return list;
    }

    private static void CollectListCandidatesRecurse(IntPtr hWnd, System.Collections.ArrayList list)
    {
        string cls = GetWndClass(hWnd);
        if (IsListClassName(cls))
        {
            string type = cls.ToLowerInvariant().Contains("listbox") ? "ListBox" : "SysListView32";
            int cnt = GetDeviceListCount(hWnd, type);
            list.Add(hWnd.ToInt64() + "|" + cls + "|" + cnt);
        }
        EnumChildWindows(hWnd, (ch, lp) =>
        {
            CollectListCandidatesRecurse(ch, list);
            return true;
        }, IntPtr.Zero);
    }

    public static IntPtr FindChildByTextContainsRecursive(IntPtr parent, string needle)
    {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(parent, (h, l) =>
        {
            string t = GetWndText(h);
            if (!string.IsNullOrEmpty(t) && t.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                found = h;
                return false;
            }
            IntPtr inner = FindChildByTextContainsRecursive(h, needle);
            if (inner != IntPtr.Zero) { found = inner; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static IntPtr FindDeviceListHwnd(IntPtr parent)
    {
        var candidates = FindListCandidates(parent);
        IntPtr best = IntPtr.Zero;
        int bestCount = -1;
        string bestCls = "SysListView32";
        foreach (string entry in candidates)
        {
            string[] parts = entry.Split('|');
            if (parts.Length < 3) continue;
            long ptrVal;
            if (!long.TryParse(parts[0], out ptrVal)) continue;
            IntPtr h = new IntPtr(ptrVal);
            int cnt;
            if (!int.TryParse(parts[2], out cnt)) cnt = 0;
            if (cnt > bestCount)
            {
                bestCount = cnt;
                best = h;
                bestCls = parts[1];
            }
        }
        return best;
    }

    public static int GetDeviceListCount(IntPtr hwnd, string className)
    {
        if (className.Equals("ListBox", StringComparison.OrdinalIgnoreCase))
            return (int)SendMessage(hwnd, 0x018B, IntPtr.Zero, IntPtr.Zero);
        return GetListItemCount(hwnd);
    }

    public static string GetDeviceListCellText(IntPtr hwnd, string className, int row, int col)
    {
        if (className.Equals("ListBox", StringComparison.OrdinalIgnoreCase))
        {
            if (col > 0) return string.Empty;
            int len = (int)SendMessage(hwnd, 0x018A, (IntPtr)row, IntPtr.Zero);
            if (len <= 0) len = 512;
            IntPtr buffer = Marshal.AllocHGlobal((len + 4) * 2);
            try
            {
                SendMessage(hwnd, 0x0189, (IntPtr)row, buffer);
                return Marshal.PtrToStringUni(buffer) ?? string.Empty;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        return GetListSubItem(hwnd, row, col);
    }

    public static void SelectDeviceListRow(IntPtr hwnd, string className, int row)
    {
        if (className.Equals("ListBox", StringComparison.OrdinalIgnoreCase))
        {
            SendMessage(hwnd, 0x0186, (IntPtr)row, IntPtr.Zero);
            return;
        }
        SelectListRow(hwnd, row);
    }

    public static string GetDeviceListClass(IntPtr hwnd, IntPtr parent)
    {
        string c = GetWndClass(hwnd);
        if (!string.IsNullOrEmpty(c)) return c;
        return "SysListView32";
    }

    public static void LogChildClasses(IntPtr parent, int depth, int maxDepth)
    {
        if (depth > maxDepth) return;
        EnumChildWindows(parent, (h, l) =>
        {
            string cls = GetWndClass(h);
            string txt = GetWndText(h);
            if (!string.IsNullOrEmpty(cls))
            {
                System.Diagnostics.Debug.WriteLine(new string(' ', depth * 2) + cls + " | " + txt);
            }
            LogChildClasses(h, depth + 1, maxDepth);
            return true;
        }, IntPtr.Zero);
    }

    public static List<IntPtr> FindChildrenByClass(IntPtr parent, string className)
    {
        var list = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) =>
        {
            if (GetWndClass(h).Equals(className, StringComparison.OrdinalIgnoreCase))
                list.Add(h);
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static IntPtr FindChildByTextContains(IntPtr parent, string needle)
    {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(parent, (h, l) =>
        {
            string t = GetWndText(h);
            if (!string.IsNullOrEmpty(t) && t.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                found = h;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static string GetListSubItem(IntPtr listHwnd, int row, int subItem)
    {
        const int maxLen = 512;
        IntPtr buffer = Marshal.AllocHGlobal(maxLen * 2);
        try
        {
            LVITEMW item = new LVITEMW();
            item.mask = LVIF_TEXT;
            item.iItem = row;
            item.iSubItem = subItem;
            item.pszText = buffer;
            item.cchTextMax = maxLen;
            IntPtr pItem = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(LVITEMW)));
            try
            {
                Marshal.StructureToPtr(item, pItem, false);
                SendMessage(listHwnd, (uint)LVM_GETITEMTEXTW, (IntPtr)row, pItem);
                item = (LVITEMW)Marshal.PtrToStructure(pItem, typeof(LVITEMW));
                return Marshal.PtrToStringUni(item.pszText) ?? string.Empty;
            }
            finally { Marshal.FreeHGlobal(pItem); }
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static int GetListItemCount(IntPtr listHwnd)
    {
        return (int)SendMessage(listHwnd, (uint)LVM_GETITEMCOUNT, IntPtr.Zero, IntPtr.Zero);
    }

    public static void SelectListRow(IntPtr listHwnd, int row)
    {
        int count = GetListItemCount(listHwnd);
        for (int i = 0; i < count; i++)
        {
            LVITEMW item = new LVITEMW();
            item.mask = 0x0008; // LVIF_STATE
            item.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
            item.state = 0;
            item.iItem = i;
            IntPtr pItem = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(LVITEMW)));
            try
            {
                Marshal.StructureToPtr(item, pItem, false);
                SendMessage(listHwnd, (uint)LVM_SETITEMSTATE, (IntPtr)i, pItem);
            }
            finally { Marshal.FreeHGlobal(pItem); }
        }

        LVITEMW sel = new LVITEMW();
        sel.mask = 0x0008;
        sel.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
        sel.state = LVIS_SELECTED | LVIS_FOCUSED;
        sel.iItem = row;
        IntPtr pSel = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(LVITEMW)));
        try
        {
            Marshal.StructureToPtr(sel, pSel, false);
            SendMessage(listHwnd, (uint)LVM_SETITEMSTATE, (IntPtr)row, pSel);
            SendMessage(listHwnd, (uint)LVM_ENSUREVISIBLE, (IntPtr)row, (IntPtr)1);
        }
        finally { Marshal.FreeHGlobal(pSel); }
    }

    public static void ClickHwnd(IntPtr hWnd)
    {
        if (hWnd == IntPtr.Zero) return;
        SendMessage(hWnd, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
    }

    public static bool IsChecked(IntPtr hWnd)
    {
        return (int)SendMessage(hWnd, BM_GETCHECK, IntPtr.Zero, IntPtr.Zero) == BST_CHECKED;
    }

    public static void SetChecked(IntPtr hWnd, bool check)
    {
        SendMessage(hWnd, BM_SETCHECK, (IntPtr)(check ? BST_CHECKED : BST_UNCHECKED), IntPtr.Zero);
    }

    public static string GetComboText(IntPtr combo, int index)
    {
        int len = (int)SendMessage(combo, CB_GETLBTEXTLEN, (IntPtr)index, IntPtr.Zero);
        if (len <= 0) { len = 256; }
        IntPtr buffer = Marshal.AllocHGlobal((len + 4) * 2);
        try
        {
            SendMessage(combo, 0x0148, (IntPtr)index, buffer);
            return Marshal.PtrToStringUni(buffer) ?? string.Empty;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static bool SelectComboBySubstring(IntPtr combo, string needle)
    {
        int count = (int)SendMessage(combo, CB_GETCOUNT, IntPtr.Zero, IntPtr.Zero);
        for (int i = 0; i < count; i++)
        {
            string txt = GetComboText(combo, i);
            if (!string.IsNullOrEmpty(txt) && txt.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                SendMessage(combo, CB_SETCURSEL, (IntPtr)i, IntPtr.Zero);
                return true;
            }
        }
        return false;
    }

    public static string GetComboCurrentText(IntPtr combo)
    {
        int sel = (int)SendMessage(combo, CB_GETCURSEL, IntPtr.Zero, IntPtr.Zero);
        if (sel < 0) return string.Empty;
        return GetComboText(combo, sel);
    }

    public static void CloseWindow(IntPtr hWnd)
    {
        const uint WM_CLOSE = 0x0010;
        PostMessage(hWnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }
}
"@
}

$paramJson = Import-ControllerOverclockerParams -ParamFile $ParamFile
if ($paramJson) {
    if ($paramJson.AppRoot) { $AppRoot = [string]$paramJson.AppRoot }
    if ($paramJson.LogPath) { $LogPath = [string]$paramJson.LogPath }
    if ($paramJson.DeviceInstanceId) { $DeviceInstanceId = [string]$paramJson.DeviceInstanceId }
    if ($paramJson.Vid) { $Vid = [string]$paramJson.Vid }
    if ($paramJson.Pid) { $DevicePid = [string]$paramJson.Pid }
    if ($paramJson.Rate) { $Rate = [int]$paramJson.Rate }
    if ($paramJson.Mode) { $Mode = [string]$paramJson.Mode }
}

if (-not (Test-IsAdmin)) {
    Invoke-RelaunchElevated -ScriptPath $PSCommandPath -BoundParams $PSBoundParameters
}

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) { exit 9 }
if (-not $LogPath) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }
if (-not $ResultPath) { $ResultPath = Join-Path $app 'logs\hidusbf-setup-automation-result.json' }

$script:SetupWindowFound = $false
$script:ChildDumpPath = Join-Path $app 'logs\hidusbf-setup-child-dump.txt'
$script:UIADumpPath = Join-Path $app 'logs\hidusbf-setup-uia-dump.txt'
$script:RowDetectionMethod = ''
$script:RowsFound = 0

function Write-AutoLog {
    param([string]$Line)
    Write-DeviceLog ("[HIDUSBF-AUTO] " + $Line) $LogPath
}

function Test-ValidDeviceInstanceId {
    param([string]$Id)
    $id = ($Id + '').Trim()
    if (-not $id) { return $false }
    if ($id -match '^(?i)(test|null|none|undefined|n/a|na)$') { return $false }
    if ($id.Length -lt 12) { return $false }
    if ($id -notmatch '^(?i)(HID|USB)\\') { return $false }
    if ($id -notmatch 'VID_[0-9A-Fa-f]{4}') { return $false }
    if ($id -notmatch 'PID_[0-9A-Fa-f]{4}') { return $false }
    return $true
}

function Write-AutomationResult {
    param(
        [bool]$Success,
        [string]$Code,
        [string]$Message,
        [int]$ExitCode,
        [bool]$Verified = $false,
        [int]$ConfirmedRate = 0,
        [string]$FilterStatus = '',
        [bool]$LeaveSetupOpen = $false
    )
    $payload = @{
        Success          = $Success
        Code             = $Code
        Message          = $Message
        Verified         = $Verified
        ConfirmedRate    = $ConfirmedRate
        FilterStatus     = $FilterStatus
        Rate             = $Rate
        Mode             = $Mode
        DeviceInstanceId = $DeviceInstanceId
        Vid              = $Vid
        Pid              = $DevicePid
        SetupWindowFound = [bool]$script:SetupWindowFound
        ChildDumpPath    = [string]$script:ChildDumpPath
        UIADumpPath      = [string]$script:UIADumpPath
        RowDetectionMethod = [string]$script:RowDetectionMethod
        RowsFound        = [int]$script:RowsFound
    }
    $dir = Split-Path -Parent $ResultPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($ResultPath, ($payload | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
    $legacyPath = Join-Path $app 'logs\controller-overclocker-apply-result.json'
    [System.IO.File]::WriteAllText($legacyPath, ($payload | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
    Write-ScriptExitCode -AppRoot $app -Code $ExitCode
}

$script:UiaLoaded = $false

function Initialize-Uia {
    if ($script:UiaLoaded) { return $true }
    try {
        Add-Type -AssemblyType 'UIAutomationClient', 'UIAutomationTypes' -ErrorAction Stop
        $script:UiaLoaded = $true
        return $true
    } catch {
        Write-AutoLog ("UIAutomation load failed: " + $_.Exception.Message)
        return $false
    }
}

function Format-UiaElementLine {
    param(
        $Element,
        [string]$ViewName
    )
    if (-not $Element) { return $null }
    try {
        $c = $Element.Current
        $ct = $c.ControlType.ProgrammaticName
        $name = ($c.Name + '').Replace('|', '/')
        $aid = $c.AutomationId
        $cls = $c.ClassName
        $rect = $c.BoundingRectangle
        $r = [int]$rect.X + ',' + [int]$rect.Y + ',' + [int]($rect.X + $rect.Width) + ',' + [int]($rect.Y + $rect.Height)
        return ($ViewName + '|hwnd=' + $c.NativeWindowHandle + '|ControlType=' + $ct + '|Name=' + $name +
            '|AutomationId=' + $aid + '|ClassName=' + $cls + '|BoundingRectangle=' + $r +
            '|IsEnabled=' + $c.IsEnabled + '|IsOffscreen=' + $c.IsOffscreen)
    } catch {
        return ($ViewName + '|error=' + $_.Exception.Message)
    }
}

function Get-UiaWalkerElements {
    param(
        $RootElement,
        [string]$WalkerKind
    )
    $out = New-Object System.Collections.ArrayList
    if (-not $RootElement) { return $out }
    try {
        $walker = if ($WalkerKind -eq 'Raw') {
            [System.Windows.Automation.TreeWalker]::RawViewWalker
        } else {
            [System.Windows.Automation.TreeWalker]::ControlViewWalker
        }
        $stack = New-Object System.Collections.Stack
        $stack.Push($RootElement) | Out-Null
        $guard = 0
        while ($stack.Count -gt 0 -and $guard -lt 3000) {
            $guard++
            $el = $stack.Pop()
            if (-not $el) { continue }
            [void]$out.Add($el)
            $child = $walker.GetFirstChild($el)
            while ($child) {
                $stack.Push($child) | Out-Null
                $child = $walker.GetNextSibling($child)
            }
        }
    } catch {
        Write-AutoLog ("UIA walker error (" + $WalkerKind + "): " + $_.Exception.Message)
    }
    return $out
}

function Write-HidusbfControlDumps {
    param([IntPtr]$SetupHwnd)
    $logDir = Split-Path -Parent $script:ChildDumpPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $winLines = New-Object System.Collections.Generic.List[string]
    [void]$winLines.Add('[HIDUSBF-AUTO] Window hwnd=' + $SetupHwnd)
    [void]$winLines.Add('[HIDUSBF-AUTO] Dump all descendant controls (Win32 recursive):')
    if ($SetupHwnd -ne [IntPtr]::Zero) {
        $list = New-Object System.Collections.ArrayList
        [HidusbfUiHelper]::CollectDescendants($SetupHwnd, 0, 14, $list) | Out-Null
        foreach ($entry in $list) {
            [void]$winLines.Add('  ' + $entry)
            Write-AutoLog ('  WIN32 ' + $entry)
        }
    } else {
        [void]$winLines.Add('  (no setup window hwnd)')
    }
    try {
        [System.IO.File]::WriteAllLines($script:ChildDumpPath, $winLines, [System.Text.UTF8Encoding]::new($false))
        Write-AutoLog ('ChildDumpPath=' + $script:ChildDumpPath)
    } catch {
        Write-AutoLog ('Child dump write failed: ' + $_.Exception.Message)
    }

    $uiaLines = New-Object System.Collections.Generic.List[string]
    [void]$uiaLines.Add('[HIDUSBF-AUTO] UIA dump hwnd=' + $SetupHwnd)
    if (-not (Initialize-Uia)) {
        [void]$uiaLines.Add('UIAutomation not available')
    } elseif ($SetupHwnd -eq [IntPtr]::Zero) {
        [void]$uiaLines.Add('(no setup window hwnd)')
    } else {
        try {
            $ae = [System.Windows.Automation.AutomationElement]::FromHandle($SetupHwnd)
            if (-not $ae) {
                [void]$uiaLines.Add('AutomationElement.FromHandle returned null')
            } else {
                foreach ($view in @('RawView', 'ControlView')) {
                    $kind = if ($view -eq 'RawView') { 'Raw' } else { 'Control' }
                    [void]$uiaLines.Add('')
                    [void]$uiaLines.Add('=== UIA ' + $view + 'Walker ===')
                    $els = Get-UiaWalkerElements -RootElement $ae -WalkerKind $kind
                    $max = [Math]::Min($els.Count, 2500)
                    for ($i = 0; $i -lt $max; $i++) {
                        $line = Format-UiaElementLine -Element $els[$i] -ViewName $view
                        if ($line) {
                            [void]$uiaLines.Add($line)
                            if ($i -lt 400) { Write-AutoLog ('  UIA ' + $line) }
                        }
                    }
                    if ($els.Count -gt $max) {
                        [void]$uiaLines.Add('... truncated ' + ($els.Count - $max) + ' more elements')
                    }
                }
            }
        } catch {
            [void]$uiaLines.Add('UIA dump error: ' + $_.Exception.Message)
            Write-AutoLog ('UIA dump error: ' + $_.Exception.Message)
        }
    }
    try {
        [System.IO.File]::WriteAllLines($script:UIADumpPath, $uiaLines, [System.Text.UTF8Encoding]::new($false))
        Write-AutoLog ('UIADumpPath=' + $script:UIADumpPath)
    } catch {
        Write-AutoLog ('UIA dump write failed: ' + $_.Exception.Message)
    }
}

function Write-DescendantDump {
    param([IntPtr]$SetupHwnd)
    Write-AutoLog ("Window hwnd=" + $SetupHwnd)
    Write-AutoLog 'Dump all descendant controls:'
    Write-HidusbfControlDumps -SetupHwnd $SetupHwnd
}

function Normalize-DeviceText {
    param([string]$Text)
    if (-not $Text) { return '' }
    try {
        $n = $Text.Normalize([System.Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $n.ToCharArray()) {
            $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
            if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($ch)
            }
        }
        return $sb.ToString().ToUpperInvariant()
    } catch {
        return ($Text + '').ToUpperInvariant()
    }
}

function Test-RowBlocked {
    param([string]$Text)
    $u = Normalize-DeviceText $Text
    return ($u -match 'SOURIS|MOUSE|CLAVIER|KEYBOARD|AUDIO|MICROPHONE|RAZER|TOUCHPAD|TRACKPAD|POINT DE TERMINAISON AUDIO')
}

function Get-RowsFromWin32List {
    param(
        [IntPtr]$ListHwnd,
        [string]$ListClass
    )
    $rows = @()
    $count = [HidusbfUiHelper]::GetDeviceListCount($ListHwnd, $ListClass)
    for ($i = 0; $i -lt $count; $i++) {
        $cells = New-Object System.Collections.Generic.List[string]
        if ($ListClass -match '(?i)listbox') {
            $cells.Add([HidusbfUiHelper]::GetDeviceListCellText($ListHwnd, $ListClass, $i, 0)) | Out-Null
        } else {
            for ($c = 0; $c -lt 16; $c++) {
                $t = [HidusbfUiHelper]::GetDeviceListCellText($ListHwnd, $ListClass, $i, $c)
                if (-not $t -and $c -gt 0) { break }
                $cells.Add($t) | Out-Null
            }
        }
        $line = ($cells -join ' | ')
        $rows += [pscustomobject]@{ Index = $i; Cells = @($cells); Line = $line; Source = 'Win32' }
    }
    return $rows
}

function Get-RowsFromUia {
    param([IntPtr]$SetupHwnd)
    if (-not (Initialize-Uia)) { return @() }
    $rows = @()
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($SetupHwnd)
        if (-not $root) { return @() }

        $listHost = $null
        $types = @(
            [System.Windows.Automation.ControlType]::Table,
            [System.Windows.Automation.ControlType]::DataGrid,
            [System.Windows.Automation.ControlType]::List,
            [System.Windows.Automation.ControlType]::Tree
        )
        foreach ($ct in $types) {
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ct)
            $found = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
            if ($found) { $listHost = $found; break }
        }

        if (-not $listHost) {
            $header = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::NameProperty, 'Device Name')))
            if ($header) {
                $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
                $p = $header
                for ($d = 0; $d -lt 8; $d++) {
                    $p = $walker.GetParent($p)
                    if (-not $p) { break }
                    $cn = $p.FindAll([System.Windows.Automation.TreeScope]::Children,
                        [System.Windows.Automation.Condition]::TrueCondition)
                    if ($cn.Count -ge 3) { $listHost = $p; break }
                }
            }
        }

        if (-not $listHost) { return @() }

        $items = $listHost.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::DataItem)))
        if ($items.Count -eq 0) {
            $items = $listHost.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::ListItem)))
        }

        $idx = 0
        foreach ($item in $items) {
            $cells = New-Object System.Collections.Generic.List[string]
            $itemName = ($item.Current.Name + '').Trim()
            if ($itemName) { $cells.Add($itemName) | Out-Null }
            $texts = $item.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::Text)))
            foreach ($tx in $texts) {
                $t = ($tx.Current.Name + '').Trim()
                if ($t) { $cells.Add($t) | Out-Null }
            }
            if ($cells.Count -eq 0) { continue }
            $line = ($cells -join ' | ')
            if ($line -match '(?i)^Device Name\s*\|') { continue }
            $rows += [pscustomobject]@{
                Index = $idx
                Cells = @($cells)
                Line = $line
                Source = 'UIA'
                Element = $item
            }
            $idx++
        }
    } catch {
        Write-AutoLog ("UIA row read error: " + $_.Exception.Message)
    }
    return $rows
}

function Test-HeaderTextsPresent {
    param([string[]]$Texts)
    $norm = @($Texts | ForEach-Object { Normalize-DeviceText $_ })
    $need = @('DEVICE NAME', 'FILTER', 'RATE', 'BINTERVAL')
    $hits = 0
    foreach ($n in $need) {
        foreach ($t in $norm) {
            if ($t -match [regex]::Escape($n)) { $hits++; break }
        }
    }
    return ($hits -ge 3)
}

function Test-GridHeaderMarkers {
    param([string[]]$Texts)
    $norm = @($Texts | ForEach-Object { Normalize-DeviceText $_ })
    $markers = @(
        'DEVICE NAME', 'FILTER', 'RATE', 'BINTERVAL', 'CHILD NAME', 'CONTROLLER NAME',
        'PERIPHERIQUE D ENTREE USB', 'PERIPHERIQUE USB COMPOSITE'
    )
    $hits = 0
    foreach ($m in $markers) {
        foreach ($t in $norm) {
            if ($t -match [regex]::Escape($m)) { $hits++; break }
        }
    }
    return ($hits -ge 3)
}

function Get-RowsFromGridTextWalker {
    param([IntPtr]$SetupHwnd)
    if (-not (Initialize-Uia)) { return @() }
    $rows = @()
    try {
        $ae = [System.Windows.Automation.AutomationElement]::FromHandle($SetupHwnd)
        if (-not $ae) { return @() }

        $allNames = New-Object System.Collections.Generic.List[string]
        foreach ($view in @('Raw', 'Control')) {
            $els = Get-UiaWalkerElements -RootElement $ae -WalkerKind $view
            foreach ($el in $els) {
                try {
                    $n = ($el.Current.Name + '').Trim()
                    if ($n) { $allNames.Add($n) | Out-Null }
                } catch {}
            }
        }

        if (-not (Test-GridHeaderMarkers $allNames.ToArray())) { return @() }
        Write-AutoLog 'Grid text container found'

        $deviceTexts = New-Object System.Collections.Generic.List[string]
        foreach ($n in $allNames) {
            if ($n -match '^(Device Name|Filter\?|Rate|bInterval|Child Name|Controller Name|Selected Rate)$') { continue }
            $nu = Normalize-DeviceText $n
            if ($nu -match 'PERIPHERIQUE|COMPOSITE|USB|HID|DUALSENSE|CONTROLLER|DEFAULT|YES|NO|054C|0CE6|GAMEPAD|MANETTE') {
                $deviceTexts.Add($n) | Out-Null
            }
        }

        $i = 0
        $buf = New-Object System.Collections.Generic.List[string]
        foreach ($t in $deviceTexts) {
            $buf.Add($t) | Out-Null
            if ($buf.Count -ge 4) {
                $line = ($buf -join ' | ')
                if (-not (Test-RowBlocked $line)) {
                    $rows += [pscustomobject]@{
                        Index = $i
                        Cells = @($buf.ToArray())
                        Line = $line
                        Source = 'GridText'
                    }
                    $i++
                }
                $buf = New-Object System.Collections.Generic.List[string]
            }
        }
        if ($buf.Count -ge 2 -and -not (Test-RowBlocked ($buf -join ' | '))) {
            $line = ($buf -join ' | ')
            $rows += [pscustomobject]@{
                Index = $i
                Cells = @($buf.ToArray())
                Line = $line
                Source = 'GridText'
            }
        }
    } catch {
        Write-AutoLog ("GridText walker error: " + $_.Exception.Message)
    }
    return $rows
}

function Get-RowsFromStaticTexts {
    param([IntPtr]$SetupHwnd)
    $rows = @()
    $all = New-Object System.Collections.ArrayList
    [HidusbfUiHelper]::CollectDescendants($SetupHwnd, 0, 10, $all) | Out-Null
    $texts = @()
    foreach ($entry in $all) {
        if ($entry -match '\|class=([^|]+)\|text=([^|]*)') {
            $cls = $Matches[1]
            $txt = $Matches[2]
            if ($txt -and $cls -match '(?i)static|edit|list') {
                $texts += $txt
            }
        }
    }
    if (-not (Test-HeaderTextsPresent $texts)) {
        $hdr = @('Device Name', 'Filter?', 'Rate', 'bInterval')
        $foundHdr = 0
        foreach ($h in $hdr) {
            if ($texts -contains $h) { $foundHdr++ }
        }
        if ($foundHdr -lt 3) { return @() }
    }

    $i = 0
    $buf = New-Object System.Collections.Generic.List[string]
    foreach ($t in $texts) {
        if ($t -match '^(Device Name|Filter\?|Rate|bInterval|Child Name|Controller Name|Selected Rate)$') { continue }
        $tu = Normalize-DeviceText $t
        if ($tu -match 'PERIPHERIQUE|COMPOSITE|USB|HID|DUALSENSE|CONTROLLER|DEFAULT|YES|NO|054C|0CE6') {
            $buf.Add($t) | Out-Null
            if ($buf.Count -ge 4) {
                $line = ($buf -join ' | ')
                $rows += [pscustomobject]@{ Index = $i; Cells = @($buf.ToArray()); Line = $line; Source = 'TextScan' }
                $i++
                $buf = New-Object System.Collections.Generic.List[string]
            }
        }
    }
    return $rows
}

function Get-ListViewRows {
    param(
        [IntPtr]$ListHwnd,
        [string]$ListClass = 'SysListView32'
    )
    $rows = Get-RowsFromWin32List -ListHwnd $ListHwnd -ListClass $ListClass
    for ($i = 0; $i -lt $rows.Count; $i++) {
        Write-AutoLog ("Row " + $i + " text=" + $rows[$i].Line)
    }
    return $rows
}

function Find-DeviceListControl {
    param([IntPtr]$SetupHwnd)
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $candidates = [HidusbfUiHelper]::FindListCandidates($SetupHwnd)
        $best = $null
        foreach ($entry in $candidates) {
            $parts = $entry -split '\|'
            if ($parts.Length -lt 3) { continue }
            $hwnd = [IntPtr]::new([long]$parts[0])
            $cls = $parts[1]
            $cnt = [int]$parts[2]
            $type = if ($cls -match '(?i)listbox') { 'ListBox' } else { 'SysListView32' }
            Write-AutoLog ("List candidate hwnd=" + $hwnd + " class=" + $cls + " count=" + $cnt)
            $tryRows = Get-RowsFromWin32List -ListHwnd $hwnd -ListClass $type
            if ($tryRows.Count -gt 0) {
                return @{ Hwnd = $hwnd; Class = $type; Count = $tryRows.Count; Source = 'Win32'; Rows = $tryRows }
            }
        }

        $uiaRows = Get-RowsFromUia -SetupHwnd $SetupHwnd
        if ($uiaRows.Count -gt 0) {
            return @{ Hwnd = $SetupHwnd; Class = 'UIA'; Count = $uiaRows.Count; Source = 'UIA'; Rows = $uiaRows }
        }

        $textRows = Get-RowsFromStaticTexts -SetupHwnd $SetupHwnd
        if ($textRows.Count -gt 0) {
            return @{ Hwnd = $SetupHwnd; Class = 'TextScan'; Count = $textRows.Count; Source = 'TextScan'; Rows = $textRows }
        }

        $gridRows = Get-RowsFromGridTextWalker -SetupHwnd $SetupHwnd
        if ($gridRows.Count -gt 0) {
            return @{ Hwnd = $SetupHwnd; Class = 'GridText'; Count = $gridRows.Count; Source = 'GridText'; Rows = $gridRows }
        }

        Start-Sleep -Milliseconds 500
    }
    return $null
}

function Select-DeviceRow {
    param(
        $Row,
        [IntPtr]$ListHwnd,
        [string]$ListClass
    )
    if ($Row.Element -and (Initialize-Uia)) {
        try {
            $sel = $Row.Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            if ($sel) { $sel.Select(); return $true }
            $inv = $Row.Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            if ($inv) { $inv.Invoke(); return $true }
        } catch {}
    }
    if ($ListHwnd -ne [IntPtr]::Zero -and $ListClass -notmatch 'UIA|TextScan|GridText') {
        [HidusbfUiHelper]::SelectDeviceListRow($ListHwnd, $ListClass, $Row.Index)
        return $true
    }
    return $false
}

function Select-BestDeviceRow {
    param(
        [array]$Rows,
        [string]$DeviceInstanceId,
        [string]$VidU,
        [string]$PidU
    )
    $targetId = ($DeviceInstanceId + '').ToUpperInvariant()
    $best = $null
    $bestScore = -1
    foreach ($row in $Rows) {
        if (Test-RowBlocked $row.Line) { continue }
        $textU = Normalize-DeviceText $row.Line
        $score = 0

        if ($targetId) {
            $normLine = $textU.Replace('/', '\')
            $normId = (Normalize-DeviceText $targetId).Replace('/', '\')
            if ($normLine.Contains($normId)) { $score += 200 }
        }

        if ($textU -match 'PERIPHERIQUE D.ENTREE USB|PERIPHERIQUE D ENTREE USB|INPUT DEVICE') { $score += 80 }
        if ($textU -match 'HID|GAMEPAD|DUALSENSE|WIRELESS CONTROLLER|MANETTE|CONTROLLER') { $score += 40 }
        if ($textU -match ('VID_' + [regex]::Escape($VidU))) { $score += 60 }
        if ($textU -match ('PID_' + [regex]::Escape($PidU))) { $score += 60 }
        if ($textU -match 'MI_03') { $score += 30 }
        if ($textU -match 'COMPOSITE' -and $textU -match 'HID') { $score += 25 }

        if ($textU -match 'PERIPHERIQUE D.ENTREE USB' -and $textU -notmatch 'SOURIS|MOUSE|CLAVIER|KEYBOARD|AUDIO|RAZER') {
            $score += 50
        }

        if ($score -le 0) { continue }
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $row
        }
    }
    return $best
}

function Read-RowFilterAndRate {
    param([object]$Row)
    $filter = ''
    $rate = ''
    foreach ($cell in $Row.Cells) {
        $c = ($cell + '').Trim()
        if ($c -match '^(?i)yes|no$') { $filter = $c }
        if ($c -match '(?i)default|1000|8000|125|250|500|2000|4000') { $rate = $c }
    }
    if (-not $filter) {
        foreach ($cell in $Row.Cells) {
            if (($cell + '') -match '(?i)yes') { $filter = 'Yes'; break }
            if (($cell + '') -match '(?i)no') { $filter = 'No' }
        }
    }
    if (-not $rate) {
        foreach ($cell in $Row.Cells) {
            if (($cell + '') -match '(?i)(\d+)\s*hz') { $rate = $Matches[1]; break }
            if (($cell + '') -match '(?i)^default$') { $rate = 'Default'; break }
        }
    }
    return @{ Filter = $filter; Rate = $rate }
}

function Get-RowsAfterRestart {
    param(
        $ListCtrl,
        [IntPtr]$SetupHwnd,
        [IntPtr]$ListHwnd,
        [string]$ListClass
    )
    if ($ListClass -notmatch 'UIA|TextScan|GridText') {
        $fresh = Get-RowsFromWin32List -ListHwnd $ListHwnd -ListClass $ListClass
        if ($fresh.Count -gt 0) { return $fresh }
    }
    $uia = Get-RowsFromUia -SetupHwnd $SetupHwnd
    if ($uia.Count -gt 0) { return $uia }
    $scan = Get-RowsFromStaticTexts -SetupHwnd $SetupHwnd
    if ($scan.Count -gt 0) { return $scan }
    $grid = Get-RowsFromGridTextWalker -SetupHwnd $SetupHwnd
    if ($grid.Count -gt 0) { return $grid }
    if ($ListCtrl.Rows) { return @($ListCtrl.Rows) }
    return @()
}

function Wait-SetupWindow {
    param([int]$TimeoutSec = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $h = [HidusbfUiHelper]::FindSetupWindow()
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 300
    }
    return [IntPtr]::Zero
}

function Find-RateComboBox {
    param([IntPtr]$SetupHwnd)
    $comboHwnd = [HidusbfUiHelper]::FindChildByClass($SetupHwnd, 'ComboBox')
    if ($comboHwnd -ne [IntPtr]::Zero) {
        $count = [int][HidusbfUiHelper]::SendMessage($comboHwnd, [uint32][HidusbfUiHelper]::CB_GETCOUNT, [IntPtr]::Zero, [IntPtr]::Zero)
        if ($count -ge 2) { return $comboHwnd }
    }
    $all = New-Object System.Collections.ArrayList
    [HidusbfUiHelper]::CollectDescendants($SetupHwnd, 0, 8, $all) | Out-Null
    foreach ($entry in $all) {
        if ($entry -notmatch '\|class=([^|]+)\|') { continue }
        $cls = $Matches[1]
        if ($cls -notmatch '(?i)^ComboBox$|WindowsForms10\.COMBOBOX') { continue }
        if ($entry -notmatch '^hwnd=(\d+)') { continue }
        $cb = [IntPtr]::new([long]$Matches[1])
        $count = [int][HidusbfUiHelper]::SendMessage($cb, [uint32][HidusbfUiHelper]::CB_GETCOUNT, [IntPtr]::Zero, [IntPtr]::Zero)
        if ($count -lt 2) { continue }
        for ($i = 0; $i -lt $count; $i++) {
            $t = [HidusbfUiHelper]::GetComboText($cb, $i)
            if ($t -match '(?i)1000|8000|default|125') { return $cb }
        }
    }
    return [IntPtr]::Zero
}

function Test-RateMatches {
    param([string]$Text, [int]$WantedRate)
    if (-not $Text) { return $false }
    if ($WantedRate -eq 1000) { return ($Text -match '(?i)1000') }
    if ($WantedRate -eq 8000) { return ($Text -match '(?i)8000') }
    return $false
}

function Test-FilterYes {
    param([string]$Filter) return ($Filter -match '(?i)^yes$')
}

function Test-FilterNo {
    param([string]$Filter) return ($Filter -match '(?i)^no$' -or -not $Filter)
}

function Test-RateDefault {
    param([string]$RateText) return ($RateText -match '(?i)default')
}

# --- Main ---
Write-AutoLog 'Start'
Write-AutoLog ("DeviceInstanceId=" + $DeviceInstanceId)
Write-AutoLog ("VID/PID=" + $Vid + '/' + $DevicePid)
Write-AutoLog ("Rate requested=" + $Rate)
Write-AutoLog ("Mode=" + $Mode)

if (-not (Test-ValidDeviceInstanceId $DeviceInstanceId)) {
    Write-AutoLog 'ERROR invalid DeviceInstanceId from UI'
    Write-AutoLog ("DeviceInstanceId rejected value=" + $DeviceInstanceId)
    Write-AutomationResult -Success $false -Code 'INVALID_DEVICE_INSTANCE_ID' -Message 'Aucun vrai peripherique selectionne' -ExitCode 1
    exit 1
}

$label = $DeviceInstanceId + ' VID=' + $Vid + ' PID=' + $DevicePid
if (Test-BlockedInputDevice $label) {
    Write-AutoLog 'Result=error blocked_device'
    Write-AutomationResult -Success $false -Code 'BLOCKED_DEVICE' -Message 'Peripherique clavier/souris refuse' -ExitCode 4
    exit 4
}
if (-not (Test-AllowedControllerDevice -Text $label -Vid $Vid -DevicePid $DevicePid)) {
    Write-AutoLog 'Result=error device_not_allowed'
    Write-AutomationResult -Success $false -Code 'DEVICE_NOT_ALLOWED' -Message 'Peripherique non autorise' -ExitCode 4
    exit 4
}

$setupExe = Find-HidusbfSetupExe -AppRoot $app -LogFile $LogPath
if (-not $setupExe) {
    Write-AutoLog 'Result=error setup_missing'
    Write-AutomationResult -Success $false -Code 'SETUP_MISSING' -Message 'HIDUSBF Setup introuvable' -ExitCode 12
    exit 12
}
Write-AutoLog ("Setup path=" + $setupExe)

$proc = $null
try {
    $proc = Start-Process -FilePath $setupExe -ArgumentList @('/all') -PassThru -ErrorAction Stop
    Write-AutoLog ("Setup started PID=" + $proc.Id)
} catch {
    Write-AutoLog ("Setup start failed: " + $_.Exception.Message)
    Write-AutomationResult -Success $false -Code 'SETUP_START_FAILED' -Message 'Impossible de lancer HIDUSBF Setup' -ExitCode 13
    exit 13
}

$setupHwnd = Wait-SetupWindow -TimeoutSec 50
if ($setupHwnd -eq [IntPtr]::Zero) {
    $script:SetupWindowFound = $false
    Write-HidusbfControlDumps -SetupHwnd ([IntPtr]::Zero)
    Write-AutoLog 'Result=error setup_window_timeout'
    Write-AutomationResult -Success $false -Code 'SETUP_WINDOW_TIMEOUT' -Message 'Fenetre HIDUSBF Setup introuvable' -ExitCode 30 -LeaveSetupOpen $true
    exit 30
}
Write-AutoLog ("Setup window found hwnd=" + $setupHwnd)
$script:SetupWindowFound = $true
[HidusbfUiHelper]::SetForegroundWindow($setupHwnd) | Out-Null
Start-Sleep -Milliseconds 800

$listCtrl = Find-DeviceListControl -SetupHwnd $setupHwnd
if (-not $listCtrl) {
    Write-HidusbfControlDumps -SetupHwnd $setupHwnd
    $script:RowDetectionMethod = 'none'
    $script:RowsFound = 0
    Write-AutoLog 'Result=error listview_not_found'
    Write-AutomationResult -Success $false -Code 'LISTVIEW_NOT_FOUND' -Message 'Liste peripheriques HIDUSBF introuvable' -ExitCode 30 -LeaveSetupOpen $true
    exit 30
}
$script:RowDetectionMethod = [string]$listCtrl.Source
$listHwnd = $listCtrl.Hwnd
$listClass = $listCtrl.Class
Write-AutoLog ("Device list source=" + $listCtrl.Source + " hwnd=" + $listHwnd + " class=" + $listClass)

if ($listCtrl.Rows) {
    $rows = @($listCtrl.Rows)
} else {
    $rows = Get-ListViewRows -ListHwnd $listHwnd -ListClass $listClass
}
$script:RowsFound = $rows.Count
Write-AutoLog ("Device rows found=" + $rows.Count)
for ($ri = 0; $ri -lt $rows.Count; $ri++) {
    Write-AutoLog ("Row " + $ri + " text=" + $rows[$ri].Line)
}

if ($rows.Count -eq 0) {
    Write-HidusbfControlDumps -SetupHwnd $setupHwnd
    Write-AutoLog 'Result=error list_rows_empty'
    Write-AutomationResult -Success $false -Code 'LISTVIEW_NOT_FOUND' -Message 'Grille HIDUSBF visible mais aucune ligne lue' -ExitCode 30 -LeaveSetupOpen $true
    exit 30
}

$vidU = ($Vid + '').ToUpperInvariant()
$pidU = ($DevicePid + '').ToUpperInvariant()
$selected = Select-BestDeviceRow -Rows $rows -DeviceInstanceId $DeviceInstanceId -VidU $vidU -PidU $pidU
if (-not $selected) {
    Write-HidusbfControlDumps -SetupHwnd $setupHwnd
    Write-AutoLog 'ERROR safe device row not found'
    Write-AutoLog 'Result=error device_row_not_found (no row selected — safety)'
    Write-AutomationResult -Success $false -Code 'DEVICE_ROW_NOT_FOUND' -Message 'Ligne manette introuvable (selection securisee)' -ExitCode 31 -LeaveSetupOpen $true
    exit 31
}
Write-AutoLog ("Selected row=" + $selected.Index + " text=" + $selected.Line)
$selectOk = Select-DeviceRow -Row $selected -ListHwnd $listHwnd -ListClass $listClass
if (-not $selectOk) {
    Write-AutoLog 'WARN row selection pattern failed — continuing without coordinate click'
}
Start-Sleep -Milliseconds 500

$filterHwnd = [HidusbfUiHelper]::FindChildByTextContainsRecursive($setupHwnd, 'Filter On Device')
if ($filterHwnd -eq [IntPtr]::Zero) {
    $buttons = [HidusbfUiHelper]::FindChildrenByClass($setupHwnd, 'Button')
    foreach ($b in $buttons) {
        if ([HidusbfUiHelper]::GetWndText($b) -match '(?i)Filter On Device') { $filterHwnd = $b; break }
    }
}
if ($filterHwnd -eq [IntPtr]::Zero) {
    Write-AutoLog 'Result=error filter_checkbox_not_found'
    Write-AutomationResult -Success $false -Code 'FILTER_CONTROL_NOT_FOUND' -Message 'Case Filter On Device introuvable' -ExitCode 32 -LeaveSetupOpen $true
    exit 32
}

if ($Mode -eq 'Restore') {
    if ([HidusbfUiHelper]::IsChecked($filterHwnd)) {
        [HidusbfUiHelper]::SetChecked($filterHwnd, $false)
        Start-Sleep -Milliseconds 200
    }
    Write-AutoLog 'Filter On Device unchecked'
} else {
    if (-not [HidusbfUiHelper]::IsChecked($filterHwnd)) {
        [HidusbfUiHelper]::SetChecked($filterHwnd, $true)
        Start-Sleep -Milliseconds 200
    }
    if (-not [HidusbfUiHelper]::IsChecked($filterHwnd)) {
        [HidusbfUiHelper]::ClickHwnd($filterHwnd)
        Start-Sleep -Milliseconds 200
    }
    if (-not [HidusbfUiHelper]::IsChecked($filterHwnd)) {
        Write-AutoLog 'Result=error filter_not_checked'
        Write-AutomationResult -Success $false -Code 'FILTER_NOT_CHECKED' -Message 'Impossible de cocher Filter On Device' -ExitCode 32 -LeaveSetupOpen $true
        exit 32
    }
    Write-AutoLog ("Filter On Device checked=" + [HidusbfUiHelper]::IsChecked($filterHwnd))

    $rateCombo = Find-RateComboBox -SetupHwnd $setupHwnd
    if ($rateCombo -eq [IntPtr]::Zero) {
        Write-AutoLog 'Result=error rate_combo_not_found'
        Write-AutomationResult -Success $false -Code 'RATE_COMBO_NOT_FOUND' -Message 'Liste Rate introuvable' -ExitCode 33 -LeaveSetupOpen $true
        exit 33
    }
    $rateNeedle = if ($Rate -eq 8000) { '8000' } else { '1000' }
    $selectedCombo = [HidusbfUiHelper]::SelectComboBySubstring($rateCombo, $rateNeedle)
    if (-not $selectedCombo) {
        Write-AutoLog 'Result=error rate_not_selected'
        Write-AutomationResult -Success $false -Code 'RATE_NOT_SELECTED' -Message ('Impossible de choisir ' + $Rate + ' Hz') -ExitCode 33 -LeaveSetupOpen $true
        exit 33
    }
    $curRate = [HidusbfUiHelper]::GetComboCurrentText($rateCombo)
    Write-AutoLog ("Selected Rate set to " + $curRate)
    if (-not (Test-RateMatches -Text $curRate -WantedRate $Rate)) {
        Write-AutoLog 'Result=error rate_verify_combo'
        Write-AutomationResult -Success $false -Code 'RATE_NOT_SELECTED' -Message ('Rate combo invalide: ' + $curRate) -ExitCode 33 -LeaveSetupOpen $true
        exit 33
    }
}

$installBtn = [HidusbfUiHelper]::FindChildByTextContainsRecursive($setupHwnd, 'Install Service')
if ($Mode -eq 'Apply' -and $installBtn -ne [IntPtr]::Zero) {
    Write-AutoLog 'Install Service clicked'
    [HidusbfUiHelper]::ClickHwnd($installBtn)
    Start-Sleep -Seconds 2
}

$restartBtn = [HidusbfUiHelper]::FindChildByTextContainsRecursive($setupHwnd, 'Restart')
if ($restartBtn -ne [IntPtr]::Zero) {
    Write-AutoLog 'Restart clicked'
    [HidusbfUiHelper]::ClickHwnd($restartBtn)
    Start-Sleep -Seconds 3
} else {
    Write-AutoLog 'Restart button not found'
}

Select-DeviceRow -Row $selected -ListHwnd $listHwnd -ListClass $listClass | Out-Null
Start-Sleep -Milliseconds 400

$rowsAfter = Get-RowsAfterRestart -ListCtrl $listCtrl -SetupHwnd $setupHwnd -ListHwnd $listHwnd -ListClass $listClass
Write-AutoLog ("Post-restart device rows=" + $rowsAfter.Count)
$verifyRow = $rowsAfter | Where-Object { $_.Index -eq $selected.Index } | Select-Object -First 1
if (-not $verifyRow) {
    $verifyRow = Select-BestDeviceRow -Rows $rowsAfter -DeviceInstanceId $DeviceInstanceId -VidU $vidU -PidU $pidU
}
if (-not $verifyRow) { $verifyRow = $selected }
$status = Read-RowFilterAndRate -Row $verifyRow
Write-AutoLog ("Verification filter=" + $status.Filter + " rate=" + $status.Rate)

$verified = $false
$confirmedRate = 0
if ($Mode -eq 'Restore') {
    if ((Test-FilterNo $status.Filter) -and (Test-RateDefault $status.Rate)) {
        $verified = $true
        $confirmedRate = 125
    }
} else {
    if ((Test-FilterYes $status.Filter) -and (Test-RateMatches -Text $status.Rate -WantedRate $Rate)) {
        $verified = $true
        $confirmedRate = $Rate
    } elseif (Test-FilterYes $status.Filter) {
        $comboRate = [HidusbfUiHelper]::GetComboCurrentText((Find-RateComboBox -SetupHwnd $setupHwnd))
        if (Test-RateMatches -Text $comboRate -WantedRate $Rate) {
            Write-AutoLog ("Verification via Selected Rate combo=" + $comboRate)
            $verified = $true
            $confirmedRate = $Rate
        }
    }
}

if ($verified) {
    Write-AutoLog ("Result=success filter=" + $status.Filter + " rate=" + $status.Rate)
    [HidusbfUiHelper]::CloseWindow($setupHwnd) | Out-Null
    $msg = if ($Mode -eq 'Restore') { 'Defaut restaure et confirme dans HIDUSBF Setup' } else { ($Rate.ToString() + ' Hz confirme') }
    Write-AutomationResult -Success $true -Code 'APPLIED_VERIFIED' -Message $msg -ExitCode 0 -Verified $true -ConfirmedRate $confirmedRate -FilterStatus $status.Filter
    exit 0
}

if (-not $verified) {
    Write-DescendantDump -SetupHwnd $setupHwnd
}
Write-AutoLog 'Result=error not_confirmed'
$failMsg = if ($Mode -eq 'Restore') {
    'Non confirme : HIDUSBF n indique pas Default/No'
} else {
    'Non confirme : HIDUSBF indique encore Default.'
}
Write-AutomationResult -Success $false -Code 'NOT_CONFIRMED_DEFAULT' -Message $failMsg -ExitCode 34 -Verified $false -FilterStatus $status.Filter -LeaveSetupOpen $true
exit 34
