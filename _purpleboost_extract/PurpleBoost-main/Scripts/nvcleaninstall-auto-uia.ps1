# NVCleanstall wizard automation — source of truth: written list only (nvcleaninstall-auto.ahk)
param(
    [string]$LiveStatusPath = '',
    [string]$LogPath = '',
    [ValidateSet('wizard', 'nvcleanstall-loop', 'postinstall', 'tweaks', 'next', 'finished', 'install-only', 'wait-tweaks', 'finished-install', 'package-ready-install', 'nvidia-wizard', 'nvidia-installer-tick')]
    [string]$Phase = 'wizard'
)

$ErrorActionPreference = 'Continue'
$script:WorkflowPollMs = 200
$script:SafeClickBlockCoordinateFallbacks = $true

function Write-SafeClickBlocked([string]$context) {
    Write-BlockedUnsafeClick $context
    Set-LogField 'SAFECLICK_BLOCKED' $context
}

function Write-NvcManualUiRequired([string]$context) {
    Write-LiveStatus '[NVCleanstall] Bouton introuvable via UIA, action manuelle requise.'
    Set-LogField 'NVC_UI_MANUAL' $context
}

function Write-TimingLog([string]$label, [int]$elapsedMs) {
    $suffix = if ($elapsedMs -ge 0) { " en ${elapsedMs} ms." } else { '.' }
    $line = "[Timing] ${label}${suffix}"
    Write-LiveStatus $line
    if ($LogPath) {
        try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 } catch {}
    }
}

$script:TweakSearchTimeoutMs = 2800
$script:MaxScrollsPerTweak = 3
$script:MaxGlobalScrolls = 3
$script:TweakActionDelayMs = 550

function Write-LiveStatus([string]$msg) {
    if (-not $LiveStatusPath) { return }
    try {
        $dir = Split-Path -Parent $LiveStatusPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $LiveStatusPath -Value ("STATUS=" + $msg) -Encoding UTF8
    } catch {}
}

. (Join-Path $PSScriptRoot 'Safe-UiaClick.ps1')
$script:SafeUiaLogFn = { param([string]$m) Write-LiveStatus $m }

function Set-LogField([string]$key, [string]$value) {
    if ($LogPath) {
        try {
            Add-Content -LiteralPath $LogPath -Value ($key + '=' + $value) -Encoding UTF8
        } catch {}
    }
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

function Get-NvcRootWindow {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $all) {
        try {
            $n = [string]$w.Current.Name
            $cn = [string]$w.Current.ClassName
            if ($n -match 'NVCleanstall|NVCleanInstall|TechPowerUp.*Clean') { return $w }
            if ($cn -match 'Windows\.UI\.Core\.Window|HwndWrapper' -and $n -match 'Clean') { return $w }
        } catch {}
    }
    return $null
}

function Wait-NvcWindow([int]$seconds) {
    $t0 = [DateTime]::UtcNow
    Write-TimingLog 'Attente NVCleanstall démarrée' -1
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $w = Get-NvcRootWindow
        if ($w) {
            Write-TimingLog 'NVCleanstall page détectée' ([int](([DateTime]::UtcNow - $t0).TotalMilliseconds))
            return $w
        }
        Start-Sleep -Milliseconds $script:WorkflowPollMs
    }
    return $null
}

function Test-PageContains([string]$blob, [string[]]$patterns) {
    if (-not $blob) { return $false }
    $u = $blob.ToUpperInvariant()
    foreach ($p in $patterns) {
        $pu = $p.ToUpperInvariant()
        if ($u.Contains($pu)) { return $true }
        try {
            if ($u -match $p) { return $true }
        } catch {}
    }
    return $false
}

function Find-ElementByAliases(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$aliases,
    [System.Windows.Automation.ControlType[]]$types
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
            $ct = $el.Current.ControlType
            if ($types -and ($types -notcontains $ct)) { continue }
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

function Find-ElementByNameMatch(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$patterns,
    [System.Windows.Automation.ControlType[]]$types
) {
    if (-not $root) { return $null }
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el in $all) {
        try {
            $n = [string]$el.Current.Name
            if (-not $n) { continue }
            $ct = $el.Current.ControlType
            if ($types -and ($types -notcontains $ct)) { continue }
            foreach ($p in $patterns) {
                if ($n -match $p) { return $el }
            }
        } catch {}
    }
    return $null
}

function Invoke-Element([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    try {
        $inv = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        if ($inv) { $inv.Invoke(); return $true }
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

function Invoke-ScrollDown([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return $false }
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                $sp = $el.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
                if ($sp -and $sp.Current.VerticallyScrollable) {
                    $sp.Scroll([System.Windows.Automation.ScrollAmount]::LargeIncrement)
                    return $true
                }
            } catch {}
        }
    } catch {}
    return $false
}

function Find-ToggleByPartialAliases(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$aliases
) {
    if (-not $root) { return $null }
    $bestEl = $null
    $bestLen = 0
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el in $all) {
        try {
            $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if (-not $toggle) { continue }
            $n = [string]$el.Current.Name
            if (-not $n) { continue }
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

function Get-ToggleStateFromElement([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return @{ Status = 'not_found'; Element = $null } }
    try {
        Scroll-ElementIntoView $el | Out-Null
        $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle) {
            $st = $toggle.Current.ToggleState
            if ($st -eq [System.Windows.Automation.ToggleState]::On) {
                return @{ Status = 'already_checked'; Element = $el }
            }
            return @{ Status = 'unchecked'; Element = $el }
        }
    } catch {}
    return @{ Status = 'error'; Element = $el }
}

function Get-CheckBoxStateByAliases(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$aliases
) {
    $cbType = [System.Windows.Automation.ControlType]::CheckBox
    $el = Find-ElementByAliases $root $aliases @($cbType)
    if (-not $el) {
        $el = Find-ToggleByPartialAliases $root $aliases
    }
    if (-not $el) { return @{ Status = 'not_found'; Element = $null } }
    try {
        Scroll-ElementIntoView $el | Out-Null
        $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle) {
            $st = $toggle.Current.ToggleState
            if ($st -eq [System.Windows.Automation.ToggleState]::On) {
                return @{ Status = 'already_checked'; Element = $el }
            }
            return @{ Status = 'unchecked'; Element = $el }
        }
    } catch {}
    return @{ Status = 'error'; Element = $el }
}

function Ensure-CheckBoxCheckedByAliasesOnce(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$aliases
) {
    $state = Get-CheckBoxStateByAliases $root $aliases
    if ($state.Status -eq 'not_found') { return 'not_found' }
    if ($state.Status -eq 'already_checked') { return 'already_checked' }
    if ($state.Status -eq 'error') { return 'error' }
    $el = $state.Element
    try {
        $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle) {
            $toggle.Toggle()
            Start-Sleep -Milliseconds 150
            if ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) {
                return 'ok'
            }
            return 'error'
        }
    } catch {
        if (Invoke-Element $el) { return 'ok' }
        return 'error'
    }
    return 'error'
}

function Ensure-TweakCheckedByAliases(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$aliases,
    [ref]$globalScrolls,
    [int]$maxGlobalScrolls = 2
) {
    $deadline = (Get-Date).AddMilliseconds($script:TweakSearchTimeoutMs)
    $localScrolls = 0
    while ((Get-Date) -lt $deadline) {
        $r = Ensure-CheckBoxCheckedByAliasesOnce $root $aliases
        if ($r -ne 'not_found') { return $r }
        if ($localScrolls -lt $script:MaxScrollsPerTweak) {
            if (Invoke-ScrollDown $root) {
                $localScrolls++
                if ($globalScrolls.Value -lt $maxGlobalScrolls) { $globalScrolls.Value++ }
                Set-LogField 'SCROLL_USED' 'oui'
                Start-Sleep -Milliseconds 500
            } else {
                Start-Sleep -Milliseconds 200
            }
        } else {
            Start-Sleep -Milliseconds 150
        }
    }
    return 'not_found'
}

function Set-NvcForeground([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return }
    try {
        $hwnd = [int]$win.Current.NativeWindowHandle
        if ($hwnd -eq 0) { return }
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NvcWin32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue | Out-Null
        [NvcWin32]::SetForegroundWindow([IntPtr]$hwnd) | Out-Null
    } catch {}
}

function Get-DescendantCount([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return 0 }
    try {
        return $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition).Count
    } catch { return 0 }
}

function Get-TweakStatusLabel([string]$optionName) {
    if ($optionName -match 'MPO') { return 'Disable MPO' }
    if ($optionName -match 'HDCP') { return 'Disable HDCP' }
    if ($optionName -match 'Ansel') { return 'Disable Ansel' }
    if ($optionName -match 'Expert') { return 'Show Expert Tweaks' }
    if ($optionName -match 'Telemetry & Advertising') { return 'Disable Installer Telemetry' }
    if ($optionName -match 'Clean Installation') { return 'Clean Installation' }
    if ($optionName -match 'Driver Telemetry') { return 'Disable Driver Telemetry' }
    if ($optionName -match 'Message Signaled') { return 'Enable MSI' }
    if ($optionName -match 'Anti-Cheat') { return 'Easy Anti-Cheat' }
    if ($optionName -match 'unsigned') { return 'Unsigned warning' }
    return $optionName
}

function Invoke-ClickClientRelative(
    [System.Windows.Automation.AutomationElement]$root,
    [double]$relX,
    [double]$relY
) {
    Write-BlockedUnsafeClick "Invoke-ClickClientRelative pourcentage client ${relX}/${relY}"
    Write-LiveStatus '[NVCleanstall] Fallback coordonnées désactivé pour sécurité.'
    Write-NvcManualUiRequired "client_relative_${relX}_${relY}"
    return $false
}

function Get-SortedToggleRows([System.Windows.Automation.AutomationElement]$root) {
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $root) { return @() }
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el in $all) {
        try {
            $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if (-not $toggle) { continue }
            $rect = $el.Current.BoundingRectangle
            $list.Add([PSCustomObject]@{
                Element = $el
                Toggle = $toggle
                Y = [double]$rect.Y
                X = [double]$rect.X
                Name = [string]$el.Current.Name
                IsOn = ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On)
            }) | Out-Null
        } catch {}
    }
    return @($list | Sort-Object { $_.Y }, { $_.X })
}

function Invoke-ToggleRowClick([object]$row) {
    if (-not $row) { return 'not_found' }
    try {
        Scroll-ElementIntoView $row.Element | Out-Null
        Start-Sleep -Milliseconds 120
        if ($row.IsOn) { return 'already_checked' }
        $row.Toggle.Toggle()
        Start-Sleep -Milliseconds 180
        if ($row.Toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) {
            return 'ok'
        }
    } catch {}
    return 'error'
}

function Invoke-EacSpecialFixByControlOrder([System.Windows.Automation.AutomationElement]$root) {
    Set-LogField 'EAC_SPECIAL_FIX_STARTED' 'oui'
    Set-LogField 'EAC_CLICKED_BY_CONTROL_ORDER' 'non'
    Set-LogField 'EAC_CLICKED_BY_WINDOW_RELATIVE_FALLBACK' 'non'
    if (-not $root) {
        Set-LogField 'REBUILD_SIGNATURE_FOUND' 'non'
        Set-LogField 'EAC_CHECKBOX_UNDER_REBUILD_FOUND' 'non'
        Set-LogField 'EAC_FINAL_RESULT' 'error'
        return 'not_found'
    }

    $rows = Get-SortedToggleRows $root
    $rebuildIdx = -1
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $n = [string]$rows[$i].Name
        if ($n -and $n.IndexOf('Rebuild digital signature', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $rebuildIdx = $i
            break
        }
    }

    $blob = Get-TextBlob $root
    $rebuildInBlob = Test-BlobContainsAny $blob @('REBUILD DIGITAL SIGNATURE', 'DIGITAL SIGNATURE')
    if ($rebuildIdx -ge 0 -or $rebuildInBlob) {
        Set-LogField 'REBUILD_SIGNATURE_FOUND' 'oui'
    } else {
        Set-LogField 'REBUILD_SIGNATURE_FOUND' 'non'
    }

    if ($rebuildIdx -ge 0) {
        for ($j = $rebuildIdx + 1; $j -lt $rows.Count; $j++) {
            $r = $rows[$j]
            $n = [string]$r.Name
            if ($n -and $n.IndexOf('Rebuild digital signature', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                continue
            }
            if ($n -and $n.IndexOf('Automatically accept', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                break
            }
            Set-LogField 'EAC_CHECKBOX_UNDER_REBUILD_FOUND' 'oui'
            $clickR = Invoke-ToggleRowClick $r
            if ($clickR -eq 'ok' -or $clickR -eq 'already_checked') {
                Set-LogField 'EAC_CLICKED_BY_CONTROL_ORDER' 'oui'
                Set-LogField 'EAC_FINAL_RESULT' 'ok'
                return $clickR
            }
        }
    }

    if ($rebuildInBlob) {
        $rebuildY = $null
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                $n = [string]$el.Current.Name
                if ($n -and $n.IndexOf('Rebuild digital signature', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $rebuildY = [double]$el.Current.BoundingRectangle.Y
                    break
                }
            } catch {}
        }
        if ($null -ne $rebuildY) {
            foreach ($r in $rows) {
                if ($r.Y -le $rebuildY + 4) { continue }
                $n = [string]$r.Name
                if ($n -and $n.IndexOf('Automatically accept', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    break
                }
                Set-LogField 'EAC_CHECKBOX_UNDER_REBUILD_FOUND' 'oui'
                $clickR = Invoke-ToggleRowClick $r
                if ($clickR -eq 'ok' -or $clickR -eq 'already_checked') {
                    Set-LogField 'EAC_CLICKED_BY_CONTROL_ORDER' 'oui'
                    Set-LogField 'EAC_FINAL_RESULT' 'ok'
                    return $clickR
                }
            }
        }
    }

    Write-UiaDumpForElement $root 'EAC checkbox introuvable après ordre des contrôles'
    Write-NvcManualUiRequired 'eac_checkbox'
    Set-LogField 'EAC_FINAL_RESULT' 'manual_required'
    return 'not_found'
}

function Click-FirstUncheckedToggleAfterMarker(
    [System.Windows.Automation.AutomationElement]$root,
    [string]$marker,
    [string[]]$skipNameContains
) {
    if (-not $root) { return 'not_found' }
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    $pastMarker = $false
    foreach ($el in $all) {
        try {
            $n = [string]$el.Current.Name
            if (-not $pastMarker) {
                if ($n -and $n.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $pastMarker = $true
                }
                continue
            }
            if (-not $n) { continue }
            $skip = $false
            foreach ($s in $skipNameContains) {
                if ($n.IndexOf($s, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $skip = $true
                    break
                }
            }
            if ($skip) { continue }
            $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if (-not $toggle) { continue }
            if ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) {
                continue
            }
            Scroll-ElementIntoView $el | Out-Null
            Start-Sleep -Milliseconds 120
            $toggle.Toggle()
            Start-Sleep -Milliseconds 180
            if ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) {
                return 'ok'
            }
        } catch {}
    }
    return 'not_found'
}

function Test-BlobContainsAny([string]$blob, [string[]]$patterns) {
    if (-not $blob) { return $false }
    $u = $blob.ToUpperInvariant()
    foreach ($p in $patterns) {
        if (-not $p) { continue }
        if ($u.Contains($p.ToUpperInvariant())) { return $true }
    }
    return $false
}

function Apply-BottomPageTweaks(
    [ref]$globalScrolls,
    [ref]$clickedCount,
    [ref]$optionStatuses,
    [ref]$attemptedCount
) {
    Set-LogField 'EAC_SEARCH_STARTED' 'oui'
    $eacPartialPatterns = @(
        'USE METHOD COMPATIBLE WITH EASY-ANTI-CHEAT', 'USE METHOD COMPATIBLE',
        'EASY-ANTI-CHEAT', 'EASY ANTI-CHEAT', 'ANTI-CHEAT', 'DRIVER UNSIGNED WARNING',
        'TRIGGERS A', 'WARNING DURING INSTALLATION'
    )
    $eacAliases = @(
        'Use method compatible with Easy-Anti-Cheat',
        'Use method compatible with Easy Anti-Cheat',
        'Use method compatible',
        'compatible with Easy-Anti-Cheat',
        'compatible with Easy Anti-Cheat',
        'triggers a "driver unsigned" warning',
        'triggers a driver unsigned warning',
        'driver unsigned warning during installation',
        'driver unsigned warning',
        'Easy-Anti-Cheat',
        'Easy Anti-Cheat',
        'Anti-Cheat',
        'Anti Cheat',
        'EAC'
    )
    $unsignedAliases = @(
        'Automatically accept the "driver unsigned" warning',
        'Automatically accept the driver unsigned warning',
        'accept the "driver unsigned" warning',
        'accept the driver unsigned warning',
        'driver unsigned" warning',
        'driver unsigned warning',
        'driver unsigned'
    )
    $scrollMarkers = @(
        'REBUILD DIGITAL SIGNATURE', 'EASY-ANTI-CHEAT', 'EASY ANTI-CHEAT',
        'ANTI-CHEAT', 'DRIVER UNSIGNED', 'DIGITAL SIGNATURE'
    )

    $eacScrollAttempts = 0
    $win = Get-NvcRootWindow
    if (-not $win) {
        Set-LogField 'EAC_SCROLL_ATTEMPTS' '0'
        Set-LogField 'EAC_FOUND' 'non'
        Set-LogField 'EAC_CLICKED' 'non'
        Set-LogField 'UNSIGNED_WARNING_FOUND' 'non'
        Set-LogField 'UNSIGNED_WARNING_CLICKED' 'non'
        return
    }

    for ($i = 0; $i -lt 3; $i++) {
        Set-NvcForeground $win
        $win = Get-NvcRootWindow
        $blob = Get-TextBlob $win
        $eacState = Get-CheckBoxStateByAliases $win $eacAliases
        if ($eacState.Status -ne 'not_found') { break }
        if (Test-BlobContainsAny $blob $scrollMarkers) { break }
        if (Invoke-ScrollDown $win) {
            $eacScrollAttempts++
            if ($globalScrolls.Value -lt $script:MaxGlobalScrolls) { $globalScrolls.Value++ }
            Set-LogField 'SCROLL_USED' 'oui'
            Start-Sleep -Milliseconds 500
        } else {
            Start-Sleep -Milliseconds 300
        }
    }
    Set-LogField 'EAC_SCROLL_ATTEMPTS' ([string]$eacScrollAttempts)

    $win = Get-NvcRootWindow
    Set-NvcForeground $win
    $blob = Get-TextBlob $win
    $eacName = 'Use method compatible with Easy Anti-Cheat'
    $eacTextFound = Test-BlobContainsAny $blob $eacPartialPatterns
    Set-LogField 'EAC_TEXT_FOUND' $(if ($eacTextFound) { 'oui' } else { 'non' })

    $eacR = Invoke-EacSpecialFixByControlOrder $win

    if ($eacR -eq 'not_found') {
        $eacState = Get-CheckBoxStateByAliases $win $eacAliases
        Set-LogField 'EAC_FOUND' $(if ($eacState.Status -ne 'not_found') { 'oui' } else { 'non' })
        Set-LogField 'EAC_FOUND_BY_PARTIAL_TEXT' $(if ($eacState.Status -ne 'not_found') { 'oui' } else { 'non' })
        for ($try = 0; $try -lt 2; $try++) {
            $win = Get-NvcRootWindow
            if (-not $win) { break }
            Set-NvcForeground $win
            $eacR = Ensure-TweakCheckedByAliases $win $eacAliases ([ref]$globalScrolls) $script:MaxGlobalScrolls
            if ($eacR -eq 'ok' -or $eacR -eq 'already_checked') { break }
            if (Invoke-ScrollDown $win) {
                if ($globalScrolls.Value -lt $script:MaxGlobalScrolls) { $globalScrolls.Value++ }
                Set-LogField 'SCROLL_USED' 'oui'
                Start-Sleep -Milliseconds 500
                $eacR = Invoke-EacSpecialFixByControlOrder $win
            }
        }
    }

    if ($eacR -eq 'ok' -or $eacR -eq 'already_checked') {
        Set-LogField 'EAC_FOUND' 'oui'
        Set-LogField 'EAC_FOUND_BY_PARTIAL_TEXT' 'oui'
    }

    Write-LiveStatus 'Application : Easy Anti-Cheat'
    Set-LogField 'CURRENT_OPTION' $eacName
    switch ($eacR) {
        'ok' {
            Set-LogField 'OPTION_FOUND' 'oui'
            Set-LogField 'OPTION_CLICKED' 'oui'
            Set-LogField 'EAC_CLICKED' 'oui'
            $clickedCount.Value++
            $optionStatuses[$eacName] = 'ok'
        }
        'already_checked' {
            Set-LogField 'OPTION_FOUND' 'oui'
            Set-LogField 'OPTION_ALREADY_CHECKED' 'oui'
            Set-LogField 'EAC_CLICKED' 'oui'
            $clickedCount.Value++
            $optionStatuses[$eacName] = 'already_checked'
        }
        default {
            if ($eacTextFound) {
                Set-LogField 'OPTION_FOUND' 'oui'
            }
            Set-LogField 'OPTION_NOT_FOUND_CONTINUED' 'oui'
            Set-LogField 'EAC_CLICKED' 'non'
            $optionStatuses[$eacName] = 'not_found'
        }
    }
    $attemptedCount.Value++
    Start-Sleep -Milliseconds $script:TweakActionDelayMs

    $unsignedName = 'Automatically accept the driver unsigned warning'
    Set-LogField 'UNSIGNED_WARNING_SEARCH_STARTED' 'oui'
    $win = Get-NvcRootWindow
    Set-NvcForeground $win
    $uState = Get-CheckBoxStateByAliases $win $unsignedAliases
    Set-LogField 'UNSIGNED_WARNING_FOUND' $(if ($uState.Status -ne 'not_found') { 'oui' } else { 'non' })

    $uR = Ensure-TweakCheckedByAliases $win $unsignedAliases ([ref]$globalScrolls) $script:MaxGlobalScrolls
    if ($uR -eq 'not_found' -and (Invoke-ScrollDown $win)) {
        Start-Sleep -Milliseconds 500
        $win = Get-NvcRootWindow
        $uR = Ensure-TweakCheckedByAliases $win $unsignedAliases ([ref]$globalScrolls) $script:MaxGlobalScrolls
    }

    Write-LiveStatus 'Application : Unsigned warning'
    Set-LogField 'CURRENT_OPTION' $unsignedName
    switch ($uR) {
        'ok' {
            Set-LogField 'OPTION_FOUND' 'oui'
            Set-LogField 'OPTION_CLICKED' 'oui'
            Set-LogField 'UNSIGNED_WARNING_CLICKED' 'oui'
            Set-LogField 'TWEAK_UNSIGNED_WARNING' 'ok'
            $clickedCount.Value++
            $optionStatuses[$unsignedName] = 'ok'
        }
        'already_checked' {
            Set-LogField 'OPTION_FOUND' 'oui'
            Set-LogField 'OPTION_ALREADY_CHECKED' 'oui'
            Set-LogField 'UNSIGNED_WARNING_CLICKED' 'oui'
            Set-LogField 'TWEAK_UNSIGNED_WARNING' 'ok'
            $clickedCount.Value++
            $optionStatuses[$unsignedName] = 'already_checked'
        }
        default {
            Set-LogField 'OPTION_NOT_FOUND_CONTINUED' 'oui'
            Set-LogField 'UNSIGNED_WARNING_CLICKED' 'non'
            Set-LogField 'TWEAK_UNSIGNED_WARNING' 'not_found'
            $optionStatuses[$unsignedName] = 'not_found'
        }
    }
    $attemptedCount.Value++
    Start-Sleep -Milliseconds $script:TweakActionDelayMs
}

function Apply-TweakOption(
    [System.Windows.Automation.AutomationElement]$root,
    [string]$optionName,
    [string[]]$aliases,
    [ref]$globalScrolls,
    [ref]$clickedCount,
    [ref]$attemptedCount
) {
    $attemptedCount.Value++
    $label = Get-TweakStatusLabel $optionName
    Write-LiveStatus ('Application : ' + $label)
    Set-LogField 'CURRENT_OPTION' $optionName
    Set-LogField 'OPTION_FOUND' 'non'
    Set-LogField 'OPTION_CLICKED' 'non'
    Set-LogField 'OPTION_ALREADY_CHECKED' 'non'
    Set-LogField 'OPTION_NOT_FOUND_CONTINUED' 'non'
    Set-LogField 'SCROLL_USED' 'non'

    $state = Get-CheckBoxStateByAliases $root $aliases
    if ($state.Status -ne 'not_found') {
        Set-LogField 'OPTION_FOUND' 'oui'
    }

    $r = Ensure-TweakCheckedByAliases $root $aliases ([ref]$globalScrolls) $script:MaxGlobalScrolls
    switch ($r) {
        'ok' {
            Set-LogField 'OPTION_CLICKED' 'oui'
            $clickedCount.Value++
        }
        'already_checked' {
            Set-LogField 'OPTION_ALREADY_CHECKED' 'oui'
            $clickedCount.Value++
        }
        default {
            Set-LogField 'OPTION_NOT_FOUND_CONTINUED' 'oui'
        }
    }
    Start-Sleep -Milliseconds $script:TweakActionDelayMs
    return $r
}

function Get-CheckBoxState(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$patterns
) {
    $cbType = [System.Windows.Automation.ControlType]::CheckBox
    $el = Find-ElementByNameMatch $root $patterns @($cbType)
    if (-not $el) { return @{ Status = 'not_found'; Element = $null } }
    try {
        Scroll-ElementIntoView $el | Out-Null
        $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle) {
            $st = $toggle.Current.ToggleState
            if ($st -eq [System.Windows.Automation.ToggleState]::On) {
                return @{ Status = 'already_checked'; Element = $el }
            }
            return @{ Status = 'unchecked'; Element = $el }
        }
    } catch {}
    return @{ Status = 'error'; Element = $el }
}

function Ensure-CheckBoxCheckedOnce(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$patterns
) {
    $state = Get-CheckBoxState $root $patterns
    if ($state.Status -eq 'not_found') { return 'not_found' }
    if ($state.Status -eq 'already_checked') { return 'already_checked' }
    if ($state.Status -eq 'error') { return 'error' }
    $el = $state.Element
    try {
        $enabled = $true
        try { $enabled = $el.Current.IsEnabled } catch {}
        if (-not $enabled) {
            $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
            if ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) {
                return 'already_checked'
            }
            return 'already_checked'
        }
        $toggle = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle) {
            $toggle.Toggle()
            Start-Sleep -Milliseconds 150
            if ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) {
                return 'ok'
            }
            return 'error'
        }
    } catch {
        if (Invoke-Element $el) { return 'ok' }
        return 'error'
    }
    return 'error'
}

function Ensure-TweakChecked(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$patterns,
    [string]$logKey
) {
    $deadline = (Get-Date).AddMilliseconds($script:TweakSearchTimeoutMs)
    $scrolls = 0
    while ((Get-Date) -lt $deadline) {
        $r = Ensure-CheckBoxCheckedOnce $root $patterns
        if ($r -ne 'not_found') {
            Set-LogField $logKey $r
            return $r
        }
        if ($scrolls -lt $script:MaxScrollsPerTweak) {
            if (Invoke-ScrollDown $root) {
                $scrolls++
                Start-Sleep -Milliseconds 350
            } else {
                Start-Sleep -Milliseconds 200
            }
        } else {
            Start-Sleep -Milliseconds 150
        }
    }
    Set-LogField $logKey 'not_found'
    return 'not_found'
}

function Test-ButtonNameForbidden([string]$name, [string[]]$forbidden) {
    if (-not $name) { return $true }
    $u = $name.ToUpperInvariant()
    foreach ($f in $forbidden) {
        if ($u -match $f) { return $true }
    }
    return $false
}

function Click-ButtonByPatterns(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$patterns,
    [string[]]$forbidden
) {
    $btnType = [System.Windows.Automation.ControlType]::Button
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
    foreach ($btn in $all) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            if (Test-ButtonNameForbidden $n $forbidden) { continue }
            foreach ($p in $patterns) {
                if ($n -match $p) {
                    if (Invoke-Element $btn) { return $true }
                }
            }
        } catch {}
    }
    return $false
}

function Click-FirstInstallButton(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$forbidden
) {
    if (-not $root) { return $false }
    $installPatterns = @('^Install$', '^Install Driver$', '^Install Package$', '^Installer$', '^Install\s')
    $btnType = [System.Windows.Automation.ControlType]::Button
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
    foreach ($btn in $all) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            if (Test-ButtonNameForbidden $n $forbidden) { continue }
            $matched = $false
            foreach ($p in $installPatterns) {
                if ($n -match $p) { $matched = $true; break }
            }
            if (-not $matched) { continue }
            Scroll-ElementIntoView $btn | Out-Null
            Start-Sleep -Milliseconds 200
            if (Invoke-Element $btn) { return $true }
        } catch {}
    }
    return $false
}

function Normalize-NvcUiText([string]$text) {
    if (-not $text) { return '' }
    $t = $text.Trim().ToLowerInvariant()
    return ([regex]::Replace($t, '\s+', ' '))
}

function Test-NvcPackageReadyText([string]$blob) {
    if (-not $blob) { return $false }
    if ($blob -match '(?i)PREPARING SOURCE|COPYING INSTALL|BUILDING PACKAGE|PLEASE WAIT|PROCESSING\.\.\.') { return $false }
    if ($blob -match '(?i)your customi[sz]ed installer is now ready') { return $true }
    $norm = Normalize-NvcUiText $blob
    if ($norm -match 'your customi[sz]ed installer is now ready') { return $true }
    return $false
}

function Find-NvcInstallButtonExact(
    [System.Windows.Automation.AutomationElement]$win,
    [string[]]$forbiddenBtn
) {
    if (-not $win) { return $null }
    $btnType = [System.Windows.Automation.ControlType]::Button
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
    foreach ($btn in $all) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            if (Test-ButtonNameForbidden $n $forbiddenBtn) { continue }
            if ($n.Equals('Install', [System.StringComparison]::OrdinalIgnoreCase)) { return $btn }
        } catch {}
    }
    return $null
}

function Invoke-ClickElementScreenCenter([System.Windows.Automation.AutomationElement]$el, [System.Windows.Automation.AutomationElement]$win) {
    if (-not $el -or -not $win) { return $false }
    $name = ''
    try { $name = [string]$el.Current.Name } catch {}
    return (SafeClickElementCenter $el $name $win)
}

function Invoke-NvcInstallKeyboardFallback([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return $false }
    if ($script:SafeClickBlockCoordinateFallbacks) {
        Write-SafeClickBlocked 'clavier Alt+I / Tab+Enter global'
        Write-LiveStatus '[NVCleanstall] Fallback coordonnées désactivé pour sécurité.'
        Write-NvcManualUiRequired 'install_keyboard_fallback'
        return $false
    }
    Set-NvcForeground $win
    Start-Sleep -Milliseconds 300
    if (Send-KeysSequence '%i') {
        Write-LiveStatus '[NVCleanstall] Fallback clavier utilise pour lancer Install.'
        return $true
    }
    foreach ($i in 1..14) {
        Send-KeysSequence '{TAB}'
        Start-Sleep -Milliseconds 120
    }
    Send-KeysSequence '{ENTER}'
    Write-LiveStatus '[NVCleanstall] Fallback clavier utilise pour lancer Install.'
    return $true
}

function Invoke-NvcPackageReadyDownEnter([System.Windows.Automation.AutomationElement]$win) {
    if ($script:hasTriggeredNVCleanstallInstall) { return $true }
    if (-not $win) { return $false }
    try {
        if (-not (Test-NvcWindowTitle ([string]$win.Current.Name))) { return $false }
    } catch {
        return $false
    }
    $blob = Get-TextBlob $win
    if (-not (Test-NvcPackageReadyText $blob)) { return $false }
    Write-LiveStatus '[NVCleanstall] Page finale détectée.'
    Set-NvcForeground $win
    Start-Sleep -Milliseconds 200
    if (-not (Send-KeysToNvcWindow $win '{DOWN}')) { return $false }
    Start-Sleep -Milliseconds 100
    if (-not (Send-KeysToNvcWindow $win '{ENTER}')) { return $false }
    $script:hasTriggeredNVCleanstallInstall = $true
    $script:isNVCleanstallAutomationRunning = $false
    Set-LogField 'INSTALL_SEQUENCE' 'down_enter'
    Set-LogField 'INSTALL_KEYS_SENT' 'oui'
    Set-LogField 'PACKAGE_READY_INSTALL_TRIGGERED' 'oui'
    Write-LiveStatus '[NVCleanstall] Flèche bas + Entrée envoyé pour lancer Install.'
    Write-LiveStatus '[NVCleanstall] Installation lancée.'
    return $true
}

function Invoke-NvcPackageReadyDetectionAndInstall([int]$timeoutSec) {
    $script:hasTriggeredNVCleanstallInstall = $false
    Write-LiveStatus 'Détection page prête NVCleanstall...'
    Set-LogField 'NV_PROGRESS_PCT' '75'
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline -and -not $script:hasTriggeredNVCleanstallInstall) {
        $win = Get-NvcRootWindow
        if ($win) {
            $blob = Get-TextBlob $win
            if (Test-NvcPackageReadyText $blob) {
                Set-LogField 'PACKAGE_READY_DETECTED' 'oui'
                if (Invoke-NvcPackageReadyDownEnter $win) {
                    break
                }
            }
        }
        Start-Sleep -Milliseconds $script:WorkflowPollMs
    }
    if (-not $script:hasTriggeredNVCleanstallInstall) {
        Set-LogField 'RESULT' 'package_ready_timeout'
        return $false
    }
    Write-TimingLog 'Action suivante immédiate' -1
    Write-LiveStatus 'Lancement du programme d installation NVIDIA...'
    Set-LogField 'NV_PROGRESS_PCT' '80'
    Write-LiveStatus 'En attente installateur NVIDIA...'
    if (Test-NvidiaInstallerOpened 10) {
        Set-LogField 'NVIDIA_INSTALLER_FOUND' 'oui'
        Set-LogField 'INSTALL_LAUNCHED' 'oui'
        Set-LogField 'RESULT' 'install_launched'
        return $true
    }
    Set-LogField 'NVIDIA_INSTALLER_FOUND' 'non'
    Set-LogField 'RESULT' 'install_launch_pending'
    return $true
}

function Invoke-NvcClickInstallButton(
    [System.Windows.Automation.AutomationElement]$win,
    [string[]]$forbiddenBtn
) {
    if (-not $win) { return $false }
    $exact = Find-NvcInstallButtonExact $win $forbiddenBtn
    if ($exact) {
        Set-NvcForeground $win
        Scroll-ElementIntoView $exact | Out-Null
        Start-Sleep -Milliseconds 200
        if (Invoke-Element $exact) { return $true }
        if (Invoke-ClickElementScreenCenter $exact $win) { return $true }
    }
    Set-NvcForeground $win
    $installPatterns = @('Install', 'Installer', 'Install Driver', 'Install Package')
    $btnType = [System.Windows.Automation.ControlType]::Button
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
    foreach ($btn in $all) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            if (Test-ButtonNameForbidden $n $forbiddenBtn) { continue }
            $isInstall = $false
            foreach ($p in $installPatterns) {
                if ($n.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $isInstall = $true
                    break
                }
            }
            if (-not $isInstall) { continue }
            Set-LogField 'INSTALL_BUTTON_FOUND' 'oui'
            Scroll-ElementIntoView $btn | Out-Null
            Start-Sleep -Milliseconds 300
            if (Invoke-Element $btn) {
                Set-LogField 'INSTALL_BUTTON_CLICKED' 'oui'
                Set-LogField 'INSTALL_CLICKED' 'oui'
                return $true
            }
        } catch {}
    }
    if (Click-FirstInstallButton $win $forbiddenBtn) {
        Set-LogField 'INSTALL_BUTTON_FOUND' 'oui'
        Set-LogField 'INSTALL_BUTTON_CLICKED' 'oui'
        Set-LogField 'INSTALL_CLICKED' 'oui'
        return $true
    }
    Write-NvcManualUiRequired 'install_button'
    return $false
}

function Ensure-RadioSelected(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$patterns
) {
    $rbType = [System.Windows.Automation.ControlType]::RadioButton
    $el = Find-ElementByNameMatch $root $patterns @($rbType)
    if (-not $el) {
        $el = Find-ElementByNameMatch $root $patterns @(
            [System.Windows.Automation.ControlType]::ListItem
        )
    }
    if (-not $el) { return 'not_found' }
    try {
        $sel = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sel) {
            if ($sel.Current.IsSelected) { return 'already_checked' }
            $sel.Select()
            Start-Sleep -Milliseconds 250
            return 'ok'
        }
    } catch {}
    try {
        if (Invoke-Element $el) { return 'ok' }
    } catch {}
    return 'error'
}

function Test-ForbiddenVisible([string]$blob) {
    if ($blob -match 'RESTART|REDEMARR|SHUTDOWN|ÉTEINDRE|REBOOT') { return $true }
    return $false
}

function Send-KeysSequence([string]$keys) {
    try {
        $ws = New-Object -ComObject WScript.Shell
        Start-Sleep -Milliseconds 250
        $ws.SendKeys($keys)
        Start-Sleep -Milliseconds 200
        return $true
    } catch {
        return $false
    }
}

function Test-NvcWindowTitle([string]$title) {
    if (-not $title) { return $false }
    return ($title -match '(?i)NVCleanstall|NVCleanInstall|TechPowerUp')
}

function Assert-NvcWindowForeground([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return $false }
    try {
        $fgTitle = Get-ForegroundWindowTitle
        if (Test-NvcWindowTitle $fgTitle) { return $true }
        $expected = [string]$win.Current.Name
        if ($fgTitle -and $expected -and ($fgTitle -eq $expected)) { return $true }
    } catch {}
    Write-LiveStatus '[Automation] Action bloquée : mauvaise fenêtre active.'
    Set-NvcForeground $win
    Start-Sleep -Milliseconds 200
    return $false
}

function Send-KeysToNvcWindow([System.Windows.Automation.AutomationElement]$win, [string]$keys) {
    if (-not $win) { return $false }
    if (-not (Assert-NvcWindowForeground $win)) {
        Set-NvcForeground $win
        Start-Sleep -Milliseconds 250
        if (-not (Assert-NvcWindowForeground $win)) { return $false }
    }
    return (Send-KeysSequence $keys)
}

function Invoke-NvcFinishedFocusClick([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return $false }
    if ($script:SafeClickBlockCoordinateFallbacks) {
        Write-SafeClickBlocked 'focus Finished 0.10 x 0.30/0.26'
        Write-LiveStatus '[NVCleanstall] Fallback coordonnées désactivé pour sécurité.'
        return $false
    }
    return $false
}

function Invoke-NvcFinishedInstallKeys([System.Windows.Automation.AutomationElement]$win, [string]$method) {
    if (-not $win) { return $false }
    if ($script:SafeClickBlockCoordinateFallbacks) {
        Write-SafeClickBlocked 'SendKeys Down+Enter (sans garde-fou strict)'
        Write-LiveStatus '[NVCleanstall] Fallback coordonnées désactivé pour sécurité.'
        Write-NvcManualUiRequired 'finished_down_enter'
        return $false
    }
    Write-LiveStatus '[NVCleanInstall] Activation fenetre NVCleanstall'
    Set-NvcForeground $win
    Start-Sleep -Milliseconds 300
    Set-LogField 'INSTALL_METHOD' $method
    Set-LogField 'INSTALL_SEQUENCE' 'down_enter'
    Write-LiveStatus '[NVCleanInstall] Envoi Fleche bas'
    if (Send-KeysSequence '{DOWN}') {
        Start-Sleep -Milliseconds 250
        Write-LiveStatus '[NVCleanInstall] Envoi Entree'
        if (Send-KeysSequence '{ENTER}') {
            Write-LiveStatus '[NVCleanInstall] Down + Enter envoye'
            Set-LogField 'INSTALL_KEYS_SENT' 'oui'
            return $true
        }
    }
    Set-LogField 'INSTALL_KEYS_SENT' 'non'
    return $false
}

function Test-NvidiaInstallerOpened([int]$waitSec) {
    $w = Wait-NvidiaInstallerWindow $waitSec
    return ($null -ne $w)
}

function Invoke-NvcFinishedInstallAllMethods([System.Windows.Automation.AutomationElement]$win, [string[]]$forbiddenBtn) {
    if (-not $win) { return $false }
    foreach ($method in @('SendEvent', 'SendInput', 'ControlSend')) {
        $w = Get-NvcRootWindow
        if (-not $w) { $w = $win }
        if (-not (Test-NvcFinishedPage $w)) { break }
        if (Invoke-NvcFinishedInstallKeys $w $method) {
            Write-LiveStatus 'Lancement du programme d installation NVIDIA...'
            Set-LogField 'NV_PROGRESS_PCT' '80'
            if (Test-NvidiaInstallerOpened 10) {
                Set-LogField 'INSTALL_LAUNCH_OK' $method
                return $true
            }
            Set-LogField ('INSTALL_METHOD_FAILED_' + $method) 'oui'
        }
        Start-Sleep -Milliseconds 400
    }
    $w = Get-NvcRootWindow
    if ($w -and (Test-NvcFinishedPage $w)) {
        Set-LogField 'INSTALL_RETRY' 'down_down_enter_once'
        if (Invoke-NvcFinishedInstallKeys $w 'SendEvent') {
            Write-LiveStatus 'Lancement du programme d installation NVIDIA...'
            Set-LogField 'NV_PROGRESS_PCT' '80'
            if (Test-NvidiaInstallerOpened 10) {
                Set-LogField 'INSTALL_LAUNCH_OK' 'retry_sendevent'
                return $true
            }
        }
    }
    $w = Get-NvcRootWindow
    if ($w -and (Test-NvcFinishedPage $w)) {
        Set-LogField 'INSTALL_METHOD' 'uia_install_button'
        if (Invoke-NvcClickInstallButton $w $forbiddenBtn) {
            Write-LiveStatus 'Lancement du programme d installation NVIDIA...'
            Set-LogField 'NV_PROGRESS_PCT' '80'
            if (Test-NvidiaInstallerOpened 10) {
                Set-LogField 'INSTALL_LAUNCH_OK' 'uia_install_button'
                return $true
            }
        }
    }
    return $false
}

function Test-NvcFinishedPage([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return $false }
    return (Test-NvcPackageReadyText (Get-TextBlob $win))
}

function Test-NvidiaInstallerSetupWindowTitle([string]$title) {
    if (-not $title) { return $false }
    if ($title -match '(?i)Panneau de configuration|Control Panel|NVIDIA Control Panel|Centre de configuration') { return $false }
    return (Test-NvidiaInstallerProgrammeWindowTitle $title)
}

function Test-NvidiaInstallerWindowMatch([System.Windows.Automation.AutomationElement]$w) {
    if (-not $w) { return $false }
    try {
        $n = [string]$w.Current.Name
        return (Test-NvidiaInstallerSetupWindowTitle $n)
    } catch {}
    return $false
}

function Get-NvidiaInstallerWindow {
    if ((Ensure-NvidiaWin32MsaaType) -and (Test-NvidiaWin32MsaaTypeLoaded)) {
        try {
            $rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
            if ($rootHwnd -ne [IntPtr]::Zero) {
                $fromHwnd = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd)
                if ($fromHwnd -and (Test-NvidiaInstallerWindowMatch $fromHwnd)) {
                    return $fromHwnd
                }
            }
        } catch {}
    }
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($w in $all) {
            if (Test-NvidiaInstallerWindowMatch $w) { return $w }
        }
    } catch {}
    return $null
}

function Get-ForegroundWindowTitle {
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class NvcFgWin {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@ -ErrorAction SilentlyContinue | Out-Null
        $hwnd = [NvcFgWin]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return '' }
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
        if ($el) { return [string]$el.Current.Name }
    } catch {}
    return ''
}

function Test-NvidiaInstallerIsActiveForeground([System.Windows.Automation.AutomationElement]$nvWin) {
    if (-not $nvWin) { return $false }
    try {
        $fgTitle = Get-ForegroundWindowTitle
        if (Test-NvidiaInstallerSetupWindowTitle $fgTitle) { return $true }
        $expected = [string]$nvWin.Current.Name
        if ($fgTitle -and $expected -and ($fgTitle -eq $expected)) { return $true }
    } catch {}
    return $false
}

function Assert-NvidiaInstallerForeground([System.Windows.Automation.AutomationElement]$nvWin) {
    if (-not $nvWin) { return $false }
    Set-NvcForeground $nvWin
    Start-Sleep -Milliseconds 200
    return $true
}

function Write-NvidiaInstallerClickFailed {
    Write-LiveStatus '[NVIDIA Installer] Clic impossible, vérifier que Unreal est lancé en administrateur.'
}

function Test-NvidiaInstallOptionsPage([string]$blob) {
    if (-not $blob) { return $false }
    if (Test-NvidiaCustomInstallOptionsPage $blob) { return $false }
    $hasOptionsTitle = ($blob -match "(?i)Options d'installation|Options d installation")
    $hasExpress = ($blob -match '(?i)\bExpress\b')
    $hasCustom = ($blob -match '(?i)Personnalis|\bCustom\b')
    if ($hasOptionsTitle -and $hasExpress -and $hasCustom) { return $true }
    if ($hasExpress -and $hasCustom) { return $true }
    return $false
}

function Test-NvidiaInstallOptionsPageByControls([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return $false }
    if (Test-NvidiaCustomInstallOptionsPage (Get-TextBlob $root)) { return $false }
    $express = Find-NvidiaExpressRadio $root
    if (-not $express) { return $false }
    $customPatterns = @(
        'Personnalisée (avancée)', 'Personnalisee (avancee)',
        'Personnalisée', 'Personnalisee', 'Custom (Advanced)', 'Custom'
    )
    $custom = Find-NvidiaRadioNearTextOnSameRow $root $customPatterns
    if (-not $custom) { $custom = Find-NvidiaCustomAdvancedRadio $root }
    return ($null -ne $custom)
}

function Test-NvidiaInstallOptionsPageDetected(
    [System.Windows.Automation.AutomationElement]$nvWin,
    [string]$blob
) {
    if (Test-NvidiaInstallOptionsPage $blob) { return $true }
    if (Test-NvidiaInstallOptionsPageByControls $nvWin) { return $true }
    return $false
}

function Test-NvidiaCustomInstallOptionsPage([string]$blob) {
    if (-not $blob) { return $false }
    if ($blob -match "(?i)Options d'installation personnalisée|Options d installation personnalisée") { return $true }
    if ($blob -match '(?i)Sélectionnez les composants du pilote|Selectionnez les composants du pilote') { return $true }
    return $false
}

function Test-NvidiaInstallerProgrammeWindowTitle([string]$title) {
    if (-not $title) { return $false }
    if ($title -match '(?i)^NVIDIA Installer$|^NVIDIA Installer ') { return $true }
    return ($title -match '(?i)Programme d''installation NVIDIA|Programme d installation NVIDIA')
}

function Get-NvidiaInstallerNativeHwnd([System.Windows.Automation.AutomationElement]$nvWin) {
    if (-not $nvWin) { return [IntPtr]::Zero }
    try {
        return [IntPtr][int]$nvWin.Current.NativeWindowHandle
    } catch {
        return [IntPtr]::Zero
    }
}

function Test-NvidiaInstallerForegroundHwnd([System.Windows.Automation.AutomationElement]$nvWin) {
    $expected = Get-NvidiaInstallerNativeHwnd $nvWin
    if ($expected -eq [IntPtr]::Zero) { return $false }
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NvcFgWinCheck {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@ -ErrorAction SilentlyContinue | Out-Null
        $fg = [NvcFgWinCheck]::GetForegroundWindow()
        return ($fg -eq $expected)
    } catch {
        return $false
    }
}

function Set-UiaElementFocus([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    try {
        $el.SetFocus()
        return $true
    } catch {
        try {
            $hwnd = [IntPtr][int]$el.Current.NativeWindowHandle
            if ($hwnd -ne [IntPtr]::Zero) {
                Add-Type @"
using System.Runtime.InteropServices;
public class NvcSetFocusWin {
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(System.IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue | Out-Null
                [void][NvcSetFocusWin]::SetFocus($hwnd)
                return $true
            }
        } catch {}
    }
    return $false
}

function Find-NvidiaOptionsPageContainer([System.Windows.Automation.AutomationElement]$nvWin) {
    if (-not $nvWin) { return $null }
    $types = @(
        [System.Windows.Automation.ControlType]::Pane,
        [System.Windows.Automation.ControlType]::Group,
        [System.Windows.Automation.ControlType]::Window,
        [System.Windows.Automation.ControlType]::Custom
    )
    return (Find-NvidiaElementByNameContains $nvWin $types @(
        "Options d'installation", 'Options d installation', 'Installation Options', 'Setup Options'
    ))
}

function Find-NvidiaInstallerWindow {
    return Get-NvidiaInstallerWindow
}

function Format-NvidiaUiRect([System.Windows.Rect]$rect) {
    if ($rect.Width -le 0 -and $rect.Height -le 0) { return 'Rect=empty' }
    return ('Rect=L{0:F0},T{1:F0},W{2:F0},H{3:F0}' -f $rect.X, $rect.Y, $rect.Width, $rect.Height)
}

function Write-NvidiaInstallerUiDump([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return }
    Write-LiveStatus '[NVIDIA Installer] Dump UIA fenêtre NVIDIA...'
    $interesting = @(
        [System.Windows.Automation.ControlType]::Button,
        [System.Windows.Automation.ControlType]::RadioButton,
        [System.Windows.Automation.ControlType]::Text,
        [System.Windows.Automation.ControlType]::CheckBox
    )
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        $count = 0
        foreach ($el in $all) {
            if ($count -ge 120) { break }
            try {
                $ct = $el.Current.ControlType
                if ($interesting -notcontains $ct) { continue }
                $n = [string]$el.Current.Name
                $aid = ''
                try { $aid = [string]$el.Current.AutomationId } catch {}
                if (-not $n -and -not $aid) { continue }
                $en = 'enabled'
                try { if (-not $el.Current.IsEnabled) { $en = 'disabled' } } catch {}
                $sel = ''
                try {
                    $sp = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                    if ($sp) { $sel = ' IsSelected=' + $sp.Current.IsSelected }
                } catch {}
                $rectStr = Format-NvidiaUiRect $el.Current.BoundingRectangle
                $line = "[NVIDIA Installer UIA Dump] $($ct.ProgrammaticName) | Name='$n' | AutomationId='$aid' | $en$sel | $rectStr"
                Write-LiveStatus $line
                $count++
            } catch {}
        }
    } catch {}
}

function Find-NvidiaElementByNameContains(
    [System.Windows.Automation.AutomationElement]$root,
    [System.Windows.Automation.ControlType[]]$controlTypes,
    [string[]]$texts
) {
    if (-not $root -or -not $texts) { return $null }
    $bestEl = $null
    $bestScore = 0
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                $ct = $el.Current.ControlType
                if ($controlTypes -and ($controlTypes -notcontains $ct)) { continue }
                $n = [string]$el.Current.Name
                if (-not $n) { continue }
                foreach ($t in $texts) {
                    if (-not $t) { continue }
                    if ($n.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        if ($t.Length -gt $bestScore) {
                            $bestEl = $el
                            $bestScore = $t.Length
                        }
                    }
                }
            } catch {}
        }
    } catch {}
    return $bestEl
}

function Click-ElementCenter(
    [System.Windows.Automation.AutomationElement]$element,
    [System.Windows.Automation.AutomationElement]$ownerWindow
) {
    if (-not $element) { return $false }
    if (-not $ownerWindow) { $ownerWindow = $element }
    return (Invoke-ClickElementScreenCenter $element $ownerWindow)
}

function TryInvokeOrClickCenter(
    [System.Windows.Automation.AutomationElement]$element,
    [System.Windows.Automation.AutomationElement]$ownerWindow
) {
    if (-not $element) { return $false }
    Scroll-ElementIntoView $element | Out-Null
    Start-Sleep -Milliseconds 100
    $name = ''
    try { $name = [string]$element.Current.Name } catch {}
    if (SafeInvokeElement $element $name) { return $true }
    return (SafeClickElementCenter $element $name $ownerWindow)
}

function Test-NvidiaRadioIsSelected([System.Windows.Automation.AutomationElement]$radio) {
    if (-not $radio) { return $false }
    try {
        $sp = $radio.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sp) { return [bool]$sp.Current.IsSelected }
    } catch {}
    try {
        $tp = $radio.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($tp) { return ($tp.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) }
    } catch {}
    return $false
}

function TrySelectRadio([System.Windows.Automation.AutomationElement]$radio) {
    if (-not $radio) { return $false }
    if (Test-NvidiaRadioIsSelected $radio) { return $true }
    $name = ''
    try { $name = [string]$radio.Current.Name } catch {}
    if (SafeSelectRadio $radio $name) { return $true }
    return $false
}

function Click-LeftOfElementRow(
    [System.Windows.Automation.AutomationElement]$labelElement,
    [System.Windows.Automation.AutomationElement]$ownerWindow,
    [int]$offsetLeft
) {
    Write-BlockedUnsafeClick "Click-LeftOfElementRow offset fixe $offsetLeft"
    return $false
}

function Find-NvidiaInstallerButtonByNameContains(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$nameParts,
    [string[]]$forbidden
) {
    $btnType = [System.Windows.Automation.ControlType]::Button
    $best = $null
    $bestScore = 0
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
        foreach ($btn in $all) {
            try {
                $n = [string]$btn.Current.Name
                if (-not $n) { continue }
                if (Test-ButtonNameForbidden $n $forbidden) { continue }
                foreach ($part in $nameParts) {
                    if (-not $part) { continue }
                    if ($n.IndexOf($part, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        if ($part.Length -gt $bestScore) {
                            $best = $btn
                            $bestScore = $part.Length
                        }
                    }
                }
            } catch {}
        }
    } catch {}
    return $best
}

function Find-NvidiaCustomAdvancedRadio([System.Windows.Automation.AutomationElement]$root) {
    $rbType = [System.Windows.Automation.ControlType]::RadioButton
    return (Find-NvidiaElementByNameContains $root @($rbType) @(
        'Personnalisée (avancée)', 'Personnalisee (avancee)',
        'Custom (Advanced)', 'Personnalisée', 'Personnalisee', 'Custom'
    ))
}

function Find-NvidiaExpressRadio([System.Windows.Automation.AutomationElement]$root) {
    $rbType = [System.Windows.Automation.ControlType]::RadioButton
    return (Find-NvidiaElementByNameContains $root @($rbType) @('Express', 'EXPRESS'))
}

function Find-NvidiaRadioNearTextOnSameRow(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$textPatterns
) {
    if (-not $root -or -not $textPatterns) { return $null }
    $textTypes = @(
        [System.Windows.Automation.ControlType]::Text,
        [System.Windows.Automation.ControlType]::Label
    )
    $label = Find-NvidiaElementByNameContains $root $textTypes $textPatterns
    if (-not $label) { return $null }
    try {
        $lr = $label.Current.BoundingRectangle
        if ($lr.Width -le 0 -or $lr.Height -le 0) { return $null }
        $midY = $lr.Y + ($lr.Height / 2)
        $tolY = [Math]::Max(14, $lr.Height * 0.75)
        $rbType = [System.Windows.Automation.ControlType]::RadioButton
        $best = $null
        $bestScore = [double]::MaxValue
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                if ($el.Current.ControlType -ne $rbType) { continue }
                $n = [string]$el.Current.Name
                $matchName = $false
                foreach ($p in @('Personnalis', 'Custom', 'Advanced')) {
                    if ($n -and $n.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $matchName = $true
                        break
                    }
                }
                if (-not $matchName -and -not $n) { continue }
                $rr = $el.Current.BoundingRectangle
                if ($rr.Width -le 0 -or $rr.Height -le 0) { continue }
                $ry = $rr.Y + ($rr.Height / 2)
                if ([Math]::Abs($ry - $midY) -gt $tolY) { continue }
                if ($rr.X -gt ($lr.Right + 48)) { continue }
                $score = [Math]::Abs($rr.X - $lr.X) + ([Math]::Abs($ry - $midY) * 2)
                if ($score -lt $bestScore) {
                    $best = $el
                    $bestScore = $score
                }
            } catch {}
        }
        return $best
    } catch {
        return $null
    }
}

function Select-NvidiaCustomAdvancedOption([System.Windows.Automation.AutomationElement]$nvWin) {
    $namePatterns = @(
        'Personnalisée (avancée)', 'Personnalisee (avancee)',
        'Personnalisée', 'Personnalisee', 'Custom', 'Advanced'
    )
    $radio = Find-NvidiaCustomAdvancedRadio $nvWin
    if (-not $radio) {
        $radio = Find-NvidiaRadioNearTextOnSameRow $nvWin $namePatterns
        if ($radio) {
            Write-LiveStatus '[NVIDIA Installer] Radio Personnalisée trouvé près du texte (même ligne).'
        }
    } else {
        Write-LiveStatus '[NVIDIA Installer] Radio Personnalisée trouvé via UIA.'
    }

    if ($radio) {
        if (TrySelectRadio $radio) {
            Start-Sleep -Milliseconds 300
            if (Test-NvidiaRadioIsSelected $radio) { return $true }
        }
        if (TryInvokeOrClickCenter $radio $nvWin) {
            Start-Sleep -Milliseconds 300
            if (Test-NvidiaRadioIsSelected $radio) { return $true }
        }
        $radio2 = Find-NvidiaCustomAdvancedRadio $nvWin
        if (-not $radio2) { $radio2 = Find-NvidiaRadioNearTextOnSameRow $nvWin $namePatterns }
        if ($radio2 -and (Test-NvidiaRadioIsSelected $radio2)) { return $true }
    }

    return $false
}

function Get-NvidiaCustomInstallLabelPatterns {
    return @(
        'Personnalisée (avancée)', 'Personnalisee (avancee)',
        'Personnalisée', 'Personnalisee', 'Custom (Advanced)', 'Custom'
    )
}

function Test-NvidiaCustomLabelName([string]$name) {
    if (-not $name) { return $false }
    if ($name -match '(?i)Personnalisée \(avancée\)|Personnalisee \(avancee\)') { return $true }
    if ($name -match '(?i)Custom \(Advanced\)') { return $true }
    if ($name -match '(?i)Personnalisée|Personnalisee') { return $true }
    if ($name -match '(?i)\bCustom\b' -and $name -match '(?i)Advanced|Personnalis|avanc') { return $true }
    return $false
}

function Test-NvidiaInstallOptionsPageHasExpress(
    [System.Windows.Automation.AutomationElement]$nvWin,
    [string]$blob
) {
    if ($blob -and $blob -match '(?i)\bExpress\b|\bExpresse\b') { return $true }
    if (Find-NvidiaExpressRadio $nvWin) { return $true }
    return $false
}

function Find-NvidiaCustomInstallLabelElement([System.Windows.Automation.AutomationElement]$nvWin) {
    if (-not $nvWin) { return $null }
    $allowedTypes = @(
        [System.Windows.Automation.ControlType]::Text,
        [System.Windows.Automation.ControlType]::RadioButton,
        [System.Windows.Automation.ControlType]::Button,
        [System.Windows.Automation.ControlType]::Pane,
        [System.Windows.Automation.ControlType]::Group,
        [System.Windows.Automation.ControlType]::ListItem
    )
    $typeRank = @{
        ([System.Windows.Automation.ControlType]::Text) = 5
        ([System.Windows.Automation.ControlType]::RadioButton) = 4
        ([System.Windows.Automation.ControlType]::Button) = 3
        ([System.Windows.Automation.ControlType]::ListItem) = 2
        ([System.Windows.Automation.ControlType]::Group) = 1
        ([System.Windows.Automation.ControlType]::Pane) = 0
    }
    $patterns = Get-NvidiaCustomInstallLabelPatterns
    $best = $null
    $bestScore = -1
    try {
        $all = $nvWin.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                if (-not $el.Current.IsEnabled) { continue }
                $ct = $el.Current.ControlType
                if ($allowedTypes -notcontains $ct) { continue }
                $n = [string]$el.Current.Name
                if (-not (Test-NvidiaCustomLabelName $n)) { continue }
                $matchLen = 0
                foreach ($p in $patterns) {
                    if ($n.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        if ($p.Length -gt $matchLen) { $matchLen = $p.Length }
                    }
                }
                if ($matchLen -le 0) { continue }
                $r = $el.Current.BoundingRectangle
                if ($r.Width -le 2 -or $r.Height -le 2) { continue }
                $rank = 0
                if ($typeRank.ContainsKey($ct)) { $rank = $typeRank[$ct] }
                $score = ($matchLen * 10) + $rank
                if ($score -gt $bestScore) {
                    $best = $el
                    $bestScore = $score
                }
            } catch {}
        }
    } catch {}
    return $best
}

function Write-NvidiaInstallerOptionsPageDump([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return }
    Write-LiveStatus '[UIA-DUMP] NVIDIA installer Options page — éléments Express/Personnalisée/Suivant'
    $keywords = @('Express', 'Personnalis', 'Personnalise', 'avanc', 'avance', 'Custom', 'Advanced', 'Suivant', 'Next', 'SUIVANT')
    $interesting = @(
        [System.Windows.Automation.ControlType]::Button,
        [System.Windows.Automation.ControlType]::RadioButton,
        [System.Windows.Automation.ControlType]::Text,
        [System.Windows.Automation.ControlType]::Pane,
        [System.Windows.Automation.ControlType]::Group,
        [System.Windows.Automation.ControlType]::ListItem
    )
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        $count = 0
        foreach ($el in $all) {
            if ($count -ge 80) { break }
            try {
                $ct = $el.Current.ControlType
                if ($interesting -notcontains $ct) { continue }
                $n = [string]$el.Current.Name
                $aid = ''
                try { $aid = [string]$el.Current.AutomationId } catch {}
                $hay = ($n + ' ' + $aid)
                $hit = $false
                foreach ($kw in $keywords) {
                    if ($hay.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $hit = $true
                        break
                    }
                }
                if (-not $hit) { continue }
                $en = 'enabled'
                try { if (-not $el.Current.IsEnabled) { $en = 'disabled' } } catch {}
                $sel = ''
                try {
                    $sp = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                    if ($sp) { $sel = ' IsSelected=' + $sp.Current.IsSelected }
                } catch {}
                $rectStr = Format-NvidiaUiRect $el.Current.BoundingRectangle
                Write-LiveStatus "[UIA-DUMP] $($ct.ProgrammaticName) Name='$n' AutomationId='$aid' $en$sel $rectStr"
                $count++
            } catch {}
        }
    } catch {}
    Write-UiaDumpForElement $root 'NVIDIA installer Options page custom selection failed'
}

function Invoke-NvidiaCustomLabelClick(
    [System.Windows.Automation.AutomationElement]$nvWin,
    [ref]$outRadio
) {
    if (-not $nvWin) { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$nvWin.Current.Name))) { return $false }

    $blob = Get-TextBlob $nvWin
    if (-not (Test-NvidiaInstallOptionsPageDetected $nvWin $blob)) { return $false }
    if (-not (Test-NvidiaInstallOptionsPageHasExpress $nvWin $blob)) { return $false }

    $label = Find-NvidiaCustomInstallLabelElement $nvWin
    if (-not $label) { return $false }

    $labelName = ''
    try { $labelName = [string]$label.Current.Name } catch {}
    if (-not $labelName) { $labelName = 'Personnalisée (avancée)' }

    Scroll-ElementIntoView $label | Out-Null
    Start-Sleep -Milliseconds 120

    if (-not (SafeClickElementCenter $label $labelName $nvWin)) { return $false }

    $rectStr = Format-NvidiaUiRect $label.Current.BoundingRectangle
    Write-LiveStatus "[SAFE-UIA-RECT] Clicked custom install label text: Name='$labelName' $rectStr"

    Start-Sleep -Milliseconds 300

    $customPatterns = Get-NvidiaCustomInstallLabelPatterns
    $radio = Find-NvidiaRadioNearTextOnSameRow $nvWin $customPatterns
    if (-not $radio) { $radio = Find-NvidiaCustomAdvancedRadio $nvWin }
    if ($outRadio) { $outRadio.Value = $radio }

    if ($radio -and (Test-NvidiaCustomInstallSelected $nvWin $radio)) { return $true }

    $express = Find-NvidiaExpressRadio $nvWin
    if ($express -and (Test-NvidiaRadioIsSelected $express)) { return $false }

    $blob2 = Get-TextBlob $nvWin
    if (Test-NvidiaInstallOptionsPageDetected $nvWin $blob2) { return $true }

    return $false
}

function Test-NvidiaInstallOptionsPageExactTitle([string]$blob) {
    if (-not $blob) { return $false }
    if (Test-NvidiaCustomInstallOptionsPage $blob) { return $false }
    return ($blob -match "(?i)Options d'installation|Options d installation")
}

function Test-NvidiaInstallOptionsHasCustomText([string]$blob) {
    if (-not $blob) { return $false }
    return ($blob -match '(?i)Personnalis|\bCustom\b')
}

function Test-NvidiaNoOtherInstallerScreenActive(
    [string]$blob,
    [System.Windows.Automation.AutomationElement]$nvWin
) {
    if (Test-NvidiaLicensePage $blob) { return $false }
    if (Test-NvidiaCustomInstallOptionsPage $blob) { return $false }
    if (Test-NvidiaInstallerInstallingPage $blob) { return $false }
    $pageKey = Get-NvidiaInstallerPageKey $blob $nvWin
    return ($pageKey -eq 'options')
}

function Test-NvidiaMsaaCustomName([string]$name) {
    if (-not $name) { return $false }
    if ($name -match '(?i)Personnalis|Personnalise|avancée|avancee|\bCustom\b|Advanced') { return $true }
    return $false
}

$script:NvidiaWin32MsaaLoadFailed = $false

function Test-NvidiaWin32MsaaTypeLoaded {
    try {
        return ($null -ne [Type]::GetType('NvidiaWin32Msaa'))
    } catch {
        return $false
    }
}

function Ensure-NvidiaWin32MsaaType {
    if (Test-NvidiaWin32MsaaTypeLoaded) { return $true }
    if ($script:NvidiaWin32MsaaLoadFailed) { return $false }
    $helperCs = Join-Path $PSScriptRoot 'NvidiaWin32Msaa-helper.cs'
    if (-not (Test-Path -LiteralPath $helperCs)) {
        $script:NvidiaWin32MsaaLoadFailed = $true
        Write-LiveStatus '[NVIDIA-INSTALLER] MSAA/Win32 helper file missing — MSAA/Win32 disabled'
        return $false
    }
    try {
        Add-Type -Path $helperCs -ErrorAction Stop | Out-Null
    } catch {
        $script:NvidiaWin32MsaaLoadFailed = $true
        Write-LiveStatus '[NVIDIA-INSTALLER] MSAA/Win32 helper compile failed — MSAA/Win32 disabled'
        return $false
    }
    return (Test-NvidiaWin32MsaaTypeLoaded)
}

function Test-NvidiaLicensePage([string]$blob) {
    if (-not $blob) { return $false }
    return ($blob -match '(?i)Contrat de licence|License Agreement|NVIDIA Driver License Agreement')
}

function Test-NvidiaInstallerLicenseWin32PageReady(
    [IntPtr]$rootHwnd,
    [System.Windows.Automation.AutomationElement]$nvWin = $null
) {
    if ($rootHwnd -eq [IntPtr]::Zero) { return $false }
    if (-not (Ensure-NvidiaWin32MsaaType)) { return $false }
    if (-not (Test-NvidiaWin32MsaaTypeLoaded)) { return $false }

    $rootTitle = [NvidiaWin32Msaa]::GetWndText($rootHwnd)
    if ($rootTitle -match '(?i)NVCleanstall|NVCleanInstall|TechPowerUp') { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle $rootTitle)) { return $false }

    if (-not $nvWin) {
        try { $nvWin = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd) } catch {}
    }
    if (-not $nvWin) { return $false }

    $blob = Get-TextBlob $nvWin
    if (-not (Test-NvidiaLicensePage $blob)) { return $false }

    $acceptInfo = [NvidiaWin32Msaa]::FindLicenseAcceptButton($rootHwnd)
    if ($acceptInfo -and $acceptInfo.Visible -and $acceptInfo.Enabled) { return $true }
    return $false
}

function Get-NvidiaInstallerLicenseDumpPath {
    if ($LogPath) {
        return (Join-Path (Split-Path -Parent $LogPath) 'nvidia-installer-license-win32-dump.txt')
    }
    $root = Split-Path -Parent $PSScriptRoot
    $logsDir = Join-Path $root 'logs'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        try { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null } catch {}
    }
    return (Join-Path $logsDir 'nvidia-installer-license-win32-dump.txt')
}

function Write-NvidiaInstallerLicenseWin32HandlesDump([IntPtr]$rootHwnd) {
    if ($rootHwnd -eq [IntPtr]::Zero) { return }
    if (-not (Ensure-NvidiaWin32MsaaType)) { return }
    $path = Get-NvidiaInstallerLicenseDumpPath
    $highlightKw = @('Accepter', 'Continuer', 'Accept', 'Continue', 'Licence', 'License')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    $lines.Add('ROOT_CLASS=' + [NvidiaWin32Msaa]::GetWndClass($rootHwnd)) | Out-Null
    $lines.Add('--- CHILDREN ---') | Out-Null
    $highlights = New-Object System.Collections.Generic.List[string]
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        $rect = "L$($c.Rect.Left),T$($c.Rect.Top),R$($c.Rect.Right),B$($c.Rect.Bottom)"
        $lines.Add(
            "HWND=$($c.Hwnd.ToInt64()) | class='$($c.ClassName)' | text='$($c.Text)' | id=$($c.ControlId) | visible=$($c.Visible) | enabled=$($c.Enabled) | rect=$rect | style=$($c.Style) | exStyle=$($c.ExStyle) | parent=$($c.ParentHwnd)"
        ) | Out-Null
        $hay = if ($c.Text) { [string]$c.Text } else { '' }
        foreach ($kw in $highlightKw) {
            if ($hay.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $highlights.Add("HWND=$($c.Hwnd.ToInt64()) | text='$($c.Text)' | class='$($c.ClassName)'") | Out-Null
                break
            }
        }
    }
    $lines.Add('--- HIGHLIGHT (Accepter/Continuer/Accept/Continue/Licence/License) ---') | Out-Null
    if ($highlights.Count -eq 0) {
        $lines.Add('(none)') | Out-Null
    } else {
        foreach ($h in $highlights) { $lines.Add($h) | Out-Null }
    }
    try {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Write-LiveStatus "[UIA-DUMP] License Win32 dump written: $path"
    } catch {}
}

function Invoke-NvidiaInstallerLicenseViaWin32Handles(
    [System.Windows.Automation.AutomationElement]$nvWin = $null
) {
    if (-not (Ensure-NvidiaWin32MsaaType)) { return $false }
    if (-not (Test-NvidiaWin32MsaaTypeLoaded)) { return $false }

    $rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
    if ($rootHwnd -eq [IntPtr]::Zero) { return $false }

    if (-not $nvWin) {
        try { $nvWin = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd) } catch {}
    }
    if (-not (Test-NvidiaInstallerLicenseWin32PageReady $rootHwnd $nvWin)) { return $false }

    Write-LiveStatus '[NVIDIA-INSTALLER] License page detected'
    Set-LogField 'NVIDIA_STEP' 'license'

    $acceptInfo = [NvidiaWin32Msaa]::FindLicenseAcceptButton($rootHwnd)

    if (-not $acceptInfo -or -not $acceptInfo.Visible -or -not $acceptInfo.Enabled) {
        Write-NvidiaInstallerLicenseWin32HandlesDump $rootHwnd
        Write-LiveStatus '[NVIDIA-INSTALLER] License accept hwnd not found, manual required'
        Set-LogField 'NVIDIA_LICENSE_ACCEPTED' 'non'
        return $false
    }

    Write-LiveStatus "[SAFE-WIN32] Accept hwnd found: text='$($acceptInfo.Text)' id=$($acceptInfo.ControlId)"
    [NvidiaWin32Msaa]::InvokeControlClick($acceptInfo.Hwnd, $rootHwnd)
    Write-LiveStatus '[SAFE-WIN32] BM_CLICK accept invoked'
    Write-LiveStatus '[SAFE-WIN32] WM_COMMAND BN_CLICKED accept sent'
    Start-Sleep -Milliseconds 500

    if (-not $nvWin) {
        try { $nvWin = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd) } catch {}
    }
    $blobAfter = if ($nvWin) { Get-TextBlob $nvWin } else { '' }
    $licenseGone = -not (Test-NvidiaLicensePage $blobAfter)
    $optionsVisible = $false
    if ($nvWin) {
        $optionsVisible = (Test-NvidiaInstallOptionsPageExactTitle $blobAfter) -or (Test-NvidiaInstallOptionsPageDetected $nvWin $blobAfter)
    }

    if ($licenseGone -or $optionsVisible) {
        Write-LiveStatus '[NVIDIA-INSTALLER] License accepted, waiting for Options page'
        Set-LogField 'NVIDIA_LICENSE_ACCEPTED' 'win32_bm_click'
        return $true
    }

    Write-LiveStatus '[NVIDIA-INSTALLER] License accept sent — page transition not yet confirmed'
    Set-LogField 'NVIDIA_LICENSE_ACCEPTED' 'win32_bm_click_unverified'
    return $true
}

function Test-NvidiaInstallerOptionsWin32PageReady(
    [IntPtr]$rootHwnd,
    [System.Windows.Automation.AutomationElement]$nvWin = $null
) {
    if ($rootHwnd -eq [IntPtr]::Zero) { return $false }
    if (-not (Ensure-NvidiaWin32MsaaType)) { return $false }
    if (-not (Test-NvidiaWin32MsaaTypeLoaded)) { return $false }

    $rootTitle = [NvidiaWin32Msaa]::GetWndText($rootHwnd)
    if ($rootTitle -match '(?i)NVCleanstall|NVCleanInstall|TechPowerUp') { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle $rootTitle)) { return $false }

    if (-not $nvWin) {
        try { $nvWin = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd) } catch {}
    }
    if (-not $nvWin) { return $false }

    $blob = Get-TextBlob $nvWin
    if (-not (Test-NvidiaInstallOptionsPageExactTitle $blob)) { return $false }
    if (-not (Test-NvidiaNoOtherInstallerScreenActive $blob $nvWin)) { return $false }

    $children = [NvidiaWin32Msaa]::EnumChildren($rootHwnd)
    $hasExpress = $false
    $hasCustom = $false
    $hasNext = $false
    foreach ($c in $children) {
        if (-not $c.Visible -or -not $c.Enabled) { continue }
        $t = [string]$c.Text
        if (-not $t) { continue }
        if ($t -match '(?i)&?Expresse|&?Express') { $hasExpress = $true }
        if ($t -match '(?i)&?Personnalis|&?Custom') { $hasCustom = $true }
        if ($t -match '(?i)&?SUIVANT|&?Suivant|&?Next') { $hasNext = $true }
    }
    return ($hasExpress -and $hasCustom -and $hasNext)
}

function Write-NvidiaInstallerOptionsWin32HandlesDump([IntPtr]$rootHwnd) {
    if ($rootHwnd -eq [IntPtr]::Zero) { return }
    if (-not (Ensure-NvidiaWin32MsaaType)) { return }
    $path = if ($LogPath) {
        Join-Path (Split-Path -Parent $LogPath) 'nvidia-installer-options-win32-dump.txt'
    } else {
        Join-Path (Split-Path -Parent $PSScriptRoot) 'logs\nvidia-installer-options-win32-dump.txt'
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        $rect = "L$($c.Rect.Left),T$($c.Rect.Top),R$($c.Rect.Right),B$($c.Rect.Bottom)"
        $lines.Add("HWND=$($c.Hwnd.ToInt64()) | class='$($c.ClassName)' | text='$($c.Text)' | id=$($c.ControlId) | visible=$($c.Visible) | enabled=$($c.Enabled) | rect=$rect") | Out-Null
    }
    try {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Write-LiveStatus "[UIA-DUMP] Win32 handles dump written: $path"
    } catch {}
}

function Invoke-NvidiaInstallerOptionsViaWin32Handles(
    [System.Windows.Automation.AutomationElement]$nvWin = $null
) {
    if (-not (Ensure-NvidiaWin32MsaaType)) { return $false }
    if (-not (Test-NvidiaWin32MsaaTypeLoaded)) { return $false }

    $rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
    if ($rootHwnd -eq [IntPtr]::Zero) { return $false }

    if (-not $nvWin) {
        try { $nvWin = [System.Windows.Automation.AutomationElement]::FromHandle($rootHwnd) } catch {}
    }
    if (-not (Test-NvidiaInstallerOptionsWin32PageReady $rootHwnd $nvWin)) { return $false }

    Write-LiveStatus '[NVIDIA-INSTALLER] Options page detected'
    Write-LiveStatus "[SAFE-WIN32] NVIDIA options root hwnd found: $($rootHwnd.ToInt64()) title='$([NvidiaWin32Msaa]::GetWndText($rootHwnd))'"

    $expressInfo = [NvidiaWin32Msaa]::FindChildByTextContains($rootHwnd, @('&Expresse', 'Expresse', '&Express', 'Express'))
    $customInfo = [NvidiaWin32Msaa]::FindChildByTextContains($rootHwnd, @('&Personnalisée', '&Personnalisee', 'Personnalisée', 'Personnalisee', 'Custom'))
    $nextInfo = [NvidiaWin32Msaa]::FindChildByTextContains($rootHwnd, @('&SUIVANT', 'SUIVANT', '&Suivant', 'Suivant', '&Next', 'Next'))

    if ($expressInfo) {
        Write-LiveStatus "[SAFE-WIN32] Express hwnd found: text='$($expressInfo.Text)' id=$($expressInfo.ControlId)"
    }
    if ($customInfo) {
        Write-LiveStatus "[SAFE-WIN32] Custom hwnd found: text='$($customInfo.Text)' id=$($customInfo.ControlId)"
    }
    if ($nextInfo) {
        Write-LiveStatus "[SAFE-WIN32] Next hwnd found: text='$($nextInfo.Text)' id=$($nextInfo.ControlId)"
    }

    if (-not $customInfo -or -not $nextInfo) {
        Write-NvidiaInstallerOptionsWin32HandlesDump $rootHwnd
        Write-LiveStatus '[NVIDIA-INSTALLER] Win32 custom/next hwnd not found, manual required'
        return $false
    }

    $customHwnd = $customInfo.Hwnd
    $nextHwnd = $nextInfo.Hwnd

    [NvidiaWin32Msaa]::InvokeControlClick($customHwnd, $rootHwnd)
    Write-LiveStatus '[SAFE-WIN32] BM_CLICK custom invoked'
    Write-LiveStatus '[SAFE-WIN32] WM_COMMAND BN_CLICKED custom sent'
    Start-Sleep -Milliseconds 400

    [NvidiaWin32Msaa]::InvokeControlClick($nextHwnd, $rootHwnd)
    Write-LiveStatus '[SAFE-WIN32] BM_CLICK next invoked'
    Write-LiveStatus '[SAFE-WIN32] WM_COMMAND BN_CLICKED next sent'

    return $true
}

function Test-NvidiaInstallerOptionsAutomationAllowed(
    [System.Windows.Automation.AutomationElement]$nvWin
) {
    if (-not $nvWin) { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$nvWin.Current.Name))) { return $false }
    $blob = Get-TextBlob $nvWin
    if (-not (Test-NvidiaInstallOptionsPageExactTitle $blob)) { return $false }
    if (-not (Test-NvidiaInstallOptionsPageHasExpress $nvWin $blob)) { return $false }
    if (-not (Test-NvidiaInstallOptionsHasCustomText $blob)) { return $false }
    if (-not (Test-NvidiaNoOtherInstallerScreenActive $blob $nvWin)) { return $false }
    return $true
}

function Get-NvidiaInstallerOptionsDumpPath {
    if ($LogPath) {
        return (Join-Path (Split-Path -Parent $LogPath) 'nvidia-installer-options-page-uia-dump.txt')
    }
    $root = Split-Path -Parent $PSScriptRoot
    $logsDir = Join-Path $root 'logs'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        try { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null } catch {}
    }
    return (Join-Path $logsDir 'nvidia-installer-options-page-uia-dump.txt')
}

function Get-NvidiaUiaElementPatternFlags([System.Windows.Automation.AutomationElement]$el) {
    $flags = @{
        SelectionItem = 'no'
        Invoke = 'no'
        LegacyIAccessible = 'no'
    }
    if (-not $el) { return $flags }
    try {
        $sp = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sp) { $flags.SelectionItem = 'yes' }
    } catch {}
    try {
        $ip = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        if ($ip) { $flags.Invoke = 'yes' }
    } catch {}
    try {
        $lp = $el.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
        if ($lp) { $flags.LegacyIAccessible = 'yes' }
    } catch {}
    return $flags
}

function Write-NvidiaInstallerOptionsPageFailureDumpToFile([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$root.Current.Name))) { return }
    $path = Get-NvidiaInstallerOptionsDumpPath
    $keywords = @('Express', 'Personnalis', 'Personnalise', 'avanc', 'avance', 'Custom', 'Advanced', 'Suivant', 'Next', 'SUIVANT')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('WINDOW=' + [string]$root.Current.Name) | Out-Null
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                $n = [string]$el.Current.Name
                $aid = ''
                try { $aid = [string]$el.Current.AutomationId } catch {}
                $hay = ($n + ' ' + $aid)
                $hit = $false
                foreach ($kw in $keywords) {
                    if ($hay.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $hit = $true
                        break
                    }
                }
                if (-not $hit) { continue }
                $ct = $el.Current.ControlType.ProgrammaticName
                $en = 'True'
                try { if (-not $el.Current.IsEnabled) { $en = 'False' } } catch {}
                $off = 'False'
                try { if ($el.Current.IsOffscreen) { $off = 'True' } } catch {}
                $focus = 'False'
                try { if ($el.Current.HasKeyboardFocus) { $focus = 'True' } } catch {}
                $rect = Format-NvidiaUiRect $el.Current.BoundingRectangle
                $pat = Get-NvidiaUiaElementPatternFlags $el
                $line = "Name='$n' | AutomationId='$aid' | ControlType=$ct | IsEnabled=$en | IsOffscreen=$off | HasKeyboardFocus=$focus | BoundingRectangle=$rect | SelectionItem=$($pat.SelectionItem) | Invoke=$($pat.Invoke) | LegacyIAccessible=$($pat.LegacyIAccessible)"
                $lines.Add($line) | Out-Null
            } catch {}
        }
    } catch {}
    try {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Write-LiveStatus "[UIA-DUMP] Options page failure dump written: $path"
    } catch {}
}

function Get-NvidiaCustomInstallRadioNamePatterns {
    return @(
        'Personnalisée (avancée)', 'Personnalisee (avancee)',
        'Personnalisée', 'Personnalisee', 'Custom (Advanced)', 'Custom'
    )
}

function Find-NvidiaCustomAdvancedOptionElement([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return $null }
    $types = @(
        [System.Windows.Automation.ControlType]::RadioButton,
        [System.Windows.Automation.ControlType]::Button
    )
    foreach ($pattern in (Get-NvidiaCustomInstallRadioNamePatterns)) {
        $el = Find-NvidiaElementByNameContains $root $types @($pattern)
        if ($el) { return $el }
    }
    $customPatterns = Get-NvidiaCustomInstallRadioNamePatterns
    $near = Find-NvidiaRadioNearTextOnSameRow $root $customPatterns
    if ($near) { return $near }
    return (Find-NvidiaCustomAdvancedRadio $root)
}

function Invoke-NvidiaInstallOptionsLevel1Radio(
    [System.Windows.Automation.AutomationElement]$nvWin
) {
    if (-not $nvWin) { return $false }
    $controlTypes = @(
        [System.Windows.Automation.ControlType]::RadioButton,
        [System.Windows.Automation.ControlType]::Button
    )
    foreach ($pattern in (Get-NvidiaCustomInstallRadioNamePatterns)) {
        $tryEl = Find-NvidiaElementByNameContains $nvWin $controlTypes @($pattern)
        if (-not $tryEl) { continue }
        $tryName = ''
        try { $tryName = [string]$tryEl.Current.Name } catch {}
        if (-not $tryName) { $tryName = $pattern }
        if (Test-NvidiaRadioIsSelected $tryEl) {
            Write-LiveStatus '[SAFE-UIA] Selected radio Personnalisée (avancée)'
            return $true
        }
        if (SafeSelectRadio $tryEl $tryName) {
            Start-Sleep -Milliseconds 300
            if (Test-NvidiaCustomInstallSelected $nvWin $tryEl) {
                Write-LiveStatus '[SAFE-UIA] Selected radio Personnalisée (avancée)'
                return $true
            }
        }
    }
    $near = Find-NvidiaRadioNearTextOnSameRow $nvWin (Get-NvidiaCustomInstallRadioNamePatterns)
    if ($near) {
        $nearName = ''
        try { $nearName = [string]$near.Current.Name } catch {}
        if (-not $nearName) { $nearName = 'Personnalisée (avancée)' }
        if (Test-NvidiaRadioIsSelected $near) {
            Write-LiveStatus '[SAFE-UIA] Selected radio Personnalisée (avancée)'
            return $true
        }
        if (SafeSelectRadio $near $nearName) {
            Start-Sleep -Milliseconds 300
            if (Test-NvidiaCustomInstallSelected $nvWin $near) {
                Write-LiveStatus '[SAFE-UIA] Selected radio Personnalisée (avancée)'
                return $true
            }
        }
    }
    return $false
}

function Invoke-NvidiaInstallOptionsLevel2LabelClick(
    [System.Windows.Automation.AutomationElement]$nvWin
) {
    if (-not $nvWin) { return $false }
    $radioRef = [ref]$null
    if (-not (Invoke-NvidiaCustomLabelClick $nvWin $radioRef)) { return $false }
    $radio = $radioRef.Value
    if (Test-NvidiaCustomInstallSelected $nvWin $radio) { return $true }
    $express = Find-NvidiaExpressRadio $nvWin
    if ($express -and (Test-NvidiaRadioIsSelected $express)) { return $false }
    $blob = Get-TextBlob $nvWin
    if (Test-NvidiaInstallOptionsPageDetected $nvWin $blob) { return $true }
    return $false
}

function Invoke-NvidiaCustomViaUiaLegacyMsaa(
    [System.Windows.Automation.AutomationElement]$nvWin
) {
    if (-not $nvWin) { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$nvWin.Current.Name))) { return $false }
    try {
        $all = $nvWin.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                if (-not $el.Current.IsEnabled) { continue }
                $n = [string]$el.Current.Name
                if (-not (Test-NvidiaMsaaCustomName $n)) { continue }
                $lp = $el.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
                if (-not $lp) { continue }
                $role = ''
                $state = ''
                try { $role = [string]$lp.Current.Role } catch {}
                try { $state = [string]$lp.Current.State } catch {}
                Write-LiveStatus "[SAFE-MSAA] Found custom option (UIA Legacy): Name='$n' Role=$role State=$state"
                try {
                    $lp.DoDefaultAction()
                    Write-LiveStatus '[SAFE-MSAA] accDoDefaultAction invoked on custom option (UIA Legacy)'
                    return $true
                } catch {}
            } catch {}
        }
    } catch {}
    return $false
}

function Invoke-NvidiaCustomViaMsaa([System.Windows.Automation.AutomationElement]$nvWin) {
    if (-not (Test-NvidiaInstallerOptionsAutomationAllowed $nvWin)) { return $false }
    Write-LiveStatus '[NVIDIA-INSTALLER] Trying MSAA custom selection'
    $hwnd = Get-NvidiaInstallerNativeHwnd $nvWin
    if ($hwnd -ne [IntPtr]::Zero) {
        if ((Ensure-NvidiaWin32MsaaType) -and (Test-NvidiaWin32MsaaTypeLoaded)) {
            $foundName = ''
            $foundRole = ''
            if ([NvidiaWin32Msaa]::TryMsaaSelectCustom($hwnd, [ref]$foundName, [ref]$foundRole)) {
                Write-LiveStatus "[SAFE-MSAA] Found custom option: Name='$foundName' Role=$foundRole"
                Write-LiveStatus '[SAFE-MSAA] accDoDefaultAction invoked on custom option'
                Start-Sleep -Milliseconds 300
                if (Test-NvidiaCustomInstallSelected $nvWin) {
                    Write-LiveStatus '[NVIDIA-INSTALLER] Custom selected via MSAA'
                    return $true
                }
            }
        }
    }
    if (Invoke-NvidiaCustomViaUiaLegacyMsaa $nvWin) {
        Start-Sleep -Milliseconds 300
        if (Test-NvidiaCustomInstallSelected $nvWin) {
            Write-LiveStatus '[NVIDIA-INSTALLER] Custom selected via MSAA'
            return $true
        }
    }
    return $false
}

function Invoke-NvidiaCustomViaWin32Button([System.Windows.Automation.AutomationElement]$nvWin) {
    if (-not (Test-NvidiaInstallerOptionsAutomationAllowed $nvWin)) { return $false }
    Write-LiveStatus '[NVIDIA-INSTALLER] Trying Win32 custom selection'
    $hwnd = Get-NvidiaInstallerNativeHwnd $nvWin
    if ($hwnd -eq [IntPtr]::Zero) { return $false }
    if (-not (Ensure-NvidiaWin32MsaaType)) { return $false }
    if (-not (Test-NvidiaWin32MsaaTypeLoaded)) { return $false }
    $labelHwnd = [IntPtr]::Zero
    $radioHwnd = [IntPtr]::Zero
    if (-not [NvidiaWin32Msaa]::TryWin32SelectCustom($hwnd, [ref]$labelHwnd, [ref]$radioHwnd)) {
        return $false
    }
    if ($labelHwnd -ne [IntPtr]::Zero) {
        $labelText = [NvidiaWin32Msaa]::GetWndText($labelHwnd)
        $labelCls = [NvidiaWin32Msaa]::GetWndClass($labelHwnd)
        Write-LiveStatus "[SAFE-WIN32] Custom label HWND found: HWND=$($labelHwnd.ToInt64()) class=$labelCls text='$labelText'"
    }
    if ($radioHwnd -ne [IntPtr]::Zero) {
        $radioText = [NvidiaWin32Msaa]::GetWndText($radioHwnd)
        $radioCls = [NvidiaWin32Msaa]::GetWndClass($radioHwnd)
        Write-LiveStatus "[SAFE-WIN32] Nearest radio HWND found: HWND=$($radioHwnd.ToInt64()) class=$radioCls text='$radioText'"
        try {
            $chk = [NvidiaWin32Msaa]::SendMessage($radioHwnd, [NvidiaWin32Msaa]::BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero)
            Write-LiveStatus "[SAFE-WIN32] BM_GETCHECK before click: $chk"
        } catch {}
        if ([NvidiaWin32Msaa]::ClickWin32Button($radioHwnd, $hwnd)) {
            Write-LiveStatus '[SAFE-WIN32] BM_CLICK invoked on custom radio'
            Start-Sleep -Milliseconds 300
            try {
                $chkAfter = [NvidiaWin32Msaa]::SendMessage($radioHwnd, [NvidiaWin32Msaa]::BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero)
                Write-LiveStatus "[SAFE-WIN32] BM_GETCHECK after click: $chkAfter"
            } catch {}
            if (Test-NvidiaCustomInstallSelected $nvWin) {
                Write-LiveStatus '[NVIDIA-INSTALLER] Custom selected via Win32'
                return $true
            }
            $express = Find-NvidiaExpressRadio $nvWin
            if ($express -and (Test-NvidiaRadioIsSelected $express)) { return $false }
            Write-LiveStatus '[NVIDIA-INSTALLER] Custom selection not verifiable after Win32 fallback'
            return $false
        }
    }
    return $false
}

function Get-NvidiaInstallerOptionsWin32MsaaDumpPath {
    if ($LogPath) {
        return (Join-Path (Split-Path -Parent $LogPath) 'nvidia-installer-options-win32-msaa-dump.txt')
    }
    $root = Split-Path -Parent $PSScriptRoot
    $logsDir = Join-Path $root 'logs'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        try { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null } catch {}
    }
    return (Join-Path $logsDir 'nvidia-installer-options-win32-msaa-dump.txt')
}

function Write-NvidiaInstallerOptionsWin32MsaaDumpToFile([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$root.Current.Name))) { return }
    $path = Get-NvidiaInstallerOptionsWin32MsaaDumpPath
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('WINDOW=' + [string]$root.Current.Name) | Out-Null
    $lines.Add('=== UIA (NVIDIA window only) ===') | Out-Null
    $keywords = @('Express', 'Personnalis', 'Personnalise', 'avanc', 'avance', 'Custom', 'Advanced', 'Suivant', 'Next', 'SUIVANT')
    try {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                $n = [string]$el.Current.Name
                $aid = ''
                try { $aid = [string]$el.Current.AutomationId } catch {}
                $hay = ($n + ' ' + $aid)
                $hit = $false
                foreach ($kw in $keywords) {
                    if ($hay.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
                }
                if (-not $hit) { continue }
                $pat = Get-NvidiaUiaElementPatternFlags $el
                $rect = Format-NvidiaUiRect $el.Current.BoundingRectangle
                $lines.Add("UIA Name='$n' AutomationId='$aid' ControlType=$($el.Current.ControlType.ProgrammaticName) BoundingRectangle=$rect SelectionItem=$($pat.SelectionItem) Invoke=$($pat.Invoke) LegacyIAccessible=$($pat.LegacyIAccessible)") | Out-Null
            } catch {}
        }
    } catch {}
    $hwnd = Get-NvidiaInstallerNativeHwnd $root
    if ($hwnd -ne [IntPtr]::Zero -and (Ensure-NvidiaWin32MsaaType) -and (Test-NvidiaWin32MsaaTypeLoaded)) {
        $lines.Add('=== MSAA tree ===') | Out-Null
        $nodes = New-Object 'System.Collections.Generic.List`1[[NvidiaWin32Msaa+MsaaNodeInfo]]'
        [NvidiaWin32Msaa]::CollectMsaaNodes($hwnd, $nodes, 120)
        foreach ($node in $nodes) {
            $lines.Add("MSAA Name='$($node.Name)' Role=$($node.Role) State=$($node.State) DefaultAction='$($node.DefaultAction)' Location=$($node.Location) Depth=$($node.Depth)") | Out-Null
        }
        $lines.Add('=== Win32 child windows ===') | Out-Null
        $children = [NvidiaWin32Msaa]::EnumChildren($hwnd)
        foreach ($c in $children) {
            $hay = ($c.Text + ' ' + $c.ClassName)
            $hit = $false
            foreach ($kw in $keywords) {
                if ($hay.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
            }
            if (-not $hit) { continue }
            $rect = "L$($c.Rect.Left),T$($c.Rect.Top),R$($c.Rect.Right),B$($c.Rect.Bottom)"
            $chk = ''
            if ($null -ne $c.CheckState) { $chk = " BM_GETCHECK=$($c.CheckState)" }
            $lines.Add("WIN32 HWND=$($c.Hwnd.ToInt64()) class='$($c.ClassName)' text='$($c.Text)' rect=$rect style=$($c.Style) visible=$($c.Visible) enabled=$($c.Enabled)$chk") | Out-Null
        }
    }
    try {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        Write-LiveStatus "[UIA-DUMP] Options Win32/MSAA dump written: $path"
    } catch {}
}

function Invoke-NvidiaInstallerInvokeSuivant(
    [System.Windows.Automation.AutomationElement]$nvWin,
    [string[]]$forbiddenBtn,
    [string]$afterContext
) {
    $nextBtn = Find-NvidiaInstallerButtonByNameContains $nvWin @(
        'SUIVANT', 'Suivant', 'NEXT', '&Suivant', '&Next'
    ) $forbiddenBtn
    if (-not $nextBtn) {
        Write-NvidiaInstallerOptionsPageDump $nvWin
        Write-LiveStatus '[NVIDIA Installer] Bouton Suivant introuvable — action manuelle requise.'
        return $false
    }
    $nextName = ''
    try { $nextName = [string]$nextBtn.Current.Name } catch {}
    if (-not $nextName) { $nextName = 'Suivant' }
    if (SafeInvokeElement $nextBtn $nextName) {
        Write-LiveStatus "[SAFE-UIA] Invoked button Suivant $afterContext"
        return $true
    }
    $hwnd = Get-NvidiaInstallerNativeHwnd $nvWin
    if ($hwnd -ne [IntPtr]::Zero -and (Test-NvidiaInstallerProgrammeWindowTitle ([string]$nvWin.Current.Name))) {
        if ((Ensure-NvidiaWin32MsaaType) -and (Test-NvidiaWin32MsaaTypeLoaded)) {
            $nextHwnd = [NvidiaWin32Msaa]::FindNextButtonHwnd($hwnd)
            if ($nextHwnd -ne [IntPtr]::Zero) {
                if ([NvidiaWin32Msaa]::ClickWin32Button($nextHwnd, $hwnd)) {
                    Write-LiveStatus "[SAFE-WIN32] BM_CLICK invoked on Suivant button $afterContext"
                    return $true
                }
            }
        }
    }
    Write-NvidiaInstallerOptionsPageDump $nvWin
    Write-LiveStatus '[NVIDIA Installer] Clic Suivant impossible — action manuelle requise.'
    return $false
}

function Test-NvidiaCustomInstallSelected(
    [System.Windows.Automation.AutomationElement]$root,
    [System.Windows.Automation.AutomationElement]$preferredRadio = $null
) {
    if ($preferredRadio -and (Test-NvidiaRadioIsSelected $preferredRadio)) { return $true }
    $customPatterns = @(
        'Personnalisée (avancée)', 'Personnalisee (avancee)',
        'Personnalisée', 'Personnalisee', 'Custom (Advanced)', 'Custom'
    )
    $custom = Find-NvidiaRadioNearTextOnSameRow $root $customPatterns
    if (-not $custom) { $custom = Find-NvidiaCustomAdvancedRadio $root }
    if ($custom -and (Test-NvidiaRadioIsSelected $custom)) { return $true }
    $express = Find-NvidiaExpressRadio $root
    if ($express -and (Test-NvidiaRadioIsSelected $express)) { return $false }
    return $false
}

function Invoke-NvidiaInstallerSelectCustomAndNext(
    [System.Windows.Automation.AutomationElement]$nvWin,
    [string[]]$forbiddenBtn
) {
    if (-not $nvWin) { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$nvWin.Current.Name))) { return $false }

    $rootHwnd = [IntPtr]::Zero
    if ((Ensure-NvidiaWin32MsaaType) -and (Test-NvidiaWin32MsaaTypeLoaded)) {
        $rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
    }
    if ($rootHwnd -eq [IntPtr]::Zero) {
        $rootHwnd = Get-NvidiaInstallerNativeHwnd $nvWin
    }
    if (-not (Test-NvidiaInstallerOptionsWin32PageReady $rootHwnd $nvWin)) {
        return $false
    }

    Set-NvcForeground $nvWin
    Start-Sleep -Milliseconds 200

    if (-not (Invoke-NvidiaInstallerOptionsViaWin32Handles $nvWin)) {
        Write-NvidiaInstallerOptionsPageDump $nvWin
        Write-NvidiaInstallerOptionsWin32HandlesDump $rootHwnd
        Write-LiveStatus '[NVIDIA Installer] Personnalisée introuvable — action manuelle requise.'
        return $false
    }

    Set-LogField 'NVIDIA_OPTIONS_NEXT' 'win32_bm_click'
    return $true
}

function Invoke-NvidiaInstallOptionsStep(
    [System.Windows.Automation.AutomationElement]$nvWin,
    [string[]]$forbiddenBtn
) {
    if ($script:hasCompletedNvidiaInstallOptionsPage) { return $false }
    if (-not $nvWin) { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$nvWin.Current.Name))) { return $false }

    if (-not (Invoke-NvidiaInstallerSelectCustomAndNext $nvWin $forbiddenBtn)) {
        return $false
    }

    $script:hasClickedCustomAdvancedNvidiaInstaller = $true
    $script:hasCompletedNvidiaInstallOptionsPage = $true
    Set-LogField 'NVIDIA_CUSTOM_SELECTED' 'oui'
    $loopSt = Read-NvidiaInstallerLoopState
    $loopSt.HasCompletedInstallOptions = 'true'
    Write-NvidiaInstallerLoopState $loopSt
    return $true
}

function Wait-AndApply-NvidiaInstallOptions([int]$timeoutSec, [string[]]$forbiddenBtn) {
    $script:hasClickedCustomAdvancedNvidiaInstaller = $false
    $script:hasCompletedNvidiaInstallOptionsPage = $false
    $script:NvidiaOptionsTimingStarted = $false
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline -and -not $script:hasCompletedNvidiaInstallOptionsPage) {
        $nvWin = Get-NvidiaInstallerWindow
        if (-not $nvWin) {
            Start-Sleep -Milliseconds $script:WorkflowPollMs
            continue
        }
        if (Invoke-NvidiaInstallOptionsStep $nvWin $forbiddenBtn) {
            Write-TimingLog 'Action suivante immédiate' -1
            return $true
        }
        Start-Sleep -Milliseconds $script:WorkflowPollMs
    }
    return $script:hasCompletedNvidiaInstallOptionsPage
}

function Wait-NvidiaInstallerWindow([int]$timeoutSec) {
    $t0 = [DateTime]::UtcNow
    Write-LiveStatus 'En attente installateur NVIDIA...'
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $w = Get-NvidiaInstallerWindow
        if ($w) {
            Write-TimingLog 'Installateur NVIDIA ouvert' ([int](([DateTime]::UtcNow - $t0).TotalMilliseconds))
            return $w
        }
        Start-Sleep -Milliseconds $script:WorkflowPollMs
    }
    return $null
}

function Click-ButtonByNameContains(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$nameParts,
    [string[]]$forbidden
) {
    if (-not $root) { return $false }
    $btnType = [System.Windows.Automation.ControlType]::Button
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
    foreach ($btn in $all) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            if (Test-ButtonNameForbidden $n $forbidden) { continue }
            $matched = $false
            foreach ($part in $nameParts) {
                if ($n.IndexOf($part, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $matched = $true
                    break
                }
            }
            if (-not $matched) { continue }
            Scroll-ElementIntoView $btn | Out-Null
            Start-Sleep -Milliseconds 200
            if (Invoke-Element $btn) { return $true }
        } catch {}
    }
    return $false
}

function Click-NvidiaAcceptLicense([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$root.Current.Name))) { return $false }
    $blob = Get-TextBlob $root
    if ($blob -notmatch '(?i)Contrat de licence du logiciel NVIDIA|Contrat de licence|NVIDIA Driver License Agreement') {
        return $false
    }

    Write-LiveStatus '[NVIDIA Installer] Licence détectée.'
    Set-LogField 'NVIDIA_STEP' 'license'
    Set-NvcForeground $root
    Start-Sleep -Milliseconds 200

    $licenseBtn = Find-NvidiaInstallerButtonByNameContains $root @(
        'ACCEPTER ET CONTINUER', 'Accepter et continuer',
        'ACCEPT AND CONTINUE', 'Accept and Continue',
        'Agree and Continue', 'AGREE AND CONTINUE'
    ) $forbiddenBtn

    if ($licenseBtn) {
        Write-LiveStatus '[NVIDIA Installer] Bouton licence trouvé via UIA.'
        if (TryInvokeOrClickCenter $licenseBtn $root) {
            Write-LiveStatus '[NVIDIA Installer] Accepter et continuer cliqué.'
            Set-LogField 'NVIDIA_LICENSE_ACCEPTED' 'uia'
            Start-Sleep -Milliseconds 500
            return $true
        }
    }

    if (Click-ButtonByNameContains $root @(
        'ACCEPTER ET CONTINUER', 'Accepter et continuer',
        'ACCEPT AND CONTINUE', 'Accept and Continue'
    ) $forbiddenBtn) {
        Write-LiveStatus '[NVIDIA Installer] Accepter et continuer cliqué.'
        Set-LogField 'NVIDIA_LICENSE_ACCEPTED' 'uia_invoke'
        Start-Sleep -Milliseconds 500
        return $true
    }

    Write-NvidiaInstallerUiDump $root
    Write-LiveStatus '[NVIDIA Installer] Bouton licence introuvable, dump UIA effectué.'
    Set-LogField 'NVIDIA_LICENSE_ACCEPTED' 'non'
    return $false
}

function Invoke-NvidiaCustomInstallOptionsStep(
    [System.Windows.Automation.AutomationElement]$nvWin,
    [string[]]$forbidden
) {
    if ($script:hasCompletedNvidiaCustomOptionsPage) { return $false }
    if (-not $nvWin) { return $false }
    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$nvWin.Current.Name))) { return $false }

    $blob = Get-TextBlob $nvWin
    if (-not (Test-NvidiaCustomInstallOptionsPage $blob)) { return $false }

    Write-LiveStatus '[NVIDIA Installer] Options personnalisées détectées.'
    Set-LogField 'NVIDIA_STEP' 'custom_options'
    Set-NvcForeground $nvWin
    Start-Sleep -Milliseconds 200

    $nextBtn = Find-NvidiaInstallerButtonByNameContains $nvWin @(
        'SUIVANT', 'Suivant', 'NEXT', '&Suivant', '&Next'
    ) $forbidden
    if (-not $nextBtn) {
        Write-UiaDumpForElement $nvWin 'NVIDIA installer Suivant (custom options page) not found'
        Write-LiveStatus '[NVIDIA Installer] Bouton Suivant introuvable — action manuelle requise.'
        return $false
    }

    $nextName = ''
    try { $nextName = [string]$nextBtn.Current.Name } catch {}
    if (-not $nextName) { $nextName = 'Suivant' }

    if (SafeInvokeElement $nextBtn $nextName) {
        Write-LiveStatus '[SAFE-UIA] Invoked button Suivant (options personnalisées).'
        $script:hasCompletedNvidiaCustomOptionsPage = $true
        Set-LogField 'NVIDIA_CUSTOM_NEXT' 'safe_uia_invoke'
        $loopSt = Read-NvidiaInstallerLoopState
        $loopSt.HasCompletedCustomOptions = 'true'
        Write-NvidiaInstallerLoopState $loopSt
        return $true
    }

    $rootHwnd = Get-NvidiaInstallerNativeHwnd $nvWin
    if ($rootHwnd -eq [IntPtr]::Zero -and (Ensure-NvidiaWin32MsaaType) -and (Test-NvidiaWin32MsaaTypeLoaded)) {
        $rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
    }
    if ($rootHwnd -ne [IntPtr]::Zero -and (Ensure-NvidiaWin32MsaaType) -and (Test-NvidiaWin32MsaaTypeLoaded)) {
        $nextInfo = [NvidiaWin32Msaa]::FindChildByTextContains($rootHwnd, @('&SUIVANT', 'SUIVANT', '&Suivant', 'Suivant', '&Next', 'Next'))
        if ($nextInfo -and $nextInfo.Visible -and $nextInfo.Enabled) {
            [NvidiaWin32Msaa]::InvokeControlClick($nextInfo.Hwnd, $rootHwnd)
            Write-LiveStatus '[SAFE-WIN32] BM_CLICK next invoked (custom options page)'
            Write-LiveStatus '[SAFE-WIN32] WM_COMMAND BN_CLICKED next sent (custom options page)'
            $script:hasCompletedNvidiaCustomOptionsPage = $true
            Set-LogField 'NVIDIA_CUSTOM_NEXT' 'win32_bm_click'
            $loopSt = Read-NvidiaInstallerLoopState
            $loopSt.HasCompletedCustomOptions = 'true'
            Write-NvidiaInstallerLoopState $loopSt
            return $true
        }
    }

    Write-UiaDumpForElement $nvWin 'NVIDIA installer SafeInvokeElement Suivant (custom options) failed'
    return $false
}

function Select-NvidiaCustomInstall([System.Windows.Automation.AutomationElement]$root) {
    Set-LogField 'NVIDIA_STEP' 'install_options'
    return (Invoke-NvidiaInstallOptionsStep $root $forbiddenBtn)
}

function Test-NvidiaInstallerInstallingPage([string]$blob) {
    if (-not $blob) { return $false }
    if (Test-NvidiaLicensePage $blob) { return $false }
    if (Test-NvidiaInstallOptionsPage $blob) { return $false }
    if (Test-NvidiaCustomInstallOptionsPage $blob) { return $false }
    return ($blob -match '(?i)Installation en cours|Installation du pilote graphique|Installing|Preparing to install')
}

function Get-NvidiaInstallerLoopStatePath {
    if ($LogPath) {
        return (Join-Path (Split-Path -Parent $LogPath) 'nvidia-installer-loop.state')
    }
    return (Join-Path $env:TEMP 'nvidia-installer-loop.state')
}

function Read-NvidiaInstallerLoopState {
    $state = @{
        SawWindow = 'false'
        LastPageKey = ''
        PageStuckSince = ''
        HasCompletedInstallOptions = 'false'
        HasCompletedCustomOptions = 'false'
    }
    $path = Get-NvidiaInstallerLoopStatePath
    if (-not (Test-Path -LiteralPath $path)) { return $state }
    try {
        foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
            if ($line -match '^([^=]+)=(.*)$') {
                $state[$matches[1]] = $matches[2]
            }
        }
    } catch {}
    return $state
}

function Write-NvidiaInstallerLoopState([hashtable]$state) {
    $path = Get-NvidiaInstallerLoopStatePath
    try {
        $lines = @()
        foreach ($k in @('SawWindow', 'LastPageKey', 'PageStuckSince', 'HasCompletedInstallOptions', 'HasCompletedCustomOptions')) {
            if ($state.ContainsKey($k)) {
                $lines += ($k + '=' + $state[$k])
            }
        }
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
    } catch {}
}

function Clear-NvidiaInstallerLoopState {
    $script:NvidiaInstallerWizardRelayLogged = $false
    $script:NvidiaInstallerTickLogLast = $null
    try {
        $path = Get-NvidiaInstallerLoopStatePath
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    } catch {}
}

function Write-NvidiaInstallerTickWindowFoundLog([System.Windows.Automation.AutomationElement]$nvWin) {
    if (-not $nvWin) { return }
    $now = [DateTime]::UtcNow
    if ($script:NvidiaInstallerTickLogLast) {
        try {
            $last = [DateTime]::Parse($script:NvidiaInstallerTickLogLast, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if (($now - $last).TotalSeconds -lt 2.5) { return }
        } catch {}
    }
    $script:NvidiaInstallerTickLogLast = $now.ToString('o')
    $winTitle = ''
    try { $winTitle = [string]$nvWin.Current.Name } catch {}
    Write-LiveStatus "[NVIDIA-INSTALLER] Tick running, window found: title=$winTitle"
}

function Get-NvidiaInstallerPageKey(
    [string]$blob,
    [System.Windows.Automation.AutomationElement]$nvWin = $null
) {
    if (Test-NvidiaLicensePage $blob) { return 'license' }
    if ($nvWin -and (Test-NvidiaInstallOptionsPageDetected $nvWin $blob)) { return 'options' }
    if (Test-NvidiaInstallOptionsPage $blob) { return 'options' }
    if (Test-NvidiaCustomInstallOptionsPage $blob) { return 'custom' }
    if (Test-NvidiaInstallerInstallingPage $blob) { return 'installing' }
    return 'unknown'
}

function Sync-NvidiaInstallerScriptFlagsFromState([hashtable]$state) {
    $script:hasCompletedNvidiaInstallOptionsPage = ($state.HasCompletedInstallOptions -eq 'true')
    $script:hasCompletedNvidiaCustomOptionsPage = ($state.HasCompletedCustomOptions -eq 'true')
}

function Update-NvidiaInstallerStuckState(
    [hashtable]$state,
    [string]$pageKey
) {
    $now = [DateTime]::UtcNow
    if ($state.LastPageKey -eq $pageKey -and $state.PageStuckSince) {
        try {
            $since = [DateTime]::Parse($state.PageStuckSince, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if (($now - $since).TotalSeconds -ge 5) {
                return $true
            }
        } catch {}
        return $false
    }
    $state.LastPageKey = $pageKey
    $state.PageStuckSince = $now.ToString('o')
    return $false
}

function Test-NvidiaInstallerFinalStatePage([string]$blob) {
    if (-not $blob) { return $false }
    if ($blob -match '(?i)\bTerminer\b|\bFinish\b|Installation terminée|Installation terminee|Installation complete|The NVIDIA installer has finished|NVIDIA Installer has finished') {
        return $true
    }
    return $false
}

function Test-NvidiaInstallerFinalYesPopup([System.Windows.Automation.AutomationElement]$nvWin, [string]$blob) {
    if (-not $nvWin -or -not $blob) { return $false }
    if ($blob -notmatch '(?i)\b(Oui|Yes)\b') { return $false }
    if ($blob -match '(?i)Terminer|Finish|Installation termin|complete|finished') { return $true }
    try {
        $yesBtn = Find-NvidiaInstallerButtonByNameContains $nvWin @('Oui', 'Yes', '&Oui', '&Yes') @()
        if ($yesBtn) { return $true }
    } catch {}
    return $false
}

function Test-NvidiaInstallerFinalStateDetected(
    [System.Windows.Automation.AutomationElement]$nvWin,
    [string]$blob,
    [hashtable]$state
) {
    if (Test-NvidiaInstallerFinalStatePage $blob) { return $true }
    if ($nvWin -and (Test-NvidiaInstallerFinalYesPopup $nvWin $blob)) { return $true }
    if ($state -and ($state.SawWindow -eq 'true') -and -not $nvWin) { return $true }
    return $false
}

function Set-NvidiaInstallerProgressComplete {
    Write-LiveStatus '[NVIDIA-INSTALLER] Installation final state detected'
    Write-LiveStatus 'Installation NVIDIA terminée — validation finale manuelle si demandée.'
    Set-LogField 'NV_PROGRESS_PCT' '100'
    Set-LogField 'NVIDIA_INSTALL_FINAL' 'oui'
    Write-LiveStatus '[NVIDIA-INSTALLER] Progress forced to 100'
    Write-LiveStatus '[NVIDIA-INSTALLER] Manual final confirmation may be required'
}

function Invoke-NvidiaInstallerWizardTick {
    $state = Read-NvidiaInstallerLoopState
    Sync-NvidiaInstallerScriptFlagsFromState $state

    $nvWin = Get-NvidiaInstallerWindow
    if (-not $nvWin) {
        if ($state.SawWindow -eq 'true') {
            Set-NvidiaInstallerProgressComplete
            Write-LiveStatus '[NVIDIA Installer] Fin détectée, reprise vérification pilote.'
            Set-LogField 'NVIDIA_TICK_RESULT' 'finished'
            Clear-NvidiaInstallerLoopState
            return 'finished'
        }
        Set-LogField 'NVIDIA_TICK_RESULT' 'no_window'
        return 'no_window'
    }

    if (-not (Test-NvidiaInstallerProgrammeWindowTitle ([string]$nvWin.Current.Name))) {
        Set-LogField 'NVIDIA_TICK_RESULT' 'no_window'
        return 'no_window'
    }

    if (-not $script:NvidiaInstallerWizardRelayLogged) {
        $script:NvidiaInstallerWizardRelayLogged = $true
        Write-LiveStatus '[NVIDIA-INSTALLER] Wizard relay active — Programme d''installation NVIDIA detected after NVCleanstall'
    }

    $state.SawWindow = 'true'
    Write-NvidiaInstallerTickWindowFoundLog $nvWin
    Set-NvcForeground $nvWin
    $blob = Get-TextBlob $nvWin

    if (Test-NvidiaInstallerFinalStateDetected $nvWin $blob $state) {
        Set-NvidiaInstallerProgressComplete
        Set-LogField 'NVIDIA_TICK_RESULT' 'finished'
        Write-NvidiaInstallerLoopState $state
        return 'finished'
    }

    $pageKey = Get-NvidiaInstallerPageKey $blob $nvWin
    if (Update-NvidiaInstallerStuckState $state $pageKey) {
        Write-NvidiaInstallerUiDump $nvWin
        Write-LiveStatus '[NVIDIA Installer] Page bloquée > 5 s — dump UIA effectué.'
    }

    if (Test-NvidiaLicensePage $blob) {
        if (Invoke-NvidiaInstallerLicenseViaWin32Handles $nvWin) {
            $state.LastPageKey = ''
            $state.PageStuckSince = ''
        } else {
            Write-LiveStatus '[NVIDIA Installer] Bouton licence introuvable — action manuelle requise.'
            Set-LogField 'NVIDIA_TICK_RESULT' 'manual'
            Write-NvidiaInstallerLoopState $state
            return 'manual'
        }
        Write-NvidiaInstallerLoopState $state
        Set-LogField 'NVIDIA_TICK_RESULT' 'continue'
        return 'continue'
    }

    if ((Test-NvidiaInstallOptionsPageDetected $nvWin $blob) -and ($state.HasCompletedInstallOptions -ne 'true')) {
        if (Invoke-NvidiaInstallOptionsStep $nvWin $forbiddenBtn) {
            $state.HasCompletedInstallOptions = 'true'
            $state.LastPageKey = ''
            $state.PageStuckSince = ''
        } else {
            Write-LiveStatus '[NVIDIA Installer] Personnalisée / Suivant introuvable — action manuelle requise.'
            Set-LogField 'NVIDIA_TICK_RESULT' 'manual'
            Write-NvidiaInstallerLoopState $state
            return 'manual'
        }
        Write-NvidiaInstallerLoopState $state
        Set-LogField 'NVIDIA_TICK_RESULT' 'continue'
        return 'continue'
    }

    if (($state.HasCompletedInstallOptions -eq 'true') -and ($state.HasCompletedCustomOptions -ne 'true')) {
        if (Test-NvidiaCustomInstallOptionsPage $blob) {
            if (Invoke-NvidiaCustomInstallOptionsStep $nvWin $forbiddenBtn) {
                $state.HasCompletedCustomOptions = 'true'
                $state.LastPageKey = ''
                $state.PageStuckSince = ''
            } else {
                Write-LiveStatus '[NVIDIA Installer] Suivant (options personnalisées) introuvable — action manuelle requise.'
                Set-LogField 'NVIDIA_TICK_RESULT' 'manual'
                Write-NvidiaInstallerLoopState $state
                return 'manual'
            }
        }
        Write-NvidiaInstallerLoopState $state
        Set-LogField 'NVIDIA_TICK_RESULT' 'continue'
        return 'continue'
    }

    if (Test-NvidiaInstallerInstallingPage $blob) {
        Write-LiveStatus '[NVIDIA Installer] Installation en cours.'
        Write-LiveStatus 'Installation NVIDIA en cours...'
        $state.HasCompletedInstallOptions = 'true'
        $state.HasCompletedCustomOptions = 'true'
        Write-NvidiaInstallerLoopState $state
        Set-LogField 'NVIDIA_TICK_RESULT' 'installing'
        return 'installing'
    }

    if ($state.HasCompletedCustomOptions -eq 'true') {
        Write-LiveStatus 'Installation NVIDIA en cours...'
        Set-LogField 'NVIDIA_TICK_RESULT' 'installing'
        Write-NvidiaInstallerLoopState $state
        return 'installing'
    }

    Write-NvidiaInstallerLoopState $state
    Set-LogField 'NVIDIA_TICK_RESULT' 'continue'
    return 'continue'
}

function Confirm-DisplayDriverRequired([System.Windows.Automation.AutomationElement]$root) {
    $patterns = @(
        '^Display Driver \(required\)$',
        '^Display Driver \(Required\)$',
        'Display Driver \(required\)'
    )
    $state = Get-CheckBoxState $root $patterns
    if ($state.Status -eq 'not_found') {
        Set-LogField 'DISPLAY_DRIVER_REQUIRED_FOUND' 'non'
        Set-LogField 'DISPLAY_DRIVER_REQUIRED_CHECKED' 'not_found'
        return
    }
    Set-LogField 'DISPLAY_DRIVER_REQUIRED_FOUND' 'oui'
    if ($state.Status -eq 'already_checked') {
        Set-LogField 'DISPLAY_DRIVER_REQUIRED_CHECKED' 'already_checked'
        return
    }
    if ($state.Status -eq 'unchecked') {
        $r = Ensure-CheckBoxCheckedOnce $root $patterns
        Set-LogField 'DISPLAY_DRIVER_REQUIRED_CHECKED' $r
        return
    }
    Set-LogField 'DISPLAY_DRIVER_REQUIRED_CHECKED' $state.Status
}

# --- Main ---
try {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
} catch {
    Set-LogField 'ERROR' 'uia_assembly'
    Set-LogField 'RESULT' 'uia_assembly_fail'
    Write-LiveStatus 'Automatisation bloquée : action manuelle requise.'
    exit 2
}

if ($LogPath) {
    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Add-Content -LiteralPath $LogPath -Value ("DATE=" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
    Add-Content -LiteralPath $LogPath -Value 'ACTION=nvcleaninstall_auto' -Encoding UTF8
}

Set-LogField 'SOURCE_OF_TRUTH' 'written_list_only'

$forbiddenBtn = @('RESTART', 'REDEMARR', 'SHUTDOWN', 'REBOOT', 'ÉTEINDRE', 'CANCEL', 'BACK', 'ANNULER', 'RETOUR', 'REDEMARRER')

if ($Phase -eq 'wait-tweaks') {
    Set-LogField 'WAITING_FOR_INSTALLATION_TWEAKS' 'oui'
    Write-LiveStatus 'Attente de la page Installation Tweaks...'
    $start = Get-Date
    $deadline = $start.AddSeconds(300)
    $preparingPatterns = @(
        'PREPARING SOURCE', 'COPYING INSTALL', 'COPYING INSTALL FILES',
        'PREPARING', 'EXTRACTING', 'DOWNLOADING', 'PLEASE WAIT', 'PROCESSING'
    )
    $tweaksPatterns = @(
        'INSTALLATION TWEAKS', 'DISABLE INSTALLER TELEMETRY',
        'PERFORM A CLEAN INSTALLATION', 'DISABLE MULTIPLANE OVERLAY',
        'SHOW EXPERT TWEAKS', 'DISABLE ANSEL'
    )
    while ((Get-Date) -lt $deadline) {
        $win = Get-NvcRootWindow
        if ($win) {
            $blob = Get-TextBlob $win
            $u = if ($blob) { $blob.ToUpperInvariant() } else { '' }
            $isPreparing = $false
            foreach ($p in $preparingPatterns) {
                if ($u.Contains($p)) { $isPreparing = $true; break }
            }
            if (-not $isPreparing) {
                foreach ($p in $tweaksPatterns) {
                    if ($u.Contains($p)) {
                        $elapsed = [int][Math]::Floor(((Get-Date) - $start).TotalSeconds)
                        Set-LogField 'INSTALLATION_TWEAKS_DETECTED' 'oui'
                        Set-LogField 'INSTALLATION_TWEAKS_DETECTED_AFTER_SECONDS' ([string]$elapsed)
                        Set-LogField 'INSTALLATION_TWEAKS_REACHED' 'oui'
                        Write-LiveStatus 'Page Installation Tweaks detectee. Confirmation requise.'
                        exit 0
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    Set-LogField 'INSTALLATION_TWEAKS_DETECTED' 'non'
    Set-LogField 'INSTALLATION_TWEAKS_REACHED' 'non'
    Set-LogField 'RESULT' 'tweaks_page_timeout'
    Write-LiveStatus 'Page Installation Tweaks non detectee. Continue manuellement.'
    exit 14
}

if ($Phase -eq 'tweaks') {
    Set-LogField 'APPLY_TWEAKS_STARTED' 'oui'
    Write-LiveStatus 'Application des reglages NVIDIA…'

    $win = Get-NvcRootWindow
    if (-not $win) { $win = Wait-NvcWindow 15 }
    if (-not $win) {
        Set-LogField 'NVCLEANSTALL_WINDOW_FOUND' 'non'
        Set-LogField 'TOTAL_OPTIONS_REQUESTED' '10'
        Set-LogField 'OPTIONS_OK' '0'
        Set-LogField 'OPTIONS_NOT_FOUND' '10'
        Set-LogField 'MISSING_OPTIONS_LIST' 'all'
        Set-LogField 'NEXT_CLICKED' 'non'
        Set-LogField 'RESULT' 'no_window'
        Write-LiveStatus 'Fenetre NVCleanstall introuvable.'
        exit 9
    }
    Set-NvcForeground $win
    Set-LogField 'NVCLEANSTALL_WINDOW_FOUND' 'oui'

    $optionStatuses = @{}
    $globalScrolls = 0
    $clickedCount = 0

    Set-LogField 'SHOW_EXPERT_FOUND' 'non'
    Set-LogField 'SHOW_EXPERT_CLICKED' 'non'
    Write-LiveStatus 'Application : Show Expert Tweaks'
    Set-LogField 'CURRENT_OPTION' 'Show Expert Tweaks'
    Set-LogField 'OPTION_FOUND' 'non'
    Set-LogField 'OPTION_CLICKED' 'non'
    Set-LogField 'OPTION_ALREADY_CHECKED' 'non'
    Set-LogField 'OPTION_NOT_FOUND_CONTINUED' 'non'
    $showState = Get-CheckBoxStateByAliases $win @('Show Expert Tweaks', 'Show Expert')
    if ($showState.Status -ne 'not_found') { Set-LogField 'SHOW_EXPERT_FOUND' 'oui' }
    $showExpertScrolls = 0
    $showR = Ensure-TweakCheckedByAliases $win @('Show Expert Tweaks', 'Show Expert') ([ref]$showExpertScrolls) 0
    $optionStatuses['Show Expert Tweaks'] = $showR
    switch ($showR) {
        'ok' {
            Set-LogField 'SHOW_EXPERT_CLICKED' 'oui'
            Set-LogField 'OPTION_FOUND' 'oui'
            Set-LogField 'OPTION_CLICKED' 'oui'
            $clickedCount++
        }
        'already_checked' {
            Set-LogField 'SHOW_EXPERT_CLICKED' 'oui'
            Set-LogField 'OPTION_FOUND' 'oui'
            Set-LogField 'OPTION_ALREADY_CHECKED' 'oui'
            $clickedCount++
        }
        default {
            Set-LogField 'SHOW_EXPERT_CLICKED' 'non'
            Set-LogField 'OPTION_NOT_FOUND_CONTINUED' 'oui'
        }
    }
    Start-Sleep -Milliseconds $script:TweakActionDelayMs

    Start-Sleep -Milliseconds 1000
    $win = Get-NvcRootWindow
    Set-NvcForeground $win
    $blob = Get-TextBlob $win
    $ctrlCount = Get-DescendantCount $win
    Set-LogField 'RESCAN_AFTER_SHOW_EXPERT' 'oui'
    Set-LogField 'CONTROLS_COUNT_AFTER_RESCAN' ([string]$ctrlCount)
    Set-LogField 'TEXT_AFTER_RESCAN_FOUND' $(if ($blob -and $blob.Length -gt 40) { 'oui' } else { 'non' })

    $tweakDefs = @(
        @{ Name = 'Disable Installer Telemetry & Advertising'; Aliases = @('Disable Installer Telemetry & Advertising', 'Disable Installer Telemetry', 'Installer Telemetry', 'Telemetry & Advertising') },
        @{ Name = 'Perform a Clean Installation'; Aliases = @('Perform a Clean Installation', 'Clean Installation') },
        @{ Name = 'Disable Multiplane Overlay (MPO)'; Aliases = @('Disable Multiplane Overlay (MPO)', 'Disable Multiplane Overlay', 'Multiplane Overlay', 'MPO') },
        @{ Name = 'Disable Ansel'; Aliases = @('Disable Ansel', 'Ansel') },
        @{ Name = 'Disable Driver Telemetry'; Aliases = @('Disable Driver Telemetry', 'Driver Telemetry') },
        @{ Name = 'Enable Message Signaled Interrupts'; Aliases = @('Enable Message Signaled Interrupts', 'Message Signaled Interrupts', 'MSI') },
        @{ Name = 'Disable HDCP'; Aliases = @('Disable HDCP', 'HDCP') }
    )

    $attemptedCount = 1
    foreach ($def in $tweakDefs) {
        $win = Get-NvcRootWindow
        if (-not $win) { break }
        Set-NvcForeground $win
        $r = Apply-TweakOption $win $def.Name $def.Aliases ([ref]$globalScrolls) ([ref]$clickedCount) ([ref]$attemptedCount)
        $optionStatuses[$def.Name] = $r
    }

    Apply-BottomPageTweaks ([ref]$globalScrolls) ([ref]$clickedCount) ([ref]$optionStatuses) ([ref]$attemptedCount)

    while ($globalScrolls -lt $script:MaxGlobalScrolls) {
        $win = Get-NvcRootWindow
        if (-not $win) { break }
        $needRetry = $false
        foreach ($def in $tweakDefs) {
            $st = $optionStatuses[$def.Name]
            if ($st -eq 'ok' -or $st -eq 'already_checked') { continue }
            $cs = Get-CheckBoxStateByAliases $win $def.Aliases
            if ($cs.Status -eq 'unchecked' -or $cs.Status -eq 'not_found') { $needRetry = $true; break }
        }
        if (-not $needRetry) { break }
        if (-not (Invoke-ScrollDown $win)) { break }
        $globalScrolls++
        Set-LogField 'SCROLL_USED' 'oui'
        Start-Sleep -Milliseconds 500
        $win = Get-NvcRootWindow
        Set-NvcForeground $win
        foreach ($def in $tweakDefs) {
            $st = $optionStatuses[$def.Name]
            if ($st -eq 'ok' -or $st -eq 'already_checked') { continue }
            Write-LiveStatus ('Application : ' + (Get-TweakStatusLabel $def.Name))
            Set-LogField 'CURRENT_OPTION' $def.Name
            $r2 = Ensure-TweakCheckedByAliases $win $def.Aliases ([ref]$globalScrolls) $script:MaxGlobalScrolls
            if ($r2 -eq 'ok' -or $r2 -eq 'already_checked') {
                $optionStatuses[$def.Name] = $r2
                $clickedCount++
            }
            Start-Sleep -Milliseconds $script:TweakActionDelayMs
        }
    }

    $allNames = @('Show Expert Tweaks') + @($tweakDefs | ForEach-Object { $_.Name }) + @(
        'Use method compatible with Easy Anti-Cheat',
        'Automatically accept the driver unsigned warning'
    )
    $optionsOk = 0
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($name in $allNames) {
        $st = $optionStatuses[$name]
        if ($st -eq 'ok' -or $st -eq 'already_checked') {
            $optionsOk++
        } else {
            $missing.Add($name) | Out-Null
        }
    }

    Set-LogField 'TOTAL_OPTIONS_REQUESTED' '10'
    Set-LogField 'OPTIONS_OK' ([string]$optionsOk)
    Set-LogField 'OPTIONS_NOT_FOUND' ([string]$missing.Count)
    Set-LogField 'MISSING_OPTIONS_LIST' $(if ($missing.Count -gt 0) { ($missing -join ' | ') } else { '' })
    Set-LogField 'TWEAKS_ATTEMPTED_COUNT' ([string]$attemptedCount)
    Set-LogField 'TWEAKS_CLICKED_COUNT' ([string]$clickedCount)
    Set-LogField 'NEXT_CLICKED' 'non'
    Set-LogField 'RESULT' $(if ($optionsOk -eq 10) { 'tweaks_all_ok' } elseif ($optionsOk -gt 0) { 'tweaks_partial' } else { 'no_options_clicked' })
    Write-LiveStatus 'Application des reglages NVIDIA terminee.'
    if ($optionsOk -eq 0) { exit 10 }
    exit 0
}

function Invoke-NvcClickNextSafe(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$forbidden
) {
    if (-not $root) { return $false }
    $btnType = [System.Windows.Automation.ControlType]::Button
    $patterns = @('^Next$', '^&Next$', '^Suivant$', '^&Suivant$')
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
    foreach ($btn in $all) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            if (Test-ButtonNameForbidden $n $forbidden) { continue }
            $matched = $false
            foreach ($p in $patterns) {
                if ($n -match $p) { $matched = $true; break }
            }
            if (-not $matched) { continue }
            Set-LogField 'NEXT_BUTTON_FOUND' 'oui'
            Scroll-ElementIntoView $btn | Out-Null
            Start-Sleep -Milliseconds 200
            if (SafeInvokeElement $btn $n) { return $true }
        } catch {}
    }
    return $false
}

function Click-NextButtonVisible(
    [System.Windows.Automation.AutomationElement]$root,
    [string[]]$forbidden
) {
    if (-not $root) { return $false }
    Set-LogField 'NEXT_BUTTON_FOUND' 'non'
    if (Invoke-NvcClickNextSafe $root $forbidden) { return $true }
    $btnType = [System.Windows.Automation.ControlType]::Button
    $patterns = @('^Next$', '^&Next$', '^Suivant$', '^&Suivant$')
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
    foreach ($btn in $all) {
        try {
            $n = [string]$btn.Current.Name
            if (-not $n) { continue }
            if (Test-ButtonNameForbidden $n $forbidden) { continue }
            $matched = $false
            foreach ($p in $patterns) {
                if ($n -match $p) { $matched = $true; break }
            }
            if (-not $matched) { continue }
            Set-LogField 'NEXT_BUTTON_FOUND' 'oui'
            Scroll-ElementIntoView $btn | Out-Null
            Start-Sleep -Milliseconds 200
            if (Invoke-Element $btn) { return $true }
        } catch {}
    }
    if (Click-ButtonByPatterns $root $patterns $forbidden) {
        Set-LogField 'NEXT_BUTTON_FOUND' 'oui'
        return $true
    }
    return $false
}

function Reset-NvcAutomationFlags {
    $script:hasClickedNVCleanstallDriverVersionNext = $false
    $script:hasClickedNVCleanstallComponentsNext = $false
    $script:hasClickedNVCleanstallTweaksNext = $false
    $script:hasTriggeredNVCleanstallInstall = $false
    $script:isNVCleanstallAutomationRunning = $true
    $script:NvcLastActionUtc = $null
    $script:NvcLastNextClickUtc = [DateTime]::MinValue
    $script:NvcWindowFirstSeenUtc = $null
    $script:NvcAntiBlockDumpDone = $false
    $script:NvcLoopBlocked = $false
}

function Test-NvcAutomationWindowTitle([string]$title) {
    if (-not $title) { return $false }
    return ($title -match '(?i)NVCleanstall|NVCleanInstall|TechPowerUp')
}

function Test-NvcAutomationElementEnabled([System.Windows.Automation.AutomationElement]$el) {
    if (-not $el) { return $false }
    try {
        return [bool]$el.Current.IsEnabled
    } catch {
        return $true
    }
}

function Get-NvcVisibleButtonNames([System.Windows.Automation.AutomationElement]$win) {
    $names = New-Object System.Collections.Generic.List[string]
    if (-not $win) { return @() }
    $btnType = [System.Windows.Automation.ControlType]::Button
    try {
        $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
        foreach ($btn in $all) {
            try {
                $n = [string]$btn.Current.Name
                if (-not $n) { continue }
                $en = if (Test-NvcAutomationElementEnabled $btn) { 'enabled' } else { 'disabled' }
                $names.Add(("{0} ({1})" -f $n, $en)) | Out-Null
            } catch {}
        }
    } catch {}
    return @($names)
}

function Find-NvcEnabledNextButton(
    [System.Windows.Automation.AutomationElement]$win,
    [string[]]$forbidden
) {
    if (-not $win) { return $null }
    $btnType = [System.Windows.Automation.ControlType]::Button
    $patterns = @('^Next$', '^&Next$', '^Suivant$', '^&Suivant$')
    try {
        $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)))
        foreach ($btn in $all) {
            try {
                $n = [string]$btn.Current.Name
                if (-not $n) { continue }
                if (Test-ButtonNameForbidden $n $forbidden) { continue }
                $matched = $false
                foreach ($p in $patterns) {
                    if ($n -match $p) { $matched = $true; break }
                }
                if (-not $matched) { continue }
                if (Test-NvcAutomationElementEnabled $btn) { return $btn }
            } catch {}
        }
    } catch {}
    return $null
}

function Invoke-NvcClickNextOnWindow(
    [System.Windows.Automation.AutomationElement]$win,
    [string[]]$forbidden
) {
    if (-not $win) { return $false }
    if (-not (Test-NvcAutomationWindowTitle ([string]$win.Current.Name))) { return $false }
    Set-NvcForeground $win
    Start-Sleep -Milliseconds 100
    if (Click-NextButtonVisible $win $forbidden) { return $true }
    return (Invoke-NvcClickNextSelectDriverFallback $win)
}

function Invoke-NvcDriverVersionPageAction(
    [System.Windows.Automation.AutomationElement]$win,
    [string[]]$forbidden
) {
    if ($script:hasClickedNVCleanstallDriverVersionNext) { return $false }
    $blob = Get-TextBlob $win
    if (-not (Test-NvcSelectDriverVersionPage $blob)) { return $false }

    Write-LiveStatus '[NVCleanstall] Page Driver Version détectée.'
    if (Invoke-NvcClickNextOnWindow $win $forbidden) {
        Write-LiveStatus '[NVCleanstall] Next cliqué.'
        $script:hasClickedNVCleanstallDriverVersionNext = $true
        $script:NvcLastActionUtc = [DateTime]::UtcNow
        $script:NvcLastNextClickUtc = [DateTime]::UtcNow
        Start-Sleep -Milliseconds 500
        return $true
    }
    return $false
}

function Invoke-NvcIntermediateNextAction(
    [System.Windows.Automation.AutomationElement]$win,
    [string[]]$forbidden,
    [string]$blob
) {
    if ($script:hasTriggeredNVCleanstallInstall) { return $false }
    if (Test-NvcPackageReadyText $blob) { return $false }
    if (Test-NvcSelectDriverVersionPage $blob) { return $false }

    $sinceNextMs = [int](([DateTime]::UtcNow - $script:NvcLastNextClickUtc).TotalMilliseconds)
    if ($sinceNextMs -ge 0 -and $sinceNextMs -lt 500) { return $false }

    if (-not (Find-NvcEnabledNextButton $win $forbidden)) { return $false }

    if ($blob -match '(?i)SELECT COMPONENTS TO INSTALL|SELECT COMPONENTS') {
        Confirm-DisplayDriverRequired $win
    }

    Write-LiveStatus '[NVCleanstall] Page intermédiaire détectée, Next cliqué.'
    if (-not (Invoke-NvcClickNextOnWindow $win $forbidden)) { return $false }

    if ($blob -match '(?i)SELECT COMPONENTS') {
        $script:hasClickedNVCleanstallComponentsNext = $true
    }
    if ($blob -match '(?i)INSTALLATION TWEAKS|RECOMMENDED TWEAKS') {
        $script:hasClickedNVCleanstallTweaksNext = $true
    }

    $script:NvcLastActionUtc = [DateTime]::UtcNow
    $script:NvcLastNextClickUtc = [DateTime]::UtcNow
    Start-Sleep -Milliseconds 500
    return $true
}

function Invoke-NvcAntiBlockageFallback(
    [System.Windows.Automation.AutomationElement]$win,
    [string[]]$forbidden
) {
    if (-not $win) { return $false }
    $blob = Get-TextBlob $win
    $btnNames = Get-NvcVisibleButtonNames $win
    $textSnippet = $blob
    if ($textSnippet.Length -gt 1200) { $textSnippet = $textSnippet.Substring(0, 1200) }
    Write-LiveStatus ("[NVCleanstall] Aucun état reconnu, dump UIA : " + ($textSnippet -replace "`r?`n", ' | '))
    Write-LiveStatus ("[NVCleanstall] Boutons détectés : " + ($btnNames -join ', '))

    if (Find-NvcEnabledNextButton $win $forbidden) {
        if (Invoke-NvcClickNextOnWindow $win $forbidden) {
            Write-LiveStatus '[NVCleanstall] Fallback : Next visible cliqué.'
            $script:NvcLastActionUtc = [DateTime]::UtcNow
            $script:NvcLastNextClickUtc = [DateTime]::UtcNow
            Start-Sleep -Milliseconds 500
            return $true
        }
    }

    if (Test-NvcPackageReadyText $blob) {
        if (Invoke-NvcPackageReadyDownEnter $win) {
            Write-LiveStatus '[NVCleanstall] Fallback final : clavier envoyé.'
            return $true
        }
    }

    Write-LiveStatus 'NVCleanstall ouvert mais page non reconnue'
    Write-LiveStatus '[NVCleanstall] Blocage détecté, intervention manuelle nécessaire.'
    $script:NvcLoopBlocked = $true
    return $false
}

function Run-NVCleanstallAutomationLoop([string[]]$forbidden) {
    if (-not $forbidden) {
        $forbidden = @('RESTART', 'REDEMARR', 'SHUTDOWN', 'REBOOT', 'ÉTEINDRE', 'CANCEL', 'BACK', 'ANNULER', 'RETOUR', 'REDEMARRER')
    }
    Reset-NvcAutomationFlags
    Write-LiveStatus '[NVCleanstall] Automatisation démarrée.'
    $loopStart = [DateTime]::UtcNow
    $deadline = $loopStart.AddSeconds(180)
    $windowLogged = $false

    while ((Get-Date) -lt $deadline -and $script:isNVCleanstallAutomationRunning) {
        $win = Get-NvcRootWindow
        if (-not $win) {
            Start-Sleep -Milliseconds $script:WorkflowPollMs
            continue
        }

        if (-not $windowLogged) {
            Write-LiveStatus '[NVCleanstall] Fenêtre détectée.'
            $windowLogged = $true
            $script:NvcWindowFirstSeenUtc = [DateTime]::UtcNow
        }

        if (-not (Test-NvcAutomationWindowTitle ([string]$win.Current.Name))) {
            Start-Sleep -Milliseconds $script:WorkflowPollMs
            continue
        }

        $blob = Get-TextBlob $win

        if (Test-NvcPackageReadyText $blob) {
            if (Invoke-NvcPackageReadyDownEnter $win) {
                Write-LiveStatus '[NVCleanstall] Flèche bas + Entrée envoyé.'
                Write-LiveStatus '[NVCleanstall] Automatisation terminée.'
                Set-LogField 'RESULT' 'install_triggered'
                Set-LogField 'STEP_1_NEXT' 'oui'
                Set-LogField 'STEP_2_NEXT' 'oui'
                return 'install_triggered'
            }
        }

        if (Invoke-NvcDriverVersionPageAction $win $forbidden) {
            Start-Sleep -Milliseconds $script:WorkflowPollMs
            continue
        }

        if (Invoke-NvcIntermediateNextAction $win $forbidden $blob) {
            Start-Sleep -Milliseconds $script:WorkflowPollMs
            continue
        }

        if ($script:NvcWindowFirstSeenUtc -and -not $script:NvcAntiBlockDumpDone) {
            $idleMs = if ($script:NvcLastActionUtc) {
                [int](([DateTime]::UtcNow - $script:NvcLastActionUtc).TotalMilliseconds)
            } else {
                [int](([DateTime]::UtcNow - $script:NvcWindowFirstSeenUtc).TotalMilliseconds)
            }
            if ($idleMs -ge 5000) {
                Invoke-NvcAntiBlockageFallback $win $forbidden | Out-Null
                $script:NvcAntiBlockDumpDone = $true
                if ($script:NvcLoopBlocked) { break }
            }
        }

        Start-Sleep -Milliseconds $script:WorkflowPollMs
    }

    if ($script:hasTriggeredNVCleanstallInstall) {
        Write-LiveStatus '[NVCleanstall] Automatisation terminée.'
        Set-LogField 'RESULT' 'install_triggered'
        return 'install_triggered'
    }

    Write-LiveStatus '[NVCleanstall] Timeout ou blocage détecté.'
    $script:isNVCleanstallAutomationRunning = $false
    if ($script:NvcLoopBlocked) {
        Set-LogField 'RESULT' 'nvc_blocked'
        return 'blocked'
    }
    Set-LogField 'RESULT' 'nvc_loop_timeout'
    return 'timeout'
}

function Test-NvcSelectDriverVersionPage([string]$blob) {
    if (-not $blob) { return $false }
    if (Test-PageContains $blob @('SELECT DRIVER VERSION TO INSTALL')) { return $true }
    if (Test-PageContains $blob @('INSTALL BEST DRIVER FOR MY HARDWARE', 'BEST DRIVER FOR MY HARDWARE')) {
        return $true
    }
    return $false
}

function Test-NvcBlockingDriverUpdateWarning([string]$blob) {
    if (-not $blob) { return $false }
    return ($blob -match '(?i)blocking automatic driver update')
}

function Test-NvcBestDriverRadioAlreadySelected([System.Windows.Automation.AutomationElement]$root) {
    if (-not $root) { return $false }
    $patterns = @(
        'Install best driver for my hardware',
        'INSTALL BEST DRIVER FOR MY HARDWARE'
    )
    $rbType = [System.Windows.Automation.ControlType]::RadioButton
    $el = Find-ElementByNameMatch $root $patterns @($rbType)
    if (-not $el) {
        $el = Find-ElementByNameMatch $root $patterns @(
            [System.Windows.Automation.ControlType]::ListItem
        )
    }
    if (-not $el) { return $false }
    try {
        $sel = $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($sel) { return $sel.Current.IsSelected }
    } catch {}
    return $false
}

function Invoke-NvcClickNextSelectDriverFallback([System.Windows.Automation.AutomationElement]$win) {
    if (-not $win) { return $false }
    Write-BlockedUnsafeClick 'ClickFromEdges(85,28) bord de fenêtre'
    Write-LiveStatus '[NVCleanstall] Fallback coordonnées désactivé pour sécurité.'
    Write-NvcManualUiRequired 'driver_version_next'
    return $false
}

function Invoke-NvcSelectDriverVersionNext([System.Windows.Automation.AutomationElement]$win, [string[]]$forbidden) {
    if (-not $win) { return $false }
    try {
        $title = [string]$win.Current.Name
        if ($title -notmatch '(?i)NVCleanstall|NVCleanInstall|TechPowerUp') { return $false }
    } catch {
        return $false
    }

    $blob = Get-TextBlob $win
    if (-not (Test-NvcSelectDriverVersionPage $blob)) { return $false }

    Write-LiveStatus '[NVCLEANSTALL] Select driver version page detected'
    Write-LiveStatus '[NVCleanstall] Page Driver Version détectée.'

    if (Test-NvcBestDriverRadioAlreadySelected $win) {
        Write-LiveStatus '[NVCLEANSTALL] Best driver already selected'
    }

    Set-NvcForeground $win
    Start-Sleep -Milliseconds 200

    if (Invoke-NvcClickNextSafe $win $forbidden) {
        Write-LiveStatus '[SAFE-UIA] Invoked button Next'
        Write-LiveStatus '[NVCleanstall] Next cliqué.'
        Write-TimingLog 'Action suivante immédiate' -1
        return $true
    }
    if (Click-NextButtonVisible $win $forbidden) {
        Write-LiveStatus '[SAFE-UIA] Invoked button Next'
        Write-LiveStatus '[NVCleanstall] Next cliqué.'
        Write-TimingLog 'Action suivante immédiate' -1
        return $true
    }
    if (Invoke-NvcClickNextSelectDriverFallback $win) {
        Write-LiveStatus '[NVCleanstall] Next cliqué.'
        Set-LogField 'STEP_1_NEXT' 'relative_fallback'
        return $true
    }
    Write-NvcManualUiRequired 'driver_version_next'
    return $false
}

if ($Phase -eq 'next') {
    $win = Get-NvcRootWindow
    if (-not $win) { $win = Wait-NvcWindow 10 }
    $nextOk = $false
    if ($win) {
        Set-NvcForeground $win
        Start-Sleep -Milliseconds 300
        $blob = Get-TextBlob $win
        if (Test-ForbiddenVisible $blob) {
            Set-LogField 'NEXT_BUTTON_FOUND' 'non'
            Set-LogField 'NEXT_CLICKED' 'non'
            Set-LogField 'RESULT' 'dangerous_prompt_visible'
            exit 7
        }
        foreach ($s in 1..2) { Invoke-ScrollDown $win | Out-Null; Start-Sleep -Milliseconds 150 }
        Set-LogField 'NEXT_BUTTON_TEXT_FOUND' 'non'
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline) {
            $win = Get-NvcRootWindow
            if (-not $win) { break }
            Set-NvcForeground $win
            if (Click-NextButtonVisible $win $forbiddenBtn) {
                Set-LogField 'NEXT_BUTTON_TEXT_FOUND' 'oui'
                $nextOk = $true
                break
            }
            Start-Sleep -Milliseconds 500
        }
    }
    if ($nextOk) {
        Set-LogField 'NEXT_CLICKED_BY_CONTROL' 'oui'
    }
    Set-LogField 'NEXT_CLICKED' $(if ($nextOk) { 'oui' } else { 'non' })
    Set-LogField 'RESULT' $(if ($nextOk) { 'next_ok' } else { 'next_missing' })
    if ($nextOk) { exit 0 }
    exit 11
}

if ($Phase -eq 'install-only') {
    Set-LogField 'INSTALL_BUTTON_FOUND' 'non'
    Set-LogField 'INSTALL_BUTTON_CLICKED' 'non'
    Set-LogField 'INSTALL_CLICKED' 'non'
    $win = Get-NvcRootWindow
    if (-not $win) {
        Set-LogField 'RESULT' 'install_button_missing'
        exit 13
    }
    if (Invoke-NvcClickInstallButton $win $forbiddenBtn) {
        Set-LogField 'RESULT' 'install_started'
        Write-LiveStatus 'Installation du pilote lancee.'
        exit 0
    }
    $blob = Get-TextBlob $win
    if (Test-PageContains $blob @('FINISHED', 'YOUR CUSTOMIZED INSTALLER', 'PLEASE CHOOSE THE NEXT ACTION')) {
        Write-SafeClickBlocked 'install-only 0.17/0.58'
        Write-LiveStatus '[NVCleanstall] Fallback coordonnées désactivé pour sécurité.'
        Write-NvcManualUiRequired 'install_only_phase'
    }
    Set-LogField 'RESULT' 'install_button_missing'
    Write-LiveStatus 'Bouton Install introuvable. Clique manuellement.'
    exit 13
}

if ($Phase -eq 'finished-install' -or $Phase -eq 'package-ready-install') {
    Set-LogField 'FINISHED_INSTALL_AUTO' 'oui'
    Set-LogField 'INSTALL_BUTTON_FOUND' 'non'
    Set-LogField 'INSTALL_BUTTON_CLICKED' 'non'
    Set-LogField 'INSTALL_CLICKED' 'non'
    if (-not (Wait-NvcWindow 30)) {
        Set-LogField 'RESULT' 'nvc_window_missing'
        Write-LiveStatus 'Fenetre NVCleanstall introuvable.'
        exit 14
    }
    if (Invoke-NvcPackageReadyDetectionAndInstall 180) {
        exit 0
    }
    Set-LogField 'RESULT' 'install_launch_failed'
    Write-LiveStatus 'Install non lance automatiquement — action manuelle requise.'
    exit 13
}

if ($Phase -eq 'nvidia-installer-tick') {
    $tick = Invoke-NvidiaInstallerWizardTick
    switch ($tick) {
        'finished' { exit 0 }
        'installing' { exit 0 }
        'manual' { exit 16 }
        default { exit 0 }
    }
}

if ($Phase -eq 'nvidia-wizard') {
    Clear-NvidiaInstallerLoopState
    $script:hasClickedCustomAdvancedNvidiaInstaller = $false
    $script:hasCompletedNvidiaInstallOptionsPage = $false
    $script:hasCompletedNvidiaCustomOptionsPage = $false
    Set-LogField 'NVIDIA_WIZARD_STARTED' 'oui'
    Write-LiveStatus 'Lancement du programme d''installation NVIDIA...'
    Set-LogField 'NV_PROGRESS_PCT' '80'

    $wizardDeadline = (Get-Date).AddSeconds(300)
    $lastTick = 'continue'
    while ((Get-Date) -lt $wizardDeadline) {
        $lastTick = Invoke-NvidiaInstallerWizardTick
        if ($lastTick -eq 'finished') {
            Set-NvidiaInstallerProgressComplete
            Write-LiveStatus '[NVIDIA Installer] Fin détectée, reprise vérification pilote.'
            Set-LogField 'RESULT' 'nvidia_wizard_launched'
            exit 0
        }
        if ($lastTick -eq 'installing') {
            Set-LogField 'NV_PROGRESS_PCT' '95'
            Set-LogField 'AWAIT_DRIVER_DETECTION' 'oui'
            Set-LogField 'RESULT' 'nvidia_wizard_launched'
            exit 0
        }
        if ($lastTick -eq 'manual') {
            Set-LogField 'RESULT' 'nvidia_wizard_manual'
            Set-LogField 'AWAIT_DRIVER_DETECTION' 'oui'
            exit 16
        }
        Start-Sleep -Milliseconds $script:WorkflowPollMs
    }

    if ($lastTick -eq 'installing' -or $script:hasCompletedNvidiaCustomOptionsPage) {
        Set-LogField 'AWAIT_DRIVER_DETECTION' 'oui'
        Set-LogField 'RESULT' 'nvidia_wizard_partial'
        Write-LiveStatus 'Installation NVIDIA en cours...'
        exit 0
    }

    Set-LogField 'RESULT' 'nvidia_wizard_incomplete'
    Write-LiveStatus 'Installation NVIDIA non confirmee automatiquement — verifiez la fenetre NVIDIA.'
    Set-LogField 'AWAIT_DRIVER_DETECTION' 'oui'
    exit 16
}

if ($Phase -eq 'finished') {
    Set-LogField 'FINISHED_PAGE_FOUND' 'non'
    Set-LogField 'INSTALL_BUTTON_FOUND' 'non'
    Set-LogField 'INSTALL_BUTTON_CLICKED' 'non'
    Set-LogField 'INSTALL_CLICKED' 'non'
    $finishedFound = $false
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        $win = Get-NvcRootWindow
        if (-not $win) { Start-Sleep -Milliseconds 500; continue }
        Set-NvcForeground $win
        $blob = Get-TextBlob $win
        if (Test-ForbiddenVisible $blob) {
            Set-LogField 'RESULT' 'dangerous_prompt_visible'
            Write-LiveStatus 'Validation finale NVCleanstall requise.'
            exit 7
        }
        if (Test-PageContains $blob @('FINISHED', 'INSTALLATION READY', 'READY TO INSTALL')) {
            $finishedFound = $true
            Set-LogField 'FINISHED_PAGE_FOUND' 'oui'
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $finishedFound) {
        Set-LogField 'RESULT' 'finished_page_timeout'
        Write-LiveStatus 'Bouton Install introuvable. Clique manuellement.'
        exit 12
    }
    $win = Get-NvcRootWindow
    if (-not $win) {
        Write-LiveStatus 'Bouton Install introuvable. Clique manuellement.'
        exit 12
    }
    if (Invoke-NvcClickInstallButton $win $forbiddenBtn) {
        Set-LogField 'RESULT' 'install_started'
        Write-LiveStatus 'Installation du pilote lancee.'
        exit 0
    }
    Set-LogField 'RESULT' 'install_button_missing'
    Write-LiveStatus 'Bouton Install introuvable. Clique manuellement.'
    exit 13
}

if ($Phase -eq 'postinstall') {
    $installClicked = $false
    $deadline = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $deadline) {
        $win = Get-NvcRootWindow
        if (-not $win) { break }
        $blob = Get-TextBlob $win
        if (Test-ForbiddenVisible $blob) {
            Set-LogField 'RESULT' 'dangerous_prompt_visible'
            Write-LiveStatus 'Validation finale NVCleanstall requise.'
            exit 7
        }
        if (Click-ButtonByPatterns $win @('^Install Driver$', '^Install$', '^Build Package$') $forbiddenBtn) {
            $installClicked = $true
            Set-LogField 'INSTALL_STARTED' 'oui'
            Write-LiveStatus 'Installation lancée.'
            break
        }
        if (Click-ButtonByPatterns $win @('^Next$', '^&Next$') $forbiddenBtn) {
            Set-LogField 'FINAL_NEXT_CLICKED' 'oui'
            Start-Sleep -Milliseconds 600
        }
        Start-Sleep -Milliseconds 500
    }
    if ($installClicked) {
        Set-LogField 'RESULT' 'ok'
        exit 0
    }
    Set-LogField 'INSTALL_STARTED' 'non'
    Set-LogField 'RESULT' 'partial'
    Write-LiveStatus 'Validation finale NVCleanstall requise.'
    exit 8
}

function Run-NVCleanstallWizardSimple([string[]]$forbidden) {
    Write-LiveStatus '[ROLLBACK] NVCleanstall restauré à la dernière version stable.'
    Write-LiveStatus '[NVCleanstall] Automatisation démarrée.'
    $wizardStart = [DateTime]::UtcNow
    $win = Wait-NvcWindow 15
    if (-not $win) {
        Write-LiveStatus '[NVCleanstall] Timeout ou blocage détecté.'
        Set-LogField 'WINDOW_FOUND' 'non'
        Set-LogField 'RESULT' 'window_timeout'
        return 3
    }
    Write-LiveStatus '[NVCleanstall] Fenêtre détectée.'
    $timingWinMs = [int](([DateTime]::UtcNow - $wizardStart).TotalMilliseconds)
    Write-LiveStatus ("[NVCleanstall Timing] Fenêtre détectée en ${timingWinMs} ms.")

    $step1Done = $false
    $step2Done = $false
    $lastNextUtc = [DateTime]::MinValue
    $deadline = (Get-Date).AddSeconds(120)

    while ((Get-Date) -lt $deadline) {
        $win = Get-NvcRootWindow
        if (-not $win) {
            Start-Sleep -Milliseconds $script:WorkflowPollMs
            continue
        }
        $blob = Get-TextBlob $win

        if ($blob -match '(?i)Preparing source|Copying install|Extracting|Progress') {
            Set-LogField 'STEP_1_NEXT' $(if ($step1Done) { 'oui' } else { 'oui' })
            Set-LogField 'STEP_2_NEXT' $(if ($step2Done) { 'oui' } else { 'oui' })
            Set-LogField 'PREPARING_SOURCE' 'oui'
            Set-LogField 'RESULT' 'preparing_source'
            Write-LiveStatus 'Preparation des fichiers NVIDIA...'
            return 0
        }

        if (Test-NvcPackageReadyText $blob) {
            Set-LogField 'RESULT' 'package_ready_early'
            return 0
        }

        if (-not $step1Done) {
            if (Test-NvcSelectDriverVersionPage $blob) {
                $t0 = [DateTime]::UtcNow
                if (Invoke-NvcSelectDriverVersionNext $win $forbidden) {
                    $step1Done = $true
                    Set-LogField 'STEP_1_NEXT' 'oui'
                    $lastNextUtc = [DateTime]::UtcNow
                    $step1Ms = [int](([DateTime]::UtcNow - $t0).TotalMilliseconds)
                    Write-LiveStatus ("[NVCleanstall Timing] Page Driver Version traitée en ${step1Ms} ms.")
                    Start-Sleep -Milliseconds 500
                    continue
                }
            }
        }

        if ($step1Done -and -not $step2Done) {
            $sinceMs = [int](([DateTime]::UtcNow - $lastNextUtc).TotalMilliseconds)
            if ($lastNextUtc -ne [DateTime]::MinValue -and $sinceMs -ge 0 -and $sinceMs -lt 500) {
                Start-Sleep -Milliseconds $script:WorkflowPollMs
                continue
            }
            if ($blob -match '(?i)SELECT COMPONENTS') {
                Confirm-DisplayDriverRequired $win
                Set-NvcForeground $win
                Start-Sleep -Milliseconds 200
                if (Click-NextButtonVisible $win $forbidden) {
                    Write-LiveStatus '[NVCleanstall] Page intermédiaire détectée, Next cliqué.'
                    $step2Done = $true
                    Set-LogField 'STEP_2_NEXT' 'oui'
                    $lastNextUtc = [DateTime]::UtcNow
                    $clickMs = [int](([DateTime]::UtcNow - $wizardStart).TotalMilliseconds)
                    Write-LiveStatus ("[NVCleanstall Timing] Composants Next cliqué en ${clickMs} ms.")
                    Start-Sleep -Milliseconds 500
                    continue
                }
            }
            if ($blob -match '(?i)INSTALLATION TWEAKS|RECOMMENDED TWEAKS') {
                $step2Done = $true
                Set-LogField 'STEP_2_NEXT' 'oui'
            }
        }

        if ($step1Done -and $step2Done) {
            Set-LogField 'STEP_1_NEXT' 'oui'
            Set-LogField 'STEP_2_NEXT' 'oui'
            Set-LogField 'RESULT' 'wizard_steps_ok'
            return 0
        }

        Start-Sleep -Milliseconds $script:WorkflowPollMs
    }

    Write-LiveStatus '[NVCleanstall] Timeout ou blocage détecté.'
    Set-LogField 'RESULT' 'wizard_timeout'
    return 16
}

if ($Phase -eq 'nvcleanstall-loop') {
    Write-LiveStatus '[ROLLBACK] Phase nvcleanstall-loop redirigée vers wizard stable.'
    $wResult = Run-NVCleanstallWizardSimple $forbiddenBtn
    Set-LogField 'WINDOW_FOUND' $(if (Get-NvcRootWindow) { 'oui' } else { 'non' })
    exit $wResult
}

if ($Phase -eq 'wizard') {
    Set-LogField 'NVCLEANSTALL_WIZARD' 'oui'
    $wResult = Run-NVCleanstallWizardSimple $forbiddenBtn
    Set-LogField 'WINDOW_FOUND' $(if (Get-NvcRootWindow) { 'oui' } else { 'non' })
    exit $wResult
}

Write-LiveStatus 'Phase NVCleanstall non reconnue.'
Set-LogField 'RESULT' 'unknown_phase'
exit 99
