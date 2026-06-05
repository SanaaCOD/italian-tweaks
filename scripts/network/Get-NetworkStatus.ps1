#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

& (Join-Path $PSScriptRoot 'Get-NetworkConnectionStatus.ps1') -AppRoot $AppRoot -LogDir $LogDir
