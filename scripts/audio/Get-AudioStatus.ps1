#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$ErrorActionPreference = 'SilentlyContinue'
$data = @{
    devices = @(Get-CimInstance Win32_SoundDevice | Select-Object Name, Status, Manufacturer)
    services = @(Get-Service | Where-Object Name -match 'Audio|Audiosrv' | Select-Object Name, Status, StartType)
}
Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'GetAudioStatus' -Message 'Périphériques audio' -Data $data
