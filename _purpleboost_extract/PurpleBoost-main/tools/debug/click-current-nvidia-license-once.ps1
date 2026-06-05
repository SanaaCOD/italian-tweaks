# One-shot: dump Win32 children on current NVIDIA installer root and click license Accept once.
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PurpleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LogsDir = Join-Path $PurpleRoot 'logs'
$DumpPath = Join-Path $LogsDir 'nvidia-license-current-win32-dump.txt'
$HelperCs = Join-Path $PurpleRoot 'Scripts\NvidiaWin32Msaa-helper.cs'

if (-not (Test-Path -LiteralPath $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

function Write-OneShotLog([string]$Message) {
    Write-Host $Message
}

if (-not (Test-Path -LiteralPath $HelperCs)) {
    Write-OneShotLog "[ONE-SHOT] Helper missing: $HelperCs"
    exit 1
}

try {
    if (-not ([System.Management.Automation.PSTypeName]'NvidiaWin32Msaa').Type) {
        Add-Type -Path $HelperCs -ErrorAction Stop | Out-Null
    }
} catch {
    Write-OneShotLog "[ONE-SHOT] Helper compile failed: $($_.Exception.Message)"
    exit 1
}

function Get-WindowTextBlob([IntPtr]$rootHwnd) {
    $parts = New-Object System.Collections.Generic.List[string]
    $rootTitle = [NvidiaWin32Msaa]::GetWndText($rootHwnd)
    if ($rootTitle) { $parts.Add($rootTitle) | Out-Null }
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if ($c.Text) { $parts.Add([string]$c.Text) | Out-Null }
    }
    return ($parts -join ' ')
}

function Test-LicensePageVisible([IntPtr]$rootHwnd) {
    $blob = Get-WindowTextBlob $rootHwnd
    if (-not $blob) { return $false }
    return ($blob -match '(?i)Contrat de licence|License Agreement|NVIDIA Driver License Agreement')
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

function Find-AcceptButtonInfo([IntPtr]$rootHwnd) {
    $needles = @('ACCEPTER', 'Accepter', 'Accept', 'CONTINUER', 'Continue')
    $needleNorms = @()
    foreach ($n in $needles) { $needleNorms += (Normalize-NeedleText $n) }

    $best = $null
    $bestLen = [int]::MaxValue
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        if (-not $c.Visible -or -not $c.Enabled) { continue }
        $text = if ($c.Text) { [string]$c.Text } else { '' }
        if (-not $text) { continue }
        $norm = Normalize-NeedleText $text
        $matched = $false
        foreach ($n in $needleNorms) {
            if ([string]::IsNullOrEmpty($n)) { continue }
            if ($norm.IndexOf($n, [System.StringComparison]::Ordinal) -ge 0) {
                $matched = $true
                break
            }
            if ($text.IndexOf($n, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $matched = $true
                break
            }
        }
        if ($matched -and $text.Length -le $bestLen) {
            $best = $c
            $bestLen = $text.Length
        }
    }
    return $best
}

function Write-Win32Dump([IntPtr]$rootHwnd, [string]$path) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))) | Out-Null
    $lines.Add('ROOT_HWND=' + $rootHwnd.ToInt64()) | Out-Null
    $lines.Add('ROOT_TITLE=' + [NvidiaWin32Msaa]::GetWndText($rootHwnd)) | Out-Null
    $lines.Add('ROOT_CLASS=' + [NvidiaWin32Msaa]::GetWndClass($rootHwnd)) | Out-Null
    $lines.Add('--- CHILDREN ---') | Out-Null
    foreach ($c in [NvidiaWin32Msaa]::EnumChildren($rootHwnd)) {
        $rect = "L$($c.Rect.Left),T$($c.Rect.Top),R$($c.Rect.Right),B$($c.Rect.Bottom)"
        $lines.Add(
            "HWND=$($c.Hwnd.ToInt64()) | className='$($c.ClassName)' | text='$($c.Text)' | visible=$($c.Visible) | enabled=$($c.Enabled) | rect=$rect | style=$($c.Style) | exStyle=$($c.ExStyle) | GetDlgCtrlID=$($c.ControlId)"
        ) | Out-Null
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
}

$rootHwnd = [NvidiaWin32Msaa]::FindNvidiaInstallerRootHwnd()
if ($rootHwnd -eq [IntPtr]::Zero) {
    Write-OneShotLog '[ONE-SHOT] NVIDIA installer top-level window not found (Programme d''installation NVIDIA / variants; NVCleanstall excluded)'
    exit 2
}

Write-Win32Dump $rootHwnd $DumpPath
Write-OneShotLog "[ONE-SHOT] Win32 dump written: $DumpPath"

$acceptInfo = Find-AcceptButtonInfo $rootHwnd
if (-not $acceptInfo) {
    Write-OneShotLog '[ONE-SHOT] Accept hwnd not found'
    exit 3
}

Write-OneShotLog "[ONE-SHOT] Accept hwnd found: HWND=$($acceptInfo.Hwnd.ToInt64()) text='$($acceptInfo.Text)' id=$($acceptInfo.ControlId) class='$($acceptInfo.ClassName)'"

[NvidiaWin32Msaa]::InvokeControlClick($acceptInfo.Hwnd, $rootHwnd)
Start-Sleep -Milliseconds 700

if (Test-LicensePageVisible $rootHwnd) {
    Write-OneShotLog '[ONE-SHOT] Accept click sent but license page still visible'
    exit 4
}

Write-OneShotLog '[ONE-SHOT] NVIDIA license accepted successfully'
exit 0
