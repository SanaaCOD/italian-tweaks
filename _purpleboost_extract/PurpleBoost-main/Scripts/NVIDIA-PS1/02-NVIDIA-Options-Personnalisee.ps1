# 02-NVIDIA-Options-Personnalisee-DynamicClick.ps1
# Sélectionne uniquement "Personnalisée (avancée)" / "Custom"
# Vrai clic dynamique calculé depuis le rectangle Win32 du contrôle Custom.
# Pas de coordonnée fixe, pas de clavier, pas de Suivant.

param(
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class Win32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

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
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    public const int SW_RESTORE = 9;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
"@

[void][Win32]::SetProcessDPIAware()

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
    $t = $t -replace "ë", "e"
    $t = $t -replace "à", "a"
    $t = $t -replace "â", "a"
    $t = $t -replace "ç", "c"
    $t = $t -replace "ù", "u"
    $t = $t -replace "û", "u"
    $t = $t -replace "&", ""
    $t = $t -replace "\s+", " "
    return $t.Trim()
}

function Test-PointInside {
    param(
        [int]$X,
        [int]$Y,
        [object]$Item
    )

    return ($X -ge $Item.Left -and $X -le $Item.Right -and $Y -ge $Item.Top -and $Y -le $Item.Bottom)
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

function Invoke-RealClick {
    param(
        [int]$X,
        [int]$Y
    )

    [void][Win32]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 120
    [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 700
}

Write-Host "[NVIDIA-PS1-02-DYN] Recherche fenêtre NVIDIA..."

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$win = [IntPtr]::Zero

while ((Get-Date) -lt $deadline) {
    $win = Find-NvidiaInstallerWindow
    if ($win -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 500
}

if ($win -eq [IntPtr]::Zero) {
    Write-Host "[NVIDIA-PS1-02-DYN] ERREUR: fenêtre NVIDIA introuvable."
    exit 1
}

Write-Host "[NVIDIA-PS1-02-DYN] Fenêtre trouvée hwnd=$win title='$(Get-Text $win)'"

[void][Win32]::ShowWindow($win, [Win32]::SW_RESTORE)
Start-Sleep -Milliseconds 200
[void][Win32]::BringWindowToTop($win)
Start-Sleep -Milliseconds 200
[void][Win32]::SetForegroundWindow($win)
Start-Sleep -Milliseconds 500

$children = Get-ChildControls $win

Write-Host "[NVIDIA-PS1-02-DYN] Contrôles visibles avec texte :"
$children | Where-Object { $_.Text -and $_.Text.Trim().Length -gt 0 } | ForEach-Object {
    Write-Host " - hwnd=$($_.Hwnd) class=$($_.Class) text='$($_.Text)' norm='$($_.Norm)' rect=($($_.Left),$($_.Top),$($_.Right),$($_.Bottom)) enabled=$($_.Enabled)"
}

$express = $children | Where-Object {
    $_.Enabled -eq $true -and
    (
        $_.Text -match "Express|Expresse" -or
        $_.Norm -match "express|expresse"
    )
} | Sort-Object Top | Select-Object -First 1

$custom = $children | Where-Object {
    $_.Enabled -eq $true -and
    (
        $_.Text -match "Personnalis|Custom" -or
        $_.Norm -match "personnalis|custom"
    ) -and
    $_.Text -notmatch "Express|Expresse" -and
    $_.Norm -notmatch "express|expresse"
} | Sort-Object Top | Select-Object -First 1

if (-not $express) {
    Write-Host "[NVIDIA-PS1-02-DYN] STOP: Express introuvable."
    exit 2
}

if (-not $custom) {
    Write-Host "[NVIDIA-PS1-02-DYN] STOP: Personnalisée/Custom introuvable."
    exit 3
}

Write-Host "[NVIDIA-PS1-02-DYN] Express candidate: hwnd=$($express.Hwnd) text='$($express.Text)' rect=($($express.Left),$($express.Top),$($express.Right),$($express.Bottom))"
Write-Host "[NVIDIA-PS1-02-DYN] Custom candidate : hwnd=$($custom.Hwnd) text='$($custom.Text)' rect=($($custom.Left),$($custom.Top),$($custom.Right),$($custom.Bottom))"

if ($custom.Hwnd -eq $express.Hwnd) {
    Write-Host "[NVIDIA-PS1-02-DYN] STOP: Custom et Express ont le même HWND."
    exit 4
}

if ($custom.Text -match "Express|Expresse" -or $custom.Norm -match "express|expresse") {
    Write-Host "[NVIDIA-PS1-02-DYN] STOP: Custom contient Express."
    exit 5
}

if ($custom.Top -le $express.Top) {
    Write-Host "[NVIDIA-PS1-02-DYN] STOP: Custom n'est pas sous Express."
    exit 6
}

# Point dynamique : ligne Custom, côté gauche.
# Le radio est généralement à gauche du texte.
$y = [int](($custom.Top + $custom.Bottom) / 2)

# Premier point : début du label Custom
$xLabel = [int]($custom.Left + 12)

# Deuxième point : légèrement à gauche du label, là où se trouve souvent le radio.
$xRadio = [int]($custom.Left - 22)

$insideExpressLabel = Test-PointInside -X $xLabel -Y $y -Item $express
$insideExpressRadio = Test-PointInside -X $xRadio -Y $y -Item $express

Write-Host "[NVIDIA-PS1-02-DYN] Dynamic label click point x=$xLabel y=$y"
Write-Host "[NVIDIA-PS1-02-DYN] Dynamic radio click point x=$xRadio y=$y"
Write-Host "[NVIDIA-PS1-02-DYN] Safety label point inside express=$insideExpressLabel"
Write-Host "[NVIDIA-PS1-02-DYN] Safety radio point inside express=$insideExpressRadio"

if ($insideExpressLabel -or $insideExpressRadio) {
    Write-Host "[NVIDIA-PS1-02-DYN] STOP: un point calculé tombe dans Express. Aucun clic."
    exit 7
}

[void][Win32]::SetForegroundWindow($win)
Start-Sleep -Milliseconds 250
[void][Win32]::SetFocus($custom.Hwnd)
Start-Sleep -Milliseconds 150

Write-Host "[NVIDIA-PS1-02-DYN] Clic dynamique sur radio Custom..."
Invoke-RealClick -X $xRadio -Y $y

Start-Sleep -Milliseconds 300

Write-Host "[NVIDIA-PS1-02-DYN] Clic dynamique sur label Custom..."
Invoke-RealClick -X $xLabel -Y $y

Write-Host "[NVIDIA-PS1-02-DYN] Terminé. Vérifie visuellement que Personnalisée est cochée. Aucun clic sur Suivant."
exit 0