#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
Write-ItalianTweaksStub -Action 'ApplyApexLegendsSettings' -Message "Equivalent TUNEDPC: 12_ApexLegends_Settings.ps1.enc - remplacez ce script."