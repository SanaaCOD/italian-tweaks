#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'Continue'
netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
netsh int tcp set security profile=normal 2>&1 | Out-Null
netsh winsock reset 2>&1 | Out-Null

$log = Join-Path $LogDir 'network-profiles.log'
Add-Content -LiteralPath $log -Value ("[{0}] Network defaults restored" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8

Write-Output (@{ ok = $true; message = 'Paramètres réseau par défaut restaurés (redémarrage recommandé).' } | ConvertTo-Json -Compress)
exit 0
