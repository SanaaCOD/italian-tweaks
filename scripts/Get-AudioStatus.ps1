#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'SilentlyContinue'
$devices = @(Get-CimInstance Win32_SoundDevice | Select-Object Name, Status, Manufacturer)
$services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Audio|Audiosrv' } | Select-Object Name, Status, StartType)

$out = [ordered]@{
    devices = $devices
    services = $services
    defaultEndpoint = 'Utilisez Paramètres Windows > Son pour le périphérique par défaut.'
}
Write-Output ($out | ConvertTo-Json -Depth 4 -Compress)
exit 0
