#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
$ddu = Join-Path $root 'tools\ddu\Display Driver Uninstaller.exe'
if (Test-Path -LiteralPath $ddu) {
    Start-Process -FilePath $ddu
    Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'RunDDU' -Message 'DDU lancé depuis tools/ddu/' -Data @{ path = $ddu }
} else {
    Start-Process 'https://www.guru3d.com/download/display-driver-uninstaller-download/'
    Write-ItalianTweaksJson -Ok $true -Status 'ready' -Action 'RunDDU' -Message 'Page DDU ouverte — placez l''exe dans tools/ddu/' -Data @{ download = $true }
}
