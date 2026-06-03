#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

Start-Process 'https://www.techpowerup.com/download/techpowerup-nvcleanstall/'
Write-Output (@{ ok = $true; message = 'Page NVCleanInstall ouverte.' } | ConvertTo-Json -Compress)
exit 0
