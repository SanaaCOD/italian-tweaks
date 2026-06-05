# 05-NVIDIA-Installer.ps1
# Clique le vrai bouton "&INSTALLER" dans le Programme d'installation NVIDIA
# Sans souris, sans clavier, sans coordonnées GPS.

param(
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class Win32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern IntPtr SetFocus(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr GetParent(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetDlgCtrlID(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    public const int SW_RESTORE = 9;
    public const int BM_CLICK = 0x00F5;
    public const int WM_COMMAND = 0x0111;
    public const int WM_LBUTTONDOWN = 0x0201;
    public const int WM_LBUTTONUP = 0x0202;
    public const int MK_LBUTTON = 0x0001;
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
"@

function Get-Text {
    param([IntPtr]$Hwnd)
    $sb = New-Object System.Text.StringBuilder 512
    [void][Win32]::GetWindowText($Hwnd, $sb, $sb.Capacity)
    return $sb.ToString()
}

function Get-Class {
    param([IntPtr]$Hwnd)
    $sb = New-Object System.Text.StringBuilder 256
    [void][Win32]::GetClassName($Hwnd, $sb, $sb.Capacity)
    return $sb.ToString()
}

function Get-Rect {
    param([IntPtr]$Hwnd)
    $rect = New-Object RECT
    [void][Win32]::GetWindowRect($Hwnd, [ref]$rect)
    return $rect
}

function Normalize-Text {
    param([string]$Text)

    if ($null -eq $Text) { return "" }

    $t = $Text.ToLowerInvariant()
    $t = $t -replace "é", "e"
    $t = $t -replace "è", "e"
    $t = $t -replace "ê", "e"
    $t = $t -replace "à", "a"
    $t = $t -replace "ç", "c"
    $t = $t -replace "&", ""
    $t = $t -replace "\s+", " "
    return $t.Trim()
}

function New-LParam {
    param(
        [int]$X,
        [int]$Y
    )

    return [IntPtr](($Y -shl 16) -bor ($X -band 0xFFFF))
}

function Find-NvidiaInstallerWindow {
    $script:foundWindow = [IntPtr]::Zero

    $callback = [Win32+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (-not [Win32]::IsWindowVisible($hWnd)) {
            return $true
        }

        $title = Get-Text $hWnd
        $norm = Normalize-Text $title

        if ($norm -like "*programme d'installation nvidia*" -or $norm -like "*nvidia installer*") {
            $script:foundWindow = $hWnd
            return $false
        }

        return $true
    }

    [void][Win32]::EnumWindows($callback, [IntPtr]::Zero)
    return $script:foundWindow
}

function Get-ChildControls {
    param([IntPtr]$Parent)

    $items = New-Object System.Collections.Generic.List[object]

    $callback = [Win32+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if ([Win32]::IsWindowVisible($hWnd)) {
            $txt = Get-Text $hWnd
            $cls = Get-Class $hWnd
            $rect = Get-Rect $hWnd

            $items.Add([pscustomobject]@{
                Hwnd = $hWnd
                Text = $txt
                Norm = Normalize-Text $txt
                Class = $cls
                Enabled = [Win32]::IsWindowEnabled($hWnd)
                Left = $rect.Left
                Top = $rect.Top
                Right = $rect.Right
                Bottom = $rect.Bottom
                Width = $rect.Right - $rect.Left
                Height = $rect.Bottom - $rect.Top
            }) | Out-Null
        }

        return $true
    }

    [void][Win32]::EnumChildWindows($Parent, $callback, [IntPtr]::Zero)
    return $items
}

function Invoke-NoMouseButtonClick {
    param(
        [IntPtr]$Window,
        [IntPtr]$ButtonHwnd,
        [string]$Label
    )

    [void][Win32]::ShowWindow($Window, [Win32]::SW_RESTORE)
    Start-Sleep -Milliseconds 200
    [void][Win32]::BringWindowToTop($Window)
    Start-Sleep -Milliseconds 200
    [void][Win32]::SetForegroundWindow($Window)
    Start-Sleep -Milliseconds 500
    [void][Win32]::SetFocus($ButtonHwnd)
    Start-Sleep -Milliseconds 200

    Write-Host "[NVIDIA-PS1-05] $Label - Methode 1: UIAutomation InvokePattern"
    try {
        $element = [System.Windows.Automation.AutomationElement]::FromHandle($ButtonHwnd)
        $invokePattern = $null

        if ($element -and $element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invokePattern)) {
            $invokePattern.Invoke()
            Start-Sleep -Seconds 1
        }
    } catch {
        Write-Host "[NVIDIA-PS1-05] UIA InvokePattern indisponible."
    }

    Write-Host "[NVIDIA-PS1-05] $Label - Methode 2: BM_CLICK"
    [void][Win32]::SendMessage($ButtonHwnd, [Win32]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Seconds 1

    Write-Host "[NVIDIA-PS1-05] $Label - Methode 3: WM_COMMAND parent"
    $parent = [Win32]::GetParent($ButtonHwnd)
    $ctrlId = [Win32]::GetDlgCtrlID($ButtonHwnd)

    if ($parent -ne [IntPtr]::Zero -and $ctrlId -ge 0) {
        $wParam = [IntPtr]($ctrlId -band 0xFFFF)
        [void][Win32]::SendMessage($parent, [Win32]::WM_COMMAND, $wParam, $ButtonHwnd)
        Start-Sleep -Seconds 1
    }

    Write-Host "[NVIDIA-PS1-05] $Label - Methode 4: WM_LBUTTONDOWN/UP poste au HWND exact"
    $rect = Get-Rect $ButtonHwnd
    $localX = [int](($rect.Right - $rect.Left) / 2)
    $localY = [int](($rect.Bottom - $rect.Top) / 2)
    $lParam = New-LParam -X $localX -Y $localY

    [void][Win32]::PostMessage($ButtonHwnd, [Win32]::WM_LBUTTONDOWN, [IntPtr][Win32]::MK_LBUTTON, $lParam)
    Start-Sleep -Milliseconds 120
    [void][Win32]::PostMessage($ButtonHwnd, [Win32]::WM_LBUTTONUP, [IntPtr]::Zero, $lParam)
    Start-Sleep -Seconds 1
}

Write-Host "[NVIDIA-PS1-05] Recherche de la fenetre NVIDIA..."

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$win = [IntPtr]::Zero

while ((Get-Date) -lt $deadline) {
    $win = Find-NvidiaInstallerWindow
    if ($win -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 500
}

if ($win -eq [IntPtr]::Zero) {
    Write-Host "[NVIDIA-PS1-05] ERREUR: fenetre NVIDIA introuvable."
    exit 1
}

Write-Host "[NVIDIA-PS1-05] Fenetre trouvee hwnd=$win title='$(Get-Text $win)'"

[void][Win32]::SetForegroundWindow($win)
Start-Sleep -Milliseconds 500

$children = Get-ChildControls $win

Write-Host "[NVIDIA-PS1-05] Controles visibles avec texte :"
$children | Where-Object { $_.Text -and $_.Text.Trim().Length -gt 0 } | ForEach-Object {
    Write-Host " - hwnd=$($_.Hwnd) class=$($_.Class) text='$($_.Text)' rect=($($_.Left),$($_.Top),$($_.Right),$($_.Bottom)) enabled=$($_.Enabled)"
}

# On cible le bouton INSTALLER en bas de la fenêtre.
# Sort-Object Top -Descending évite de prendre le texte/menu "Installer" à gauche.
$install = $children | Where-Object {
    $_.Enabled -eq $true -and
    (
        $_.Text -eq "&INSTALLER" -or
        $_.Text -eq "INSTALLER" -or
        $_.Text -eq "&Installer" -or
        $_.Text -eq "Installer" -or
        $_.Text -eq "&INSTALL" -or
        $_.Text -eq "INSTALL" -or
        $_.Norm -eq "installer" -or
        $_.Norm -eq "install"
    )
} | Sort-Object Top -Descending | Select-Object -First 1

if (-not $install) {
    Write-Host "[NVIDIA-PS1-05] ERREUR: vrai bouton INSTALLER introuvable."
    exit 2
}

Write-Host "[NVIDIA-PS1-05] VRAI bouton INSTALLER trouve : hwnd=$($install.Hwnd) text='$($install.Text)' rect=($($install.Left),$($install.Top),$($install.Right),$($install.Bottom))"

Invoke-NoMouseButtonClick -Window $win -ButtonHwnd $install.Hwnd -Label "INSTALLER"

Write-Host "[NVIDIA-PS1-05] Terminé."
exit 0