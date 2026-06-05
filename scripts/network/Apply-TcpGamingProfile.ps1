#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\_common\Kojo.Json.ps1')
. (Join-Path $PSScriptRoot '_Network-Paths.ps1')
Initialize-NetworkPaths -LogDir $LogDir

Write-Host '[network] NETWORK_APPLY_START kind=tcp-gaming'
$script:NetworkProfileExitCode = -1
. (Join-Path $PSScriptRoot '_Apply-TcpGamingProfile-Body.ps1')
$code = if ($null -ne $script:NetworkProfileExitCode) { [int]$script:NetworkProfileExitCode } else { 1 }
Write-Host "[network] NETWORK_APPLY_RESULT kind=tcp-gaming code=$code"
if ($code -eq 0) {
  Update-NetworkState -Patch @{ tcpOptimizerApplied = $true; tcpOptimizerLastApplied = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
  Write-KojoJson -Ok $true -Status 'success' -Action 'ApplyTcpGamingProfile' -Message 'Profil gaming appliqué avec succès. Redémarrage conseillé.' -Data @{ exitCode = 0 }
} elseif ($code -eq 2) {
  $detail = ''
  try {
    $rp = Join-Path $script:NetworkLogsDir 'gaming-profile-result.json'
    if (Test-Path -LiteralPath $rp) {
      $o = Get-Content -LiteralPath $rp -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($o.errors -and $o.errors.Count) { $detail = ($o.errors -join ' | ') }
    }
  } catch {}
  Write-KojoJson -Ok $false -Status 'error' -Action 'ApplyTcpGamingProfile' -Message $(if ($detail) { $detail } else { 'Vérification du profil gaming échouée.' }) -Data @{ exitCode = 2 }
} else {
  Write-KojoJson -Ok $false -Status 'error' -Action 'ApplyTcpGamingProfile' -Message ('Erreur profil gaming (code ' + $code + ')') -Data @{ exitCode = $code }
}
