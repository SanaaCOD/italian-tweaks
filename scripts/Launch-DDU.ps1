#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

Start-Process 'https://www.guru3d.com/download/display-driver-uninstaller-download/'
Write-Output (@{ ok = $true; message = 'Page téléchargement DDU ouverte dans le navigateur.' } | ConvertTo-Json -Compress)
exit 0
