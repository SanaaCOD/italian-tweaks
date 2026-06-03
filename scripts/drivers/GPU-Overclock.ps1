#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
Write-ItalianTweaksStub -Action 'GpuOverclock' -Message "Equivalent TUNEDPC: 25_GPU_Overclock.ps1.enc - remplacez ce script."