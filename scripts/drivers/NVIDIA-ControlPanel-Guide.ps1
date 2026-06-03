#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
Write-ItalianTweaksStub -Action 'NvidiaControlPanelGuide' -Message "Equivalent TUNEDPC: 07_NVIDIA_ControlPanel_Guide.ps1.enc - remplacez ce script."