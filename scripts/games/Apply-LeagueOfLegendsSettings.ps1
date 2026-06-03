#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
Write-ItalianTweaksStub -Action 'ApplyLeagueOfLegendsSettings' -Message "Equivalent TUNEDPC: 19_LeagueOfLegends_Settings.ps1.enc - remplacez ce script."