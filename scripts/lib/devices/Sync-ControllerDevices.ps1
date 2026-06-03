#Requires -Version 5.1
<#
.SYNOPSIS
  Fast sync: PnP present scan + merge/dedupe (normal path). No Win32 full scan.
#>
param(
    [string]$AppRoot = '',
    [string]$LogPath = '',
    [string]$LinkPath = '',
    [switch]$AllowCacheHints
)

$ErrorActionPreference = 'SilentlyContinue'

$app = $AppRoot
if (-not $app -or -not (Test-Path -LiteralPath $app)) {
    $here = $PSScriptRoot
    if ($here) {
        $c = Split-Path -Parent (Split-Path -Parent $here)
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'Unreal.hta'))) { $app = $c }
    }
}
if (-not $LogPath -and $app) { $LogPath = Join-Path $app 'logs\controller-overclocker.log' }

$presentScript = Join-Path $PSScriptRoot 'Get-ControllerPresentDevices.ps1'
$mergeScript = Join-Path $PSScriptRoot 'Merge-ControllerDevices.ps1'
$presentPath = if ($app) { Join-Path $app 'logs\controller-devices-present.json' } else { '' }
$finalPath = if ($app) { Join-Path $app 'logs\controller-devices-final.json' } else { '' }
$cachePath = if ($app) { Join-Path $app 'logs\controller-devices-cache.json' } else { '' }
$linkOut = if ($LinkPath) { $LinkPath } elseif ($app) { Join-Path $app 'logs\controller-devices-hidusbf-link.json' } else { '' }

& $presentScript -AppRoot $app -LogPath $LogPath -OutputPath $presentPath | Out-Null

$mergeParams = @{
    AppRoot      = $app
    LogPath      = $LogPath
    PresentPath  = $presentPath
    OutputPath   = $presentPath
    FinalPath    = $finalPath
}
if ($AllowCacheHints -and $cachePath) { $mergeParams.CachePath = $cachePath }
if ($linkOut -and (Test-Path -LiteralPath $linkOut)) { $mergeParams.LinkPath = $linkOut }

& $mergeScript @mergeParams | Out-Null
exit 0
