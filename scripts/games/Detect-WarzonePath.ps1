#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
$helper = Join-Path $root 'scripts\games\_Detect-WarzonePathCore.ps1'
. $helper
$data = Get-WarzoneDetection -AppRoot $root
Write-ItalianTweaksJson -Ok $true -Status $(if ($data.installed) { 'success' } else { 'ready' }) -Action 'DetectWarzonePath' -Message $data.message -Data $data
