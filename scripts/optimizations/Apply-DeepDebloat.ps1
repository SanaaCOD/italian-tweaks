#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
Write-ItalianTweaksStub -Action 'ApplyDeepDebloat' -Message "Equivalent TUNEDPC: 30_Deep_Debloat.ps1.enc - remplacez ce script."