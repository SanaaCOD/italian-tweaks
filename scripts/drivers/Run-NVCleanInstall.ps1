#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
$exe = Get-ChildItem -LiteralPath (Join-Path $root 'tools\nvcleanstall') -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($exe) {
    Start-Process -FilePath $exe.FullName
    Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'RunNVCleanInstall' -Message 'NVCleanInstall lancé' -Data @{ path = $exe.FullName }
} else {
    Start-Process 'https://www.techpowerup.com/download/techpowerup-nvcleanstall/'
    Write-ItalianTweaksJson -Ok $true -Status 'ready' -Action 'RunNVCleanInstall' -Message 'Page NVCleanInstall ouverte — placez l''exe dans tools/nvcleanstall/' -Data @{ download = $true }
}
