#Requires -Version 5.1
param(
    [string]$AppRoot = '',
    [string]$LogDir = '',
    [ValidateSet('gaming', 'download')]
    [string]$Profile = 'gaming'
)

$ErrorActionPreference = 'Continue'
$dir = Join-Path $env:ProgramData 'ItalianTweaks\Scripts'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

if ($Profile -eq 'download') {
    $bat = @'
@echo off
netsh int set global uro=enabled
netsh winsock set autotuning on
netsh int tcp set security profile=normal
netsh int tcp set global autotuninglevel=normal
'@
} else {
    $bat = @'
@echo off
netsh int set global uro=enabled
netsh winsock set autotuning on
netsh int tcp set security profile=disabled
netsh int tcp set global autotuninglevel=disabled
'@
}

$path = Join-Path $dir ("{0}.bat" -f $(if ($Profile -eq 'download') { 'Download' } else { 'Gaming' }))
[System.IO.File]::WriteAllText($path, $bat, [System.Text.UTF8Encoding]::new($false))

$proc = Start-Process -FilePath $path -Verb RunAs -PassThru -Wait
$log = Join-Path $LogDir 'network-profiles.log'
Add-Content -LiteralPath $log -Value ("[{0}] Applied {1} exit={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Profile, $proc.ExitCode) -Encoding UTF8

Write-Output (@{ ok = ($proc.ExitCode -eq 0); profile = $Profile; batPath = $path; exitCode = $proc.ExitCode } | ConvertTo-Json -Compress)
exit 0
