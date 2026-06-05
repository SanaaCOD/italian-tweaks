#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '_common\Kojo.Json.ps1')
$ErrorActionPreference = 'SilentlyContinue'
$adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, LinkSpeed)
$dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses } | Select-Object -First 1 -ExpandProperty ServerAddresses)
$pingMs = $null
try {
    $p = Test-Connection -ComputerName 1.1.1.1 -Count 1 -ErrorAction Stop
    if ($p) { $pingMs = [int]$p.ResponseTime }
} catch {}

$globalTcp = ''
try { $globalTcp = (netsh int tcp show global) -join "`n" } catch {}

$out = [ordered]@{
    adapters = $adapters
    dns = $dns
    pingMs = $pingMs
    tcpGlobalSnippet = ($globalTcp -split "`n" | Select-Object -First 12) -join "`n"
    tcpOptimizerPath = Join-Path (Join-Path (Get-KojoProgramDataRoot) 'Tools\TCPOptimizer') 'TCPOptimizer.exe'
    profileLog = Join-Path $LogDir 'network-profiles.log'
}
Write-Output ($out | ConvertTo-Json -Depth 4 -Compress)
exit 0
