#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

& (Join-Path $PSScriptRoot 'Restore-TcpNetwork.ps1') -AppRoot $AppRoot -LogDir $LogDir
