#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '_common\Kojo.Json.ps1')
$dir = Join-Path (Get-KojoProgramDataRoot) 'Tools\TCPOptimizer'
$exe = Join-Path $dir 'TCPOptimizer.exe'
$url = 'https://www.speedguide.net/files/TCPOptimizer.exe'

if (-not (Test-Path -LiteralPath $exe)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
    } catch {
        Write-Output (@{ ok = $false; error = 'Téléchargement TCP Optimizer échoué. Téléchargez manuellement depuis speedguide.net' } | ConvertTo-Json -Compress)
        exit 1
    }
}

Start-Process -FilePath $exe
Write-Output (@{ ok = $true; path = $exe } | ConvertTo-Json -Compress)
exit 0
