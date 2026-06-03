#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$dir = Join-Path $env:ProgramData 'ItalianTweaks\Scripts'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$bat = @'
@echo off
netsh int set global uro=enabled
netsh winsock set autotuning on
netsh int tcp set security profile=disabled
netsh int tcp set global autotuninglevel=disabled
'@
$path = Join-Path $dir 'Gaming.bat'
[System.IO.File]::WriteAllText($path, $bat, [System.Text.UTF8Encoding]::new($false))
$p = Start-Process -FilePath $path -Verb RunAs -PassThru -Wait
Write-ItalianTweaksLog -LogDir $LogDir -Name 'network' -Line "Gaming profile exit=$($p.ExitCode)"
Write-ItalianTweaksJson -Ok ($p.ExitCode -eq 0) -Status $(if ($p.ExitCode -eq 0) { 'success' } else { 'error' }) `
    -Action 'ApplyGamingNetworkProfile' -Message 'Profil Gaming appliqué (UAC)' -Data @{ batPath = $path; exitCode = $p.ExitCode }
