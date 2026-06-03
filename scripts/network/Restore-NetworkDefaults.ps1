#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
netsh int tcp set global autotuninglevel=normal | Out-Null
netsh int tcp set security profile=normal | Out-Null
Write-ItalianTweaksLog -LogDir $LogDir -Name 'network' -Line 'Restore-NetworkDefaults'
Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'RestoreNetworkDefaults' -Message 'Paramètres TCP restaurés (redémarrage recommandé)' -Data @{}
