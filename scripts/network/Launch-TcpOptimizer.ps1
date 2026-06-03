#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
$dir = Join-Path $root 'tools\tcpoptimizer'
$exe = Join-Path $dir 'TCPOptimizer.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        Invoke-WebRequest -Uri 'https://www.speedguide.net/files/TCPOptimizer.exe' -OutFile $exe -UseBasicParsing
    } catch {
        Write-ItalianTweaksJson -Ok $false -Status 'error' -Action 'LaunchTcpOptimizer' -Message 'Téléchargement échoué — voir tools/tcpoptimizer/README.txt' -Data @{}
    }
}
Start-Process -FilePath $exe
Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'LaunchTcpOptimizer' -Message 'TCP Optimizer lancé' -Data @{ path = $exe }
