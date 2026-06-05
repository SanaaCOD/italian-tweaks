# One-shot: WM_MOUSEMOVE / WM_LBUTTONDOWN / WM_LBUTTONUP on NVIDIA license Accept button HWND (client coords only).
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PurpleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LogsDir = Join-Path $PurpleRoot 'logs'
$DumpPath = Join-Path $LogsDir 'nvidia-license-after-windowmessage-dump.txt'
$HelperCs = Join-Path $PurpleRoot 'Scripts\NvidiaWin32Msaa-helper.cs'

if (-not (Test-Path -LiteralPath $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

function Write-OneShotMsgLog([string]$Message) {
    Write-Host $Message
}

if (-not (Test-Path -LiteralPath $HelperCs)) {
    Write-OneShotMsgLog "[ONE-SHOT-MSG] Helper missing: $HelperCs"
    exit 1
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'NvidiaWin32Msaa').Type) {
        Add-Type -Path $HelperCs -ErrorAction Stop | Out-Null
    }
} catch {
    Write-OneShotMsgLog "[ONE-SHOT-MSG] Helper compile failed: $($_.Exception.Message)"
    exit 1
}

if (-not ([System.Management.Automation.PSTypeName]'NvidiaLicenseMouseMsg').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NvidiaLicenseMouseMsg {
    public const int WM_MOUSEMOVE = 0x0200;
    public const int WM_LBUTTONDOWN = 0x0201;
    public const int WM_LBUTTONUP = 0x0202;
    public const int MK_LBUTTON = 0x0001;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);

    public static IntPtr MakeLParam(int x, int y) {
        return new IntPtr((y << 16) | (x & 0xFFFF));
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

    public static void SendClientCenterClick(IntPtr acceptHwnd) {
        RECT rc;
        if (!GetClientRect(acceptHwnd, out rc)) {
            throw new InvalidOperationException("GetClientRect failed for accept hwnd");
        }
        int cx = (rc.Left + rc.Right) / 2;
        int cy = (rc.Top + rc.Bottom) / 2;
        if (cx < 1) { cx = 1; }
        if (cy < 1) { cy = 1; }
        var lParam = MakeLParam(cx, cy);
        SendMessage(acceptHwnd, WM_MOUSEMOVE, IntPtr.Zero, lParam);
        SendMessage(acceptHwnd, WM_LBUTTONDOWN, new IntPtr(MK_LBUTTON), lParam);
        SendMessage(acceptHwnd, WM_LBUTTONUP, IntPtr.Zero, lParam);
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
    $t = $t -replace '`', [string]::Empty
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
        if (-not [NvidiaLicenseMouseMsg]::IsDescendantOf($c.Hwnd, $rootHwnd)) { continue }
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

function Write-VisibleWin32Dump([IntPtr]$rootHwnd, [string]$path) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    $lines.Add('ROOT_CLASS=' + [NvidiaWin32Msaa]::GetWndClass($rootHwnd)) | Out-Null
    $lines.Add('--- VISIBLE CHILDREN AFTER TEST ---') | Out-Null
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible) { continue }
        $rect = "L$($c.Rect.Left),T$($c.Rect.Top),R$($c.Rect.Right),B$($c.Rect.Bottom)"
        $lines.Add(
            "HWND=$($c.Hwnd.ToInt64()) | className='$($c.ClassName)' | text='$($c.Text)' | visible=$($c.Visible) | enabled=$($c.Enabled) | rect=$rect | style=$($c.Style) | exStyle=$($c.ExStyle) | GetDlgCtrlID=$($c.ControlId)"
        ) | Out-Null
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
}

$rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
if ($rootHwnd -eq [IntPtr]::Zero) {
    Write-OneShotMsgLog "[ONE-SHOT-MSG] NVIDIA installer top-level window not found"
    exit 2
}

$acceptInfo = Find-AcceptButtonInfo $rootHwnd
if (-not $acceptInfo) {
    Write-OneShotMsgLog '[ONE-SHOT-MSG] Accept hwnd not found'
    Write-VisibleWin32Dump $rootHwnd $DumpPath
    exit 3
}

Write-OneShotMsgLog "[ONE-SHOT-MSG] Accept hwnd found: HWND=$($acceptInfo.Hwnd.ToInt64()) text='$($acceptInfo.Text)' id=$($acceptInfo.ControlId) class='$($acceptInfo.ClassName)'"
Write-OneShotMsgLog '[ONE-SHOT-MSG] Sending WM_LBUTTONDOWN/UP to accept hwnd client center'

try {
    [NvidiaLicenseMouseMsg]::SendClientCenterClick($acceptInfo.Hwnd)
} catch {
    Write-OneShotMsgLog "[ONE-SHOT-MSG] Mouse message send failed: $($_.Exception.Message)"
    Write-VisibleWin32Dump $rootHwnd $DumpPath
    exit 5
}

Start-Sleep -Milliseconds 700

Write-VisibleWin32Dump $rootHwnd $DumpPath
Write-OneShotMsgLog "[ONE-SHOT-MSG] Post-test dump written: $DumpPath"

if (-not (Test-AcceptButtonStillVisible $rootHwnd)) {
    Write-OneShotMsgLog '[ONE-SHOT-MSG] Accept button disappeared'
    exit 0
}

if (Test-OptionsPageVisible $rootHwnd) {
    Write-OneShotMsgLog '[ONE-SHOT-MSG] Options page detected'
    exit 0
}

Write-OneShotMsgLog '[ONE-SHOT-MSG] Still on license page'
exit 4
