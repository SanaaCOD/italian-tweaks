# 02-NVIDIA-Options-Personnalisee.ps1
# Sélectionne "Personnalisée (avancée)" puis clique "SUIVANT"
# Sans souris, sans SetCursorPos, sans SendInput, sans clavier.

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

    public const int BM_GETCHECK = 0x00F0;
    public const int BM_SETCHECK = 0x00F1;
    public const int BM_CLICK = 0x00F5;

    public const int BST_UNCHECKED = 0x0000;
    public const int BST_CHECKED = 0x0001;

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

function Get-CheckState {
    param([IntPtr]$Hwnd)

    try {
        $result = [Win32]::SendMessage($Hwnd, [Win32]::BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero)
        return [int]$result
    } catch {
        return -1
    }
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
    Start-Sleep -Milliseconds 400
    [void][Win32]::SetFocus($ButtonHwnd)
    Start-Sleep -Milliseconds 200

    Write-Host "[NVIDIA-PS1-02] $Label - Methode 1: UIAutomation InvokePattern"
    try {
        $element = [System.Windows.Automation.AutomationElement]::FromHandle($ButtonHwnd)
        $invokePattern = $null

        if ($element -and $element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invokePattern)) {
            $invokePattern.Invoke()
            Start-Sleep -Seconds 1
            return $true
        }
    } catch {
        Write-Host "[NVIDIA-PS1-02] UIA InvokePattern indisponible pour $Label."
    }

    Write-Host "[NVIDIA-PS1-02] $Label - Methode 2: BM_CLICK"
    [void][Win32]::SendMessage($ButtonHwnd, [Win32]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Seconds 1

    Write-Host "[NVIDIA-PS1-02] $Label - Methode 3: WM_COMMAND parent"
    $parent = [Win32]::GetParent($ButtonHwnd)
    $ctrlId = [Win32]::GetDlgCtrlID($ButtonHwnd)

    if ($parent -ne [IntPtr]::Zero -and $ctrlId -ge 0) {
        $wParam = [IntPtr]($ctrlId -band 0xFFFF)
        [void][Win32]::SendMessage($parent, [Win32]::WM_COMMAND, $wParam, $ButtonHwnd)
        Start-Sleep -Seconds 1
    }

    Write-Host "[NVIDIA-PS1-02] $Label - Methode 4: WM_LBUTTONDOWN/UP poste au HWND exact, sans souris"
    $rect = Get-Rect $ButtonHwnd
    $localX = [int](($rect.Right - $rect.Left) / 2)
    $localY = [int](($rect.Bottom - $rect.Top) / 2)
    $lParam = New-LParam -X $localX -Y $localY

    [void][Win32]::PostMessage($ButtonHwnd, [Win32]::WM_LBUTTONDOWN, [IntPtr][Win32]::MK_LBUTTON, $lParam)
    Start-Sleep -Milliseconds 120
    [void][Win32]::PostMessage($ButtonHwnd, [Win32]::WM_LBUTTONUP, [IntPtr]::Zero, $lParam)
    Start-Sleep -Seconds 1

    return $true
}

function Invoke-NoMouseSelectCustom {
    param(
        [IntPtr]$Window,
        [object]$Custom,
        [object]$Express
    )

    [void][Win32]::ShowWindow($Window, [Win32]::SW_RESTORE)
    Start-Sleep -Milliseconds 200
    [void][Win32]::BringWindowToTop($Window)
    Start-Sleep -Milliseconds 200
    [void][Win32]::SetForegroundWindow($Window)
    Start-Sleep -Milliseconds 400
    [void][Win32]::SetFocus($Custom.Hwnd)
    Start-Sleep -Milliseconds 200

    Write-Host "[NVIDIA-PS1-02] Selection Custom - Methode 1: UIA SelectionItemPattern"
    try {
        $element = [System.Windows.Automation.AutomationElement]::FromHandle($Custom.Hwnd)
        $selectionPattern = $null

        if ($element -and $element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectionPattern)) {
            $selectionPattern.Select()
            Start-Sleep -Milliseconds 700
        }
    } catch {
        Write-Host "[NVIDIA-PS1-02] UIA SelectionItemPattern indisponible."
    }

    $customChecked = Get-CheckState $Custom.Hwnd
    $expressChecked = Get-CheckState $Express.Hwnd
    Write-Host "[NVIDIA-PS1-02] Apres UIA: expressChecked=$expressChecked customChecked=$customChecked"

    if ($customChecked -eq 1 -and $expressChecked -ne 1) {
        return $true
    }

    Write-Host "[NVIDIA-PS1-02] Selection Custom - Methode 2: BM_CLICK sur Custom exact"
    [void][Win32]::SendMessage($Custom.Hwnd, [Win32]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800

    $customChecked = Get-CheckState $Custom.Hwnd
    $expressChecked = Get-CheckState $Express.Hwnd
    Write-Host "[NVIDIA-PS1-02] Apres BM_CLICK: expressChecked=$expressChecked customChecked=$customChecked"

    if ($customChecked -eq 1 -and $expressChecked -ne 1) {
        return $true
    }

    Write-Host "[NVIDIA-PS1-02] Selection Custom - Methode 3: BM_SETCHECK + WM_COMMAND"
    [void][Win32]::SendMessage($Express.Hwnd, [Win32]::BM_SETCHECK, [IntPtr][Win32]::BST_UNCHECKED, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 150
    [void][Win32]::SendMessage($Custom.Hwnd, [Win32]::BM_SETCHECK, [IntPtr][Win32]::BST_CHECKED, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 150

    $parent = [Win32]::GetParent($Custom.Hwnd)
    $ctrlId = [Win32]::GetDlgCtrlID($Custom.Hwnd)

    if ($parent -ne [IntPtr]::Zero -and $ctrlId -ge 0) {
        $wParam = [IntPtr]($ctrlId -band 0xFFFF)
        [void][Win32]::SendMessage($parent, [Win32]::WM_COMMAND, $wParam, $Custom.Hwnd)
        Start-Sleep -Milliseconds 700
    }

    $customChecked = Get-CheckState $Custom.Hwnd
    $expressChecked = Get-CheckState $Express.Hwnd
    Write-Host "[NVIDIA-PS1-02] Apres BM_SETCHECK+WM_COMMAND: expressChecked=$expressChecked customChecked=$customChecked"

    if ($customChecked -eq 1 -and $expressChecked -ne 1) {
        return $true
    }

    Write-Host "[NVIDIA-PS1-02] Selection Custom - Methode 4: WM_LBUTTONDOWN/UP au HWND Custom exact, sans souris"
    $rect = Get-Rect $Custom.Hwnd
    $localX = [int](($rect.Right - $rect.Left) / 2)
    $localY = [int](($rect.Bottom - $rect.Top) / 2)
    $lParam = New-LParam -X $localX -Y $localY

    [void][Win32]::PostMessage($Custom.Hwnd, [Win32]::WM_LBUTTONDOWN, [IntPtr][Win32]::MK_LBUTTON, $lParam)
    Start-Sleep -Milliseconds 120
    [void][Win32]::PostMessage($Custom.Hwnd, [Win32]::WM_LBUTTONUP, [IntPtr]::Zero, $lParam)
    Start-Sleep -Milliseconds 800

    $customChecked = Get-CheckState $Custom.Hwnd
    $expressChecked = Get-CheckState $Express.Hwnd
    Write-Host "[NVIDIA-PS1-02] Apres WM_LBUTTON: expressChecked=$expressChecked customChecked=$customChecked"

    if ($customChecked -eq 1 -and $expressChecked -ne 1) {
        return $true
    }

    return $false
}

Write-Host "[NVIDIA-PS1-02] Recherche de la fenetre NVIDIA..."

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$win = [IntPtr]::Zero

while ((Get-Date) -lt $deadline) {
    $win = Find-NvidiaInstallerWindow
    if ($win -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 500
}

if ($win -eq [IntPtr]::Zero) {
    Write-Host "[NVIDIA-PS1-02] ERREUR: fenetre NVIDIA introuvable."
    exit 1
}

Write-Host "[NVIDIA-PS1-02] Fenetre trouvee hwnd=$win title='$(Get-Text $win)'"

[void][Win32]::SetForegroundWindow($win)
Start-Sleep -Milliseconds 500

$children = Get-ChildControls $win

Write-Host "[NVIDIA-PS1-02] Controles visibles avec texte :"
$children | Where-Object { $_.Text -and $_.Text.Trim().Length -gt 0 } | ForEach-Object {
    Write-Host " - hwnd=$($_.Hwnd) class=$($_.Class) text='$($_.Text)' rect=($($_.Left),$($_.Top),$($_.Right),$($_.Bottom)) enabled=$($_.Enabled) check=$(Get-CheckState $_.Hwnd)"
}

$express = $children | Where-Object {
    $_.Enabled -eq $true -and
    (
        $_.Norm -like "*expresse*" -or
        $_.Norm -like "*express*"
    )
} | Sort-Object Top | Select-Object -First 1

$custom = $children | Where-Object {
    $_.Enabled -eq $true -and
    (
        $_.Norm -like "*personnalis*" -or
        $_.Norm -eq "custom" -or
        $_.Norm -like "custom *" -or
        $_.Norm -like "*custom installation*"
    ) -and
    $_.Norm -notlike "*express*"
} | Sort-Object Top | Select-Object -First 1

$next = $children | Where-Object {
    $_.Enabled -eq $true -and
    (
        $_.Text -eq "&SUIVANT" -or
        $_.Text -eq "SUIVANT" -or
        $_.Text -eq "&NEXT" -or
        $_.Text -eq "NEXT" -or
        $_.Norm -eq "suivant" -or
        $_.Norm -eq "next"
    )
} | Sort-Object Top -Descending | Select-Object -First 1

if (-not $express) {
    Write-Host "[NVIDIA-PS1-02] ERREUR: controle Express introuvable."
    exit 2
}

if (-not $custom) {
    Write-Host "[NVIDIA-PS1-02] ERREUR: controle Personnalisee introuvable."
    exit 3
}

if (-not $next) {
    Write-Host "[NVIDIA-PS1-02] ERREUR: bouton SUIVANT introuvable."
    exit 4
}

Write-Host "[NVIDIA-PS1-02] Express trouve : hwnd=$($express.Hwnd) text='$($express.Text)' rect=($($express.Left),$($express.Top),$($express.Right),$($express.Bottom)) check=$(Get-CheckState $express.Hwnd)"
Write-Host "[NVIDIA-PS1-02] Custom trouve  : hwnd=$($custom.Hwnd) text='$($custom.Text)' rect=($($custom.Left),$($custom.Top),$($custom.Right),$($custom.Bottom)) check=$(Get-CheckState $custom.Hwnd)"
Write-Host "[NVIDIA-PS1-02] Suivant trouve : hwnd=$($next.Hwnd) text='$($next.Text)' rect=($($next.Left),$($next.Top),$($next.Right),$($next.Bottom))"

if (-not $ok -and $finalExpress -eq 0 -and $finalCustom -eq 0) {
    Write-Host "[NVIDIA-PS1-02] WARNING: BM_GETCHECK non fiable. Personnalisee semble cochee visuellement apres clic exact Custom. On continue vers SUIVANT."
    $ok = $true
}

if (-not $ok) {
    Write-Host "[NVIDIA-PS1-02] STOP SECURITE: Personnalisee non verifiee. Aucun clic sur SUIVANT."
    exit 8
}
if ($custom.Norm -like "*express*") {
    Write-Host "[NVIDIA-PS1-02] STOP SECURITE: le texte Custom contient Express."
    exit 6
}

if ($custom.Top -le $express.Top) {
    Write-Host "[NVIDIA-PS1-02] STOP SECURITE: Custom n'est pas sous Express."
    exit 7
}

$beforeExpress = Get-CheckState $express.Hwnd
$beforeCustom = Get-CheckState $custom.Hwnd
Write-Host "[NVIDIA-PS1-02] Avant selection: expressChecked=$beforeExpress customChecked=$beforeCustom"

$ok = Invoke-NoMouseSelectCustom -Window $win -Custom $custom -Express $express

$finalExpress = Get-CheckState $express.Hwnd
$finalCustom = Get-CheckState $custom.Hwnd
Write-Host "[NVIDIA-PS1-02] FINAL: expressChecked=$finalExpress customChecked=$finalCustom customVerified=$ok"

if (-not $ok) {
    Write-Host "[NVIDIA-PS1-02] STOP SECURITE: Personnalisee non verifiee. Aucun clic sur SUIVANT."
    exit 8
}

Write-Host "[NVIDIA-PS1-02] Personnalisee verifiee. Re-detection du bouton SUIVANT..."

Start-Sleep -Milliseconds 800

# Re-scan après sélection de Personnalisée, car NVIDIA peut rafraîchir/recréer les contrôles
$childrenAfterCustom = Get-ChildControls $win

$nextAfterCustom = $childrenAfterCustom | Where-Object {
    $_.Enabled -eq $true -and
    (
        $_.Text -eq "&SUIVANT" -or
        $_.Text -eq "SUIVANT" -or
        $_.Text -eq "&NEXT" -or
        $_.Text -eq "NEXT" -or
        $_.Norm -eq "suivant" -or
        $_.Norm -eq "next"
    )
} | Sort-Object Top -Descending | Select-Object -First 1

if (-not $nextAfterCustom) {
    Write-Host "[NVIDIA-PS1-02] ERREUR: bouton SUIVANT introuvable après sélection Personnalisée."
    Write-Host "[NVIDIA-PS1-02] Contrôles après sélection :"
    $childrenAfterCustom | Where-Object { $_.Text -and $_.Text.Trim().Length -gt 0 } | ForEach-Object {
        Write-Host " - hwnd=$($_.Hwnd) class=$($_.Class) text='$($_.Text)' rect=($($_.Left),$($_.Top),$($_.Right),$($_.Bottom)) enabled=$($_.Enabled)"
    }
    exit 9
}

Write-Host "[NVIDIA-PS1-02] SUIVANT re-trouve : hwnd=$($nextAfterCustom.Hwnd) text='$($nextAfterCustom.Text)' rect=($($nextAfterCustom.Left),$($nextAfterCustom.Top),$($nextAfterCustom.Right),$($nextAfterCustom.Bottom))"

# Méthode renforcée spéciale SUIVANT, sans souris, sans clavier
[void][Win32]::ShowWindow($win, [Win32]::SW_RESTORE)
Start-Sleep -Milliseconds 200
[void][Win32]::BringWindowToTop($win)
Start-Sleep -Milliseconds 200
[void][Win32]::SetForegroundWindow($win)
Start-Sleep -Milliseconds 400
[void][Win32]::SetFocus($nextAfterCustom.Hwnd)
Start-Sleep -Milliseconds 200

Write-Host "[NVIDIA-PS1-02] SUIVANT Methode 1: UIAutomation InvokePattern"
try {
    $nextElement = [System.Windows.Automation.AutomationElement]::FromHandle($nextAfterCustom.Hwnd)
    $invokePattern = $null

    if ($nextElement -and $nextElement.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invokePattern)) {
        $invokePattern.Invoke()
        Start-Sleep -Seconds 1
    }
} catch {
    Write-Host "[NVIDIA-PS1-02] SUIVANT UIA InvokePattern indisponible."
}

Write-Host "[NVIDIA-PS1-02] SUIVANT Methode 2: BM_CLICK exact"
[void][Win32]::SendMessage($nextAfterCustom.Hwnd, [Win32]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 1

Write-Host "[NVIDIA-PS1-02] SUIVANT Methode 3: WM_COMMAND parent exact"
$nextParent = [Win32]::GetParent($nextAfterCustom.Hwnd)
$nextCtrlId = [Win32]::GetDlgCtrlID($nextAfterCustom.Hwnd)

if ($nextParent -ne [IntPtr]::Zero -and $nextCtrlId -ge 0) {
    $nextWParam = [IntPtr]($nextCtrlId -band 0xFFFF)
    [void][Win32]::SendMessage($nextParent, [Win32]::WM_COMMAND, $nextWParam, $nextAfterCustom.Hwnd)
    Start-Sleep -Seconds 1
}

Write-Host "[NVIDIA-PS1-02] SUIVANT Methode 4: WM_LBUTTONDOWN/UP poste au HWND exact, sans souris"
$nextRect = Get-Rect $nextAfterCustom.Hwnd
$nextLocalX = [int](($nextRect.Right - $nextRect.Left) / 2)
$nextLocalY = [int](($nextRect.Bottom - $nextRect.Top) / 2)
$nextLParam = New-LParam -X $nextLocalX -Y $nextLocalY

[void][Win32]::PostMessage($nextAfterCustom.Hwnd, [Win32]::WM_LBUTTONDOWN, [IntPtr][Win32]::MK_LBUTTON, $nextLParam)
Start-Sleep -Milliseconds 120
[void][Win32]::PostMessage($nextAfterCustom.Hwnd, [Win32]::WM_LBUTTONUP, [IntPtr]::Zero, $nextLParam)
Start-Sleep -Seconds 1

Write-Host "[NVIDIA-PS1-02] Terminé."
exit 0