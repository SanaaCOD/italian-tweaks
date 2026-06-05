#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\Kojo.Json.ps1')
. (Join-Path $PSScriptRoot '_Network-Paths.ps1')
Initialize-NetworkPaths -LogDir $LogDir

Write-Host "[network] TCP_OPTIMIZER_PATH=$($script:NetworkTcpExe)"

if (Test-Path -LiteralPath $script:NetworkTcpExe) {
    $len = (Get-Item -LiteralPath $script:NetworkTcpExe).Length
    if ($len -gt 50000) {
        Write-KojoJson -Ok $true -Status 'success' -Action 'DownloadTcpOptimizer' -Message 'TCP Optimizer déjà présent.' -Data @{ path = $script:NetworkTcpExe; alreadyPresent = $true }
    }
}

$ps = @"
`$ErrorActionPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
`$Url = '$($script:NetworkTcpUrl)'
`$OutPath = '$($script:NetworkTcpExe -replace "'", "''")'
function Test-ExeOk(`$p) {
  if (-not (Test-Path `$p)) { return `$false }
  `$i = Get-Item -LiteralPath `$p -ErrorAction SilentlyContinue
  if (-not `$i) { return `$false }
  return (`$i.Length -gt 50000)
}
`$dir = Split-Path -Parent `$OutPath
if (-not (Test-Path `$dir)) { New-Item -ItemType Directory -Force -Path `$dir | Out-Null }
if (Test-Path `$OutPath) { Remove-Item -LiteralPath `$OutPath -Force -ErrorAction SilentlyContinue }
`$ok = `$false
try {
  Invoke-WebRequest -Uri `$Url -OutFile `$OutPath -UseBasicParsing
  if (Test-ExeOk `$OutPath) { `$ok = `$true }
} catch {}
if (-not `$ok) {
  try {
    `$wc = New-Object System.Net.WebClient
    `$wc.DownloadFile(`$Url, `$OutPath)
    if (Test-ExeOk `$OutPath) { `$ok = `$true }
  } catch {}
}
if (`$ok) { exit 0 } else { exit 1 }
"@

$tmp = Join-Path $script:NetworkScriptsDir 'download-tcp-optimizer.ps1'
Set-Content -LiteralPath $tmp -Value $ps -Encoding UTF8
$code = 1
try {
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmp) -Wait -PassThru -WindowStyle Hidden
    if ($p) { $code = [int]$p.ExitCode }
} catch {
    Write-KojoJson -Ok $false -Status 'error' -Action 'DownloadTcpOptimizer' -Message $_.Exception.Message -Data @{}
}

if ($code -eq 0 -and (Test-Path -LiteralPath $script:NetworkTcpExe)) {
    Write-KojoJson -Ok $true -Status 'success' -Action 'DownloadTcpOptimizer' -Message 'TCP Optimizer téléchargé.' -Data @{ path = $script:NetworkTcpExe }
} else {
    Write-KojoJson -Ok $false -Status 'error' -Action 'DownloadTcpOptimizer' -Message 'Téléchargement TCP Optimizer échoué.' -Data @{ path = $script:NetworkTcpExe }
}
