#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
Write-ItalianTweaksStub -Action 'UndoDeepDebloat' -Message "Equivalent TUNEDPC: 31_Undo_Deep_Debloat.ps1.enc - remplacez ce script."