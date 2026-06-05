#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\_common\Kojo.Json.ps1')
. (Join-Path $PSScriptRoot '_Network-Paths.ps1')
Initialize-NetworkPaths -LogDir $LogDir

Write-Host '[network] NETWORK_RESTORE_START'
$script:NetworkProfileExitCode = -1
. (Join-Path $PSScriptRoot '_Restore-TcpNetwork-Body.ps1')
$code = if ($null -ne $script:NetworkProfileExitCode) { [int]$script:NetworkProfileExitCode } else { 1 }
Write-Host "[network] NETWORK_RESTORE_EXIT_CODE=$code"

function Test-NetworkRestoreConfirmed {
    param([int]$ExitCode)
    if ($ExitCode -eq 0) { return $true }
    try {
        $rp = Join-Path $script:NetworkLogsDir 'network-restore-result.json'
        if (-not (Test-Path -LiteralPath $rp)) { return $false }
        $o = Get-Content -LiteralPath $rp -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($o.success -eq $true) { return $true }
        if ($o.fatalErrors -and $o.fatalErrors.Count -eq 0 -and $o.steps -and @($o.steps).Count -gt 0) { return $true }
    } catch {}
    return $false
}

$confirmed = Test-NetworkRestoreConfirmed -ExitCode $code
Write-Host "[network] NETWORK_RESTORE_CONFIRMED=$confirmed"

if ($confirmed) {
    Update-NetworkState -Patch @{ tcpOptimizerApplied = $false; tcpOptimizerLastRestored = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
    Write-Host '[network] NETWORK_RESTORE_RESULT ok=true'
    Write-KojoJson -Ok $true -Status 'success' -Action 'RestoreTcpNetwork' -Message 'Réglages réseau restaurés' -Data @{
        exitCode  = $code
        confirmed = $true
        warnings  = @()
    }
}

Write-Host '[network] NETWORK_RESTORE_RESULT ok=false'
if ($code -eq 10) {
    Write-KojoJson -Ok $false -Status 'error' -Action 'RestoreTcpNetwork' -Message 'Erreur lors de la restauration réseau.' -Data @{ exitCode = 10; confirmed = $false }
} else {
    Write-KojoJson -Ok $false -Status 'error' -Action 'RestoreTcpNetwork' -Message ('Restauration annulée ou échouée (code ' + $code + ')') -Data @{ exitCode = $code; confirmed = $false }
}
