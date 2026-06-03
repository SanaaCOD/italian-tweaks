#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$ErrorActionPreference = 'SilentlyContinue'

$adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Select-Object Name, LinkSpeed, InterfaceDescription)
$pingMs = $null
try { $pingMs = (Test-Connection 1.1.1.1 -Count 1 -ErrorAction Stop).ResponseTime } catch {}

$data = @{
    adapters = $adapters
    pingMs = $pingMs
    tcpOptimizerDir = Join-Path (Resolve-ItalianTweaksRoot -AppRoot $AppRoot) 'tools\tcpoptimizer'
}

Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'GetNetworkStatus' -Message 'État réseau' -Data $data
