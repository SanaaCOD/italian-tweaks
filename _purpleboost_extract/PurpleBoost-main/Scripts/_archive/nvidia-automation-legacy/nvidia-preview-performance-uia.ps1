# Mode performance NVIDIA — « Ajuster les paramètres d'image avec aperçu » (UI Automation)
param(
    [string]$LogPath = '',
    [string]$ResultPath = '',
    [switch]$DiagnosePreviewPerformance,
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Continue'

$script:Deadline = (Get-Date).AddSeconds([Math]::Max(10, $TimeoutSeconds))
$script:UiAssemblyOk = $false
$script:FailureReason = ''
$script:DetectedLanguage = 'unknown'

$script:PreviewPageAliases = @(
    'Ajuster les paramètres d''image avec aperçu',
    'Ajuster les parametres d''image avec apercu',
    'Régler les paramètres d''image avec Aperçu',
    'Régler les parametres d''image avec Apercu',
    'Regler les parametres d''image avec Apercu',
    'paramètres d''image avec aperçu',
    'parametres d''image avec apercu',
    'image avec Aperçu',
    'Adjust image settings with preview',
    'image settings with preview'
)
$script:NavParentAliases = @(
    '3D Settings',
    'Paramètres 3D',
    'Gérer les paramètres 3D',
    'Manage 3D settings',
    'Adjust image settings'
)
$script:PreferenceRadioAliases = @(
    'Utiliser mes préférences pour accentuer',
    'Utiliser mes preferences pour accentuer',
    'Utiliser mes préférences en mettant l''accent sur',
    'Utiliser mes preferences en mettant l''accent sur',
    'mes préférences pour accentuer',
    'my preference emphasizing',
    'Use my preference emphasizing'
)
$script:ApplyButtonAliases = @('Appliquer', 'Apply')
$script:PanelWindowPatterns = @(
    'Panneau de configuration NVIDIA',
    'NVIDIA Control Panel',
    'NVIDIA Settings',
    'NVIDIA GeForce',
    'Centre de configuration NVIDIA'
)
$script:DiagnoseKeywords = @(
    'image', 'aperçu', 'apercu', 'preview', 'performance', 'performances',
    'qualité', 'qualite', 'quality', 'préférences', 'preferences', 'preference',
    'appliquer', 'apply', 'accentuer', 'emphasizing'
)

function Write-Log([string]$msg) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    if ($LogPath) {
        try {
            $dir = Split-Path -Parent $LogPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
        } catch {}
    }
}

function Test-StepTimeout([string]$step) {
    if ((Get-Date) -lt $script:Deadline) { return $false }
    $script:FailureReason = 'timeout'
    Write-Log "FAIL=Preview performance timeout at step: $step"
    return $true
}

function Write-Result([hashtable]$payload) {
    if (-not $ResultPath) { return }
    try {
        $dir = Split-Path -Parent $ResultPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $json = $payload | ConvertTo-Json -Compress -Depth 8
        [System.IO.File]::WriteAllText($ResultPath, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {}
}

function Exit-WithResult([bool]$applied, [bool]$verified, [string]$state, [string[]]$messages, [int]$exitCode, [string]$failureReason) {
    if ($failureReason) { $script:FailureReason = $failureReason }
    $msgs = @($messages)
    if ($script:FailureReason -and ($msgs -notcontains $script:FailureReason)) {
        $msgs += $script:FailureReason
    }
    Write-Log "RESULT applied=$applied verified=$verified state=$state exit=$exitCode reason=$($script:FailureReason)"
    Write-Result @{
        previewPerformance = @{
            applied  = $applied
            verified = $verified
            state    = $state
        }
        failureReason = $script:FailureReason
        messages      = $msgs
        exitCode      = $exitCode
    }
    exit $exitCode
}

function Test-IsProcessElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal $id
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Ensure-Win32FocusType {
    if ('NvPreviewFocus' -as [type]) { return }
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Automation;
public static class NvPreviewFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetFocus(IntPtr hWnd);
    public static void FocusElement(AutomationElement el) {
        if (el == null) return;
        try {
            var h = new IntPtr(el.Current.NativeWindowHandle);
            if (h != IntPtr.Zero) {
                ShowWindow(h, 9);
                SetForegroundWindow(h);
                SetFocus(h);
                return;
            }
        } catch {}
        try {
            var parent = TreeWalker.ControlViewWalker.GetParent(el);
            for (int i = 0; i < 8 && parent != null; i++) {
                var h2 = new IntPtr(parent.Current.NativeWindowHandle);
                if (h2 != IntPtr.Zero) {
                    SetForegroundWindow(h2);
                    SetFocus(h2);
                    return;
                }
                parent = TreeWalker.ControlViewWalker.GetParent(parent);
            }
        } catch {}
    }
}
"@ -ErrorAction SilentlyContinue | Out-Null
}

$script:NvidiaControlPanelAppId = 'NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel'
$script:ClassicNvcpluiPath = "${env:ProgramFiles}\NVIDIA Corporation\Control Panel Client\nvcplui.exe"

function Find-NvcpluiClassicPath {
    Write-Log 'Trying classic nvcplui.exe path'
    Write-Log "Classic path=$($script:ClassicNvcpluiPath)"
    if (Test-Path -LiteralPath $script:ClassicNvcpluiPath) {
        Write-Log "Classic nvcplui.exe found=$($script:ClassicNvcpluiPath)"
        return $script:ClassicNvcpluiPath
    }
    Write-Log 'Classic nvcplui.exe not found'
    return $null
}

function Start-NvidiaControlPanelViaAppId {
    Write-Log 'Trying NVIDIA Control Panel AppID'
    $args = 'shell:AppsFolder\' + $script:NvidiaControlPanelAppId
    Write-Log "Launch command: explorer.exe $args"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'explorer.exe'
        $psi.Arguments = $args
        $psi.UseShellExecute = $true
        $null = [System.Diagnostics.Process]::Start($psi)
        Write-Log 'NVIDIA Control Panel launch requested'
        return $true
    } catch {
        Write-Log "NVIDIA Control Panel AppID launch failed: $($_.Exception.Message)"
        return $false
    }
}

function Launch-NvidiaControlPanel {
    $existing = Get-NvidiaPanelWindow
    if ($existing) {
        $t = [string]$existing.Current.Name
        Write-Log "Window found: $t"
        return $existing
    }

    $classic = Find-NvcpluiClassicPath
    if ($classic) {
        if (-not (Start-NvcpluiProcess $classic)) {
            Write-Log 'Classic nvcplui.exe launch failed, falling back to AppID'
            Start-NvidiaControlPanelViaAppId | Out-Null
        }
    } else {
        Start-NvidiaControlPanelViaAppId | Out-Null
    }

    Write-Log 'Waiting for NVIDIA Control Panel window'
    $win = Wait-NvidiaPanelWindow
    if ($win) { return $win }

    Write-Log 'Window not found after timeout'
    return $null
}

function Get-ElementPatterns([System.Windows.Automation.AutomationElement]$el) {
    $list = New-Object System.Collections.Generic.List[string]
    if (-not $el) { return @() }
    $ids = @(
        [System.Windows.Automation.InvokePattern]::Pattern,
        [System.Windows.Automation.SelectionItemPattern]::Pattern,
        [System.Windows.Automation.TogglePattern]::Pattern,
        [System.Windows.Automation.RangeValuePattern]::Pattern,
        [System.Windows.Automation.ExpandCollapsePattern]::Pattern,
        [System.Windows.Automation.ScrollItemPattern]::Pattern,
        [System.Windows.Automation.ValuePattern]::Pattern
    )
    foreach ($id in $ids) {
        try {
            if ($el.GetCurrentPattern($id)) { $list.Add($id.ProgrammaticName) | Out-Null }
        } catch {}
    }
    return $list.ToArray()
}

function Get-ElementInfo([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $null }
    try {
        return [PSCustomObject]@{
            Name           = [string]$el.Current.Name
            ControlType    = $el.Current.ControlType.ProgrammaticName
            AutomationId   = [string]$el.Current.AutomationId
            ClassName      = [string]$el.Current.ClassName
            IsEnabled      = $el.Current.IsEnabled
            IsOffscreen    = $el.Current.IsOffscreen
            Patterns       = (Get-ElementPatterns $el) -join ','
        }
    } catch { return $null }
}

function Get-TextBlob([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return '' }
    $parts = New-Object System.Collections.Generic.List[string]
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                $n = [string]$el.Current.Name
                if ($n) { $parts.Add($n) | Out-Null }
            } catch {}
        }
    } catch {}
    return ($parts -join "`n")
}

function Detect-LanguageFromBlob([string]$blob) {
    if (-not $blob) { return 'unknown' }
    if ($blob -match 'Ajuster|aperçu|apercu|Appliquer|préférences|Performances') { return 'fr' }
    if ($blob -match 'Adjust|preview|Apply|preference|Performance') { return 'en' }
    return 'unknown'
}

function Find-ElementByAliases(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$aliases,
    [System.Windows.Automation.ControlType[]]$types,
    [switch]$AnyControlType
) {
    if (-not $root) { return $null }
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    $bestEl = $null
    $bestLen = 0
    foreach ($el in $all) {
        try {
            $n = [string]$el.Current.Name
            if (-not $n) { continue }
            if (-not $AnyControlType) {
                $ct = $el.Current.ControlType
                if ($types -and ($types -notcontains $ct)) { continue }
            }
            foreach ($a in $aliases) {
                if (-not $a) { continue }
                if ($n.IndexOf($a, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    if ($a.Length -gt $bestLen) {
                        $bestEl = $el
                        $bestLen = $a.Length
                    }
                }
            }
        } catch {}
    }
    return $bestEl
}

function Invoke-Element([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    try {
        $inv = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        if ($inv) { $inv.Invoke(); return $true }
    } catch {}
    try {
        $sel = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sel) { $sel.Select(); return $true }
    } catch {}
    try {
        $tog = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($tog -and $tog.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) {
            $tog.Toggle()
            return $true
        }
    } catch {}
    try {
        $ec = $el.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        if ($ec -and $ec.Current.ExpandCollapseState -eq [System.Windows.Automation.ExpandCollapseState]::Collapsed) {
            $ec.Expand()
            return $true
        }
    } catch {}
    return $false
}

function Scroll-ElementIntoView([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    try {
        $sp = $el.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
        if ($sp) { $sp.ScrollIntoView(); return $true }
    } catch {}
    return $false
}

function Select-Radio([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    Scroll-ElementIntoView $el | Out-Null
    try {
        $sel = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sel) {
            if (-not $sel.Current.IsSelected) { $sel.Select() }
            Start-Sleep -Milliseconds 200
            return $sel.Current.IsSelected
        }
    } catch {}
    if (Invoke-Element $el) {
        Start-Sleep -Milliseconds 200
        return $true
    }
    return $false
}

function Test-RadioSelected([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    try {
        $sel = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sel) { return $sel.Current.IsSelected }
        $tog = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($tog) { return $tog.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On }
    } catch {}
    return $false
}

function Get-NvidiaPanelWindow {
    try {
        foreach ($procName in @('nvcplui', 'NVDisplay.Container', 'nvcontainer')) {
            foreach ($proc in @(Get-Process -Name $procName -ErrorAction SilentlyContinue)) {
                if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
                    $el = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
                    if ($el) { return $el }
                }
            }
        }
        $matchProc = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -ne [IntPtr]::Zero -and
            [string]$_.MainWindowTitle -match 'NVIDIA|Panneau de configuration'
        } | Select-Object -First 1
        if ($matchProc) {
            $el = [System.Windows.Automation.AutomationElement]::FromHandle($matchProc.MainWindowHandle)
            if ($el) { return $el }
        }
    } catch {}
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $all) {
        try {
            $n = [string]$w.Current.Name
            if (-not $n) { continue }
            foreach ($p in $script:PanelWindowPatterns) {
                if ($n.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    return $w
                }
            }
            if ($n -eq 'NVIDIA' -or $n.StartsWith('NVIDIA ')) {
                try {
                    $pid = $w.Current.ProcessId
                    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                    if ($proc -and $proc.ProcessName -match 'nvcplui|nvcontainer') { return $w }
                } catch {}
            }
        } catch {}
    }
    return $null
}

function Wait-NvidiaPanelWindow {
    while ((Get-Date) -lt $script:Deadline) {
        $w = Get-NvidiaPanelWindow
        if ($w) {
            $title = [string]$w.Current.Name
            Write-Log "Window found: $title"
            return $w
        }
        Start-Sleep -Milliseconds 350
    }
    Write-Log 'Window not found before timeout'
    return $null
}

function Set-PanelForeground([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return }
    Ensure-Win32FocusType
    try { [NvPreviewFocus]::FocusElement($win) } catch {}
}

function Start-NvcpluiProcess([string]$nvcpluiPath) {
    $isAdmin = Test-IsProcessElevated
    Write-Log "ELEVATION parent_is_admin=$isAdmin (nvcplui launched without runas to match)"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $nvcpluiPath
        $psi.UseShellExecute = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
        # Never use Verb=runas — avoids UIA elevation mismatch with non-admin HTA
        $p = [System.Diagnostics.Process]::Start($psi)
        if ($p) {
            Write-Log "LAUNCH=ok pid=$($p.Id)"
            return $true
        }
    } catch {
        Write-Log "LAUNCH=fail error=$($_.Exception.Message)"
    }
    return $false
}

function Open-PreviewPage([System.Windows.Automation.AutomationElement]$win) {
    $types = @(
        [System.Windows.Automation.ControlType]::TreeItem,
        [System.Windows.Automation.ControlType]::ListItem,
        [System.Windows.Automation.ControlType]::Hyperlink,
        [System.Windows.Automation.ControlType]::MenuItem,
        [System.Windows.Automation.ControlType]::Text
    )
    $page = Find-ElementByAliases $win $script:PreviewPageAliases $types
    if ($page) { return $page }
    $parent = Find-ElementByAliases $win $script:NavParentAliases $types
    if ($parent) {
        Write-Log 'NAV=expanding parent 3D/image settings node'
        Invoke-Element $parent | Out-Null
        Start-Sleep -Milliseconds 600
        $page = Find-ElementByAliases $win $script:PreviewPageAliases $types
        if ($page) { return $page }
    }
    return Find-ElementByAliases $win $script:PreviewPageAliases @() -AnyControlType
}

function Find-PreferenceRadio([System.Windows.Automation.AutomationElement]$root) {
    $radioType = [System.Windows.Automation.ControlType]::RadioButton
    $el = Find-ElementByAliases $root $script:PreferenceRadioAliases @($radioType)
    if ($el) { return $el }
    return Find-ElementByAliases $root $script:PreferenceRadioAliases @() -AnyControlType
}

function Find-PerformanceSlider([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return $null }
    $sliderType = [System.Windows.Automation.ControlType]::Slider
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($el in $all) {
        try {
            $rv = $el.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
            if (-not $rv) { continue }
            $min = $rv.Current.Minimum
            $max = $rv.Current.Maximum
            if ($max -le $min) { continue }
            $n = [string]$el.Current.Name
            $score = 0
            if ($el.Current.ControlType -eq $sliderType) { $score += 3 }
            if ($n -match 'Qualit|Quality|Perform|Perf|accent|image|aperçu|preview') { $score += 2 }
            $candidates.Add([PSCustomObject]@{ Element = $el; Score = $score; Range = $rv }) | Out-Null
        } catch {}
    }
    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object Score -Descending | Select-Object -First 1).Element
}

function Get-SliderRangeInfo([System.Windows.Automation.AutomationElement]$slider) {
    try {
        $rv = $slider.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
        if (-not $rv) { return $null }
        return @{
            Min     = $rv.Current.Minimum
            Max     = $rv.Current.Maximum
            Value   = $rv.Current.Value
            Large   = $rv.Current.LargeChange
            Small   = $rv.Current.SmallChange
            Pattern = $true
        }
    } catch { return @{ Pattern = $false } }
}

function Get-PerformanceTargetValue([double]$min, [double]$max, [System.Windows.Automation.AutomationElement]$root) {
    # NVIDIA : Performance à gauche → Minimum (consigne utilisateur)
    $blob = Get-TextBlob $root
    if ($blob -match 'Qualit|Quality' -and $blob -match 'Perform') {
        $qi = $blob.IndexOf('Qualit', [System.StringComparison]::OrdinalIgnoreCase)
        if ($qi -lt 0) { $qi = $blob.IndexOf('Quality', [System.StringComparison]::OrdinalIgnoreCase) }
        $pi = $blob.IndexOf('Perform', [System.StringComparison]::OrdinalIgnoreCase)
        if ($qi -ge 0 -and $pi -ge 0 -and $pi -lt $qi) { return $min }
        if ($qi -ge 0 -and $pi -ge 0 -and $pi -gt $qi) { return $max }
    }
    return $min
}

function Set-SliderViaRange([System.Windows.Automation.AutomationElement]$slider, [double]$target) {
    try {
        $rv = $slider.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
        if (-not $rv) { return $false }
        $rv.SetValue($target)
        Start-Sleep -Milliseconds 300
        return [Math]::Abs($rv.Current.Value - $target) -le 1.0
    } catch { return $false }
}

function Set-SliderViaKeyboard([System.Windows.Automation.AutomationElement]$slider) {
    Ensure-Win32FocusType
    try { [NvPreviewFocus]::FocusElement($slider) } catch {}
    Start-Sleep -Milliseconds 200
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.SendKeys]::SendWait('{HOME}')
        Start-Sleep -Milliseconds 150
        for ($i = 0; $i -lt 6; $i++) {
            [System.Windows.Forms.SendKeys]::SendWait('{LEFT}')
            Start-Sleep -Milliseconds 80
        }
        return $true
    } catch {
        Write-Log "SLIDER keyboard fallback failed: $($_.Exception.Message)"
        return $false
    }
}

function Set-SliderToPerformance([System.Windows.Automation.AutomationElement]$slider, [System.Windows.Automation.AutomationElement]$root, [ref]$usedKeyboard) {
    $usedKeyboard.Value = $false
    $info = Get-SliderRangeInfo $slider
    if ($info.Pattern) {
        $target = Get-PerformanceTargetValue $info.Min $info.Max $root
        Write-Log "SLIDER RangeValue min=$($info.Min) max=$($info.Max) current=$($info.Value) target=$target"
        if (Set-SliderViaRange $slider $target) { return $true }
        if ($target -ne $info.Min -and (Set-SliderViaRange $slider $info.Min)) { return $true }
        if (Set-SliderViaRange $slider $info.Max) { return $true }
    } else {
        Write-Log 'SLIDER RangeValuePattern=not_available'
    }
    $usedKeyboard.Value = $true
    Write-Log 'SLIDER trying keyboard fallback HOME+LEFT'
    return (Set-SliderViaKeyboard $slider)
}

function Test-SliderAtPerformance([System.Windows.Automation.AutomationElement]$slider, [System.Windows.Automation.AutomationElement]$root) {
    $info = Get-SliderRangeInfo $slider
    if (-not $info.Pattern) { return $false }
    $target = Get-PerformanceTargetValue $info.Min $info.Max $root
    $span = $info.Max - $info.Min
    if ($span -le 0) { return $false }
    return [Math]::Abs($info.Value - $target) -le ($span * 0.1)
}

function Find-ApplyButton([System.Windows.Automation.AutomationElement]$root) {
    $buttonType = [System.Windows.Automation.ControlType]::Button
    return Find-ElementByAliases $root $script:ApplyButtonAliases @($buttonType)
}

function Invoke-ApplyButton([System.Windows.Automation.AutomationElement]$btn) {
    if (-not $btn) { return $false }
    try {
        if (-not $btn.Current.IsEnabled) {
            Write-Log 'APPLY button disabled, maybe already applied'
            return $true
        }
    } catch {}
    return (Invoke-Element $btn)
}

function Run-DiagnoseDump([System.Windows.Automation.AutomationElement]$win) {
    Write-Log 'DIAGNOSE=begin element dump (keyword filter)'
    if (-not $win) {
        Write-Log 'DIAGNOSE=no window'
        return
    }
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    $count = 0
    foreach ($el in $all) {
        if (Test-StepTimeout 'diagnose') { break }
        try {
            $n = [string]$el.Current.Name
            $aid = [string]$el.Current.AutomationId
            $hay = ($n + ' ' + $aid).ToLowerInvariant()
            $match = $false
            foreach ($kw in $script:DiagnoseKeywords) {
                if ($hay.Contains($kw)) { $match = $true; break }
            }
            if (-not $match) { continue }
            $info = Get-ElementInfo $el
            if ($info) {
                Write-Log ('DIAG ' + ($info | ConvertTo-Json -Compress))
                $count++
            }
        } catch {}
        if ($count -ge 120) {
            Write-Log 'DIAGNOSE=truncated at 120 elements'
            break
        }
    }
    Write-Log "DIAGNOSE=end count=$count"
}

# --- Main ---
$messages = @()
try {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $script:UiAssemblyOk = $true
} catch {
    Write-Log 'FAIL=UI Automation assembly load error'
    Exit-WithResult $false $false 'Unavailable' @('UI Automation indisponible') 1 'uia_assembly_error'
}

Write-Log '=== nvidia preview performance ==='
Write-Log ('ACTION=' + $(if ($DiagnosePreviewPerformance) { 'diagnose_preview_performance' } else { 'apply_preview_performance' }))
Write-Log "TIMEOUT_SECONDS=$TimeoutSeconds"

$win = Launch-NvidiaControlPanel
if (-not $win) {
    Write-Log 'FAIL=Panneau NVIDIA introuvable'
    Exit-WithResult $false $false 'Unavailable' @('Panneau NVIDIA introuvable') 1 'panel_not_found'
}

$title = [string]$win.Current.Name
Write-Log "WINDOW_TITLE=$title"
$blob0 = Get-TextBlob $win
$script:DetectedLanguage = Detect-LanguageFromBlob $blob0
Write-Log "LANGUAGE_DETECTED=$($script:DetectedLanguage)"

if ($DiagnosePreviewPerformance) {
    Run-DiagnoseDump $win
    Exit-WithResult $false $false 'Unavailable' @('Mode diagnostic — voir nvidia-preview-performance.log') 0 'diagnose_only'
}

Set-PanelForeground $win
Start-Sleep -Milliseconds 500
if (Test-StepTimeout 'after_window') {
    Exit-WithResult $false $false 'Unavailable' @('Preview performance timeout') 1 'timeout'
}

$pageEl = Open-PreviewPage $win
if (-not $pageEl) {
    Write-Log 'FAIL=Preview page not found'
    Run-DiagnoseDump $win
    Exit-WithResult $false $false 'Unavailable' @('Page aperçu image introuvable') 1 'preview_page_not_found'
}
Write-Log ('PREVIEW_PAGE found name=' + [string]$pageEl.Current.Name)
if (-not (Invoke-Element $pageEl)) {
    Write-Log 'WARN=Preview page invoke/selection failed, continuing'
}
Start-Sleep -Milliseconds 900
if (Test-StepTimeout 'after_page') {
    Exit-WithResult $false $false 'Unavailable' @('Preview performance timeout') 1 'timeout'
}

$win = Get-NvidiaPanelWindow
if (-not $win) { $win = Wait-NvidiaPanelWindow }
Set-PanelForeground $win

$prefRadio = Find-PreferenceRadio $win
if (-not $prefRadio) {
    Write-Log 'FAIL=Preference radio not found'
    Run-DiagnoseDump $win
    Exit-WithResult $false $false 'Unavailable' @('Radio préférence introuvable') 1 'preference_radio_not_found'
}
Write-Log ('PREFERENCE_RADIO found name=' + [string]$prefRadio.Current.Name)
if (-not (Select-Radio $prefRadio)) {
    Write-Log 'FAIL=Preference radio selection failed'
    Exit-WithResult $false $false 'Unavailable' @('Sélection radio préférence impossible') 1 'preference_radio_select_failed'
}
Write-Log 'PREFERENCE_RADIO selected'
Start-Sleep -Milliseconds 400

$slider = Find-PerformanceSlider $win
if (-not $slider) {
    Write-Log 'FAIL=Performance slider not found'
    Run-DiagnoseDump $win
    Exit-WithResult $false $false 'Unavailable' @('Curseur Performance introuvable') 1 'slider_not_found'
}
$sliderInfo = Get-SliderRangeInfo $slider
if ($sliderInfo.Pattern) {
    Write-Log "SLIDER found RangeValue min=$($sliderInfo.Min) max=$($sliderInfo.Max) current=$($sliderInfo.Value)"
} else {
    Write-Log 'SLIDER found but RangeValuePattern not available'
}

$usedKb = $false
$sliderMoved = Set-SliderToPerformance $slider $win ([ref]$usedKb)
if ($sliderMoved) {
    Write-Log $(if ($usedKb) { 'SLIDER moved via keyboard' } else { 'SLIDER moved via RangeValue' })
} else {
    Write-Log 'WARN=Slider move uncertain'
    $messages += 'Curseur déplacé, position incertaine'
}

if (Test-StepTimeout 'before_apply') {
    Exit-WithResult $false $false 'Unavailable' @('Preview performance timeout') 1 'timeout'
}

$applyBtn = Find-ApplyButton $win
if (-not $applyBtn) {
    Write-Log 'FAIL=Apply button not found'
    Run-DiagnoseDump $win
    Exit-WithResult $false $false 'Unavailable' @('Bouton Appliquer introuvable') 1 'apply_button_not_found'
}
Write-Log ('APPLY_BUTTON found name=' + [string]$applyBtn.Current.Name)
if (-not (Invoke-ApplyButton $applyBtn)) {
    Write-Log 'FAIL=Apply button invoke failed'
    Exit-WithResult $false $false 'Unavailable' @('Clic Appliquer impossible') 1 'apply_button_failed'
}
Write-Log 'Apply clicked'
Start-Sleep -Milliseconds 1200

$win = Get-NvidiaPanelWindow
if ($win) {
    Set-PanelForeground $win
    $prefRadio2 = Find-PreferenceRadio $win
    $slider2 = Find-PerformanceSlider $win
    $prefOk = Test-RadioSelected $prefRadio2
    $sliderOk = $slider2 -and (Test-SliderAtPerformance $slider2 $win)
    Write-Log "VERIFY preference_selected=$prefOk slider_at_performance=$sliderOk"
    if ($prefOk -and $sliderOk) {
        Write-Log 'SUCCESS=Preview performance verified'
        Exit-WithResult $true $true 'Performance' $messages 0 ''
    }
    if ($prefOk -or $sliderOk) {
        Write-Log 'PARTIAL=Preview performance partially verified'
        Exit-WithResult $true $false 'Performance' @('Vérification partielle') 2 'partial_verify'
    }
}

Write-Log 'PARTIAL=Applied but not verified after apply'
Exit-WithResult $true $false 'Performance' @('Application tentée, relecture non confirmée') 2 'not_verified'
