#Requires -Version 5.1
<#
.SYNOPSIS
  HIDUSBF link path — delegates to PnP present scan + merge (no registry ghost devices).
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$OutputPath = '',
    [string]$CachePath = '',
    [string]$FinalPath = ''
)

$ErrorActionPreference = 'SilentlyContinue'

$sync = Join-Path $PSScriptRoot 'Sync-ControllerDevices.ps1'
if (-not (Test-Path -LiteralPath $sync)) { exit 9 }

& $sync -AppRoot $AppRoot -LogPath $LogPath -AllowCacheHints

$app = $AppRoot
if (-not $app) {
    $here = $PSScriptRoot
    if ($here) { $app = Split-Path -Parent (Split-Path -Parent $here) }
}
$final = if ($FinalPath) { $FinalPath } else { Join-Path $app 'logs\controller-devices-final.json' }
$out = if ($OutputPath) { $OutputPath } else { Join-Path $app 'logs\controller-devices-hidusbf-link.json' }

if ((Test-Path -LiteralPath $final) -and $out -and ($final -ne $out)) {
    Copy-Item -LiteralPath $final -Destination $out -Force -ErrorAction SilentlyContinue
}
exit 0
