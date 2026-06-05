#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\Kojo.Json.ps1')
. (Join-Path $PSScriptRoot '_Network-Paths.ps1')
Initialize-NetworkPaths -LogDir $LogDir

Write-Host "[network] TCP_OPTIMIZER_RUN start path=$($script:NetworkTcpExe)"

if (-not (Test-Path -LiteralPath $script:NetworkTcpExe)) {
    $dl = Join-Path $PSScriptRoot 'Download-TcpOptimizer.ps1'
    & $dl -AppRoot $AppRoot -LogDir $LogDir | Out-Null
}

if (-not (Test-Path -LiteralPath $script:NetworkTcpExe)) {
    Write-KojoJson -Ok $false -Status 'error' -Action 'LaunchTcpOptimizer' -Message 'TCP Optimizer introuvable. Téléchargez-le d''abord.' -Data @{ path = $script:NetworkTcpExe }
}

try {
    Start-Process -FilePath $script:NetworkTcpExe -WorkingDirectory $script:NetworkTcpDir
    Write-Host '[network] TCP_OPTIMIZER_RUN ok'
    Write-KojoJson -Ok $true -Status 'success' -Action 'LaunchTcpOptimizer' -Message 'TCP Optimizer lancé.' -Data @{ path = $script:NetworkTcpExe }
} catch {
    Write-KojoJson -Ok $false -Status 'error' -Action 'LaunchTcpOptimizer' -Message $_.Exception.Message -Data @{ path = $script:NetworkTcpExe }
}
