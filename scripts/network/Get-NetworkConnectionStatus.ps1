#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\Kojo.Json.ps1')
. (Join-Path $PSScriptRoot '_Network-Paths.ps1')
Initialize-NetworkPaths -LogDir $LogDir

Write-Host '[network] NETWORK_DETECT_START'

$ErrorActionPreference = 'SilentlyContinue'
$adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, LinkSpeed)
$pingMs = $null
try {
    $p = Test-Connection -ComputerName 1.1.1.1 -Count 1 -ErrorAction Stop
    if ($p) { $pingMs = [int]$p.ResponseTime }
} catch {}

$fromRegistry = Test-TcpGamingProfileApplied
$state = Read-NetworkState
$fromState = $false
if ($state -and $state.tcpOptimizerApplied -eq $true) { $fromState = $true }
$optimized = $fromRegistry -or $fromState

$tcpExists = Test-Path -LiteralPath $script:NetworkTcpExe
$lastApplied = $null
if ($state -and $state.tcpOptimizerLastApplied) { $lastApplied = [string]$state.tcpOptimizerLastApplied }
elseif ($state -and $state.tcpOptimizerLastRestored) { $lastApplied = [string]$state.tcpOptimizerLastRestored }

$activeProfile = Get-ActiveNetworkProfile

$data = [ordered]@{
    pingMs               = $pingMs
    adapters             = @($adapters)
    activeProfile        = $activeProfile
    optimized            = $optimized
    optimizedLabel       = if ($optimized) { 'Connexion optimisée' } else { 'Non optimisé' }
    tcpOptimizerPath     = $script:NetworkTcpExe
    tcpOptimizerPresent  = $tcpExists
    tcpOptimizerLastApplied = $lastApplied
    fromRegistry         = $fromRegistry
    fromState            = $fromState
    connectionProfilesLog = Join-Path $script:NetworkLogsDir 'connection-profiles.log'
}

Write-Host "[network] NETWORK_DETECT_RESULT optimized=$optimized ping=$pingMs tcp=$tcpExists active=$activeProfile"
Write-KojoJson -Ok $true -Status 'success' -Action 'GetNetworkConnectionStatus' -Message $data.optimizedLabel -Data $data
