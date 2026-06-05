#Requires -Version 5.1
<#
.SYNOPSIS
  Lightweight PnP-present signature only (no registry Enum ghosts).
#>
param(
    [string]$AppRoot = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Controller-Presence-Common.ps1')

function Test-IsControllerSigNode {
    param([string]$InstanceId, [string]$FriendlyName)
    if (-not $InstanceId -or $InstanceId -notmatch 'VID_') { return $false }
    if ($InstanceId -match '(?i)VID_054C') { return $true }
    $blob = $InstanceId + ' ' + $FriendlyName
    if ($InstanceId -match '(?i)VID_045E') {
        if ($blob -match '(?i)Xbox|XInput|game\s+controller|Contr.leur de jeu') { return $true }
        return $false
    }
    if ($InstanceId -match '(?i)MI_03' -and $InstanceId -match '(?i)VID_(054C|045E)') { return $true }
    if ($blob -match '(?i)DualSense|DualShock|Wireless\s+Controller|HID-compliant\s+game|game\s+controller|Contr.leur de jeu|Xbox|XInput|gamepad|joystick') {
        if ($blob -match '(?i)keyboard|mouse|souris|clavier') { return $false }
        return $true
    }
    return $false
}

$app = $AppRoot
if (-not $app -or -not (Test-Path -LiteralPath $app)) {
    $here = $PSScriptRoot
    if ($here) {
        $c = Split-Path -Parent (Split-Path -Parent $here)
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'Unreal.hta'))) { $app = $c }
    }
}
if (-not $OutputPath -and $app) {
    $OutputPath = Join-Path $app 'logs\controller-device-signature.json'
}

$parts = New-Object System.Collections.Generic.List[string]

if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
    foreach ($pd in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
        if (-not (Test-PnpStatusPresent ([string]$pd.Status))) { continue }
        $iid = (Normalize-DeviceInstanceId ([string]$pd.InstanceId)).ToUpperInvariant()
        if (-not $iid) { continue }
        if (-not (Test-IsControllerSigNode $iid ([string]$pd.FriendlyName))) { continue }
        $vp = $iid -match 'VID_([0-9A-F]{4}).*PID_([0-9A-F]{4})'
        $vid = if ($Matches) { $Matches[1] } else { '' }
        $productId = if ($Matches) { $Matches[2] } else { '' }
        $parts.Add(($vid + ':' + $productId + ':' + $iid)) | Out-Null
    }
}

$sorted = @($parts | Sort-Object -Unique)
$payload = [ordered]@{
    Success   = $true
    Signature = ($sorted -join '|')
    Count     = $sorted.Count
}

if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, ($payload | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
}
exit 0
