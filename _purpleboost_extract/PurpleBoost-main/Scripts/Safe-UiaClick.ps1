# Shared safe UI Automation click helpers — no fixed screen/window percentage clicks.
$script:SafeUiaLogFn = $null

function Write-SafeUiaMsg([string]$msg) {
    if ($script:SafeUiaLogFn) {
        try { & $script:SafeUiaLogFn $msg } catch {}
    }
}

function Write-BlockedUnsafeClick([string]$context) {
    Write-SafeUiaMsg "[BLOCKED-UNSAFE-CLICK] $context"
}

function Get-UiaElementDescriptor([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return 'element=null' }
    try {
        $ct = $el.Current.ControlType.ProgrammaticName
        $name = [string]$el.Current.Name
        $aid = ''
        try { $aid = [string]$el.Current.AutomationId } catch {}
        $en = 'enabled'
        try { if (-not $el.Current.IsEnabled) { $en = 'disabled' } } catch {}
        $r = $el.Current.BoundingRectangle
        $rect = ('L{0:F0},T{1:F0},W{2:F0},H{3:F0}' -f $r.X, $r.Y, $r.Width, $r.Height)
        return "Name='$name' AutomationId='$aid' ControlType=$ct IsEnabled=$en BoundingRectangle=$rect"
    } catch {
        return 'element=descriptor_error'
    }
}

function Test-SafeUiaElementActionable([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    try {
        if (-not $el.Current.IsEnabled) { return $false }
        $r = $el.Current.BoundingRectangle
        if ($r.Width -le 2 -or $r.Height -le 2) { return $false }
        return $true
    } catch {
        return $false
    }
}

function Write-UiaDumpForElement(
    [System.Windows.Automation.AutomationElement]$root,
    [string]$reason
) {
    if (-not $root) {
        Write-SafeUiaMsg "[UIA-DUMP] $reason — racine introuvable."
        return
    }
    Write-SafeUiaMsg "[UIA-DUMP] $reason"
    $interesting = @(
        [System.Windows.Automation.ControlType]::Button,
        [System.Windows.Automation.ControlType]::RadioButton,
        [System.Windows.Automation.ControlType]::CheckBox,
        [System.Windows.Automation.ControlType]::Text
    )
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        $n = 0
        foreach ($el in $all) {
            if ($n -ge 80) { break }
            try {
                $ct = $el.Current.ControlType
                if ($interesting -notcontains $ct) { continue }
                $desc = Get-UiaElementDescriptor $el
                $sel = ''
                try {
                    $sp = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                    if ($sp) { $sel = ' IsSelected=' + $sp.Current.IsSelected }
                } catch {}
                Write-SafeUiaMsg "[UIA-DUMP] $desc$sel"
                $n++
            } catch {}
        }
    } catch {
        Write-SafeUiaMsg "[UIA-DUMP] échec énumération descendants."
    }
}

function Ensure-SafeUiaMouseType {
    if ([type]::SafeUiaMouse) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public class SafeUiaMouse {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    public const uint LDOWN = 2;
    public const uint LUP = 4;
    public static bool ClickScreen(int x, int y, IntPtr hwnd) {
        if (hwnd != IntPtr.Zero) SetForegroundWindow(hwnd);
        Thread.Sleep(80);
        SetCursorPos(x, y);
        Thread.Sleep(40);
        mouse_event(LDOWN, 0, 0, 0, UIntPtr.Zero);
        mouse_event(LUP, 0, 0, 0, UIntPtr.Zero);
        return true;
    }
}
"@ -ErrorAction SilentlyContinue | Out-Null
}

function SafeInvokeElement(
    [System.Windows.Automation.AutomationElement]$element,
    [string]$expectedName
) {
    if (-not (Test-SafeUiaElementActionable $element)) {
        Write-UiaDumpForElement $element "SafeInvokeElement introuvable/inactif ($expectedName)"
        return $false
    }
    $desc = Get-UiaElementDescriptor $element
    try {
        $inv = $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        if ($inv) {
            $inv.Invoke()
            Write-SafeUiaMsg "[SAFE-UIA] InvokePattern | attendu='$expectedName' | $desc"
            return $true
        }
    } catch {}
    Write-SafeUiaMsg "[SAFE-UIA] InvokePattern indisponible | attendu='$expectedName' | $desc"
    return $false
}

function SafeSelectRadio(
    [System.Windows.Automation.AutomationElement]$element,
    [string]$expectedName
) {
    if (-not (Test-SafeUiaElementActionable $element)) {
        Write-UiaDumpForElement $element "SafeSelectRadio introuvable/inactif ($expectedName)"
        return $false
    }
    $desc = Get-UiaElementDescriptor $element
    try {
        $sp = $element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sp) {
            if (-not $sp.Current.IsSelected) { $sp.Select() }
            Write-SafeUiaMsg "[SAFE-UIA] SelectionItemPattern | attendu='$expectedName' | $desc"
            return $true
        }
    } catch {}
    try {
        $tp = $element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($tp -and $tp.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) {
            $tp.Toggle()
            Write-SafeUiaMsg "[SAFE-UIA] TogglePattern (radio) | attendu='$expectedName' | $desc"
            return $true
        }
    } catch {}
    Write-SafeUiaMsg "[SAFE-UIA] SelectionItemPattern indisponible | attendu='$expectedName' | $desc"
    return $false
}

function SafeToggleCheckbox(
    [System.Windows.Automation.AutomationElement]$element,
    [string]$expectedName
) {
    if (-not (Test-SafeUiaElementActionable $element)) {
        Write-UiaDumpForElement $element "SafeToggleCheckbox introuvable/inactif ($expectedName)"
        return $false
    }
    $desc = Get-UiaElementDescriptor $element
    try {
        $tp = $element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($tp) {
            if ($tp.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) { $tp.Toggle() }
            Write-SafeUiaMsg "[SAFE-UIA] TogglePattern | attendu='$expectedName' | $desc"
            return $true
        }
    } catch {}
    Write-SafeUiaMsg "[SAFE-UIA] TogglePattern indisponible | attendu='$expectedName' | $desc"
    return $false
}

function SafeClickElementCenter(
    [System.Windows.Automation.AutomationElement]$element,
    [string]$expectedName,
    [System.Windows.Automation.AutomationElement]$ownerWindow
) {
    if (-not (Test-SafeUiaElementActionable $element)) {
        Write-UiaDumpForElement $ownerWindow "SafeClickElementCenter élément invalide ($expectedName)"
        return $false
    }
    $desc = Get-UiaElementDescriptor $element
    try {
        $rect = $element.Current.BoundingRectangle
        $cx = [int]($rect.X + ($rect.Width / 2))
        $cy = [int]($rect.Y + ($rect.Height / 2))
        Ensure-SafeUiaMouseType
        $hwnd = [IntPtr]::Zero
        if ($ownerWindow) {
            try { $hwnd = [IntPtr][int]$ownerWindow.Current.NativeWindowHandle } catch {}
        }
        Write-SafeUiaMsg "[SAFE-UIA-RECT] clic centre élément UIA identifié | attendu='$expectedName' | $desc"
        return [SafeUiaMouse]::ClickScreen($cx, $cy, $hwnd)
    } catch {
        Write-SafeUiaMsg "[SAFE-UIA-RECT] échec | attendu='$expectedName' | $desc"
        return $false
    }
}
