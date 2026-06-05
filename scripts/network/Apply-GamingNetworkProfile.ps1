#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\Kojo.Json.ps1')
. (Join-Path $PSScriptRoot '_Network-Paths.ps1')
Initialize-NetworkPaths -LogDir $LogDir

Write-Host '[network] NETWORK_PROFILE_APPLY_START gaming'
Write-ConnectionProfilesLog 'Clic : Profil Gaming'

$bat = "@echo off`r`nnetsh int set global uro=enabled`r`nnetsh winsock set autotuning on`r`nnetsh int tcp set security profile=disabled`r`nnetsh int tcp set global autotuninglevel=disabled`r`n"
$path = Join-Path $script:NetworkScriptsDir 'Gaming.bat'
Write-ConnectionProfilesLog 'Fichier BAT créé ou remplacé : Gaming.bat'
Write-ConnectionProfilesLog "Chemin du BAT : $path"
[System.IO.File]::WriteAllText($path, $bat, [System.Text.UTF8Encoding]::new($false))

try {
    $p = Start-Process -FilePath $path -Wait -PassThru -WindowStyle Hidden
    $ok = ($p.ExitCode -eq 0)
    Write-ConnectionProfilesLog "Profil Gaming terminé exit=$($p.ExitCode)"
    if ($ok) { Set-ActiveNetworkProfile -Profile 'gaming' | Out-Null }
    Write-Host "[network] NETWORK_PROFILE_APPLY_RESULT ok=$ok profile=gaming"
    Write-KojoJson -Ok $ok -Status $(if ($ok) { 'success' } else { 'error' }) `
        -Action 'ApplyGamingNetworkProfile' `
        -Message $(if ($ok) { 'Profil Gaming appliqué.' } else { 'Erreur profil Gaming.' }) `
        -Data @{ batPath = $path; exitCode = $p.ExitCode; activeProfile = $(if ($ok) { 'gaming' } else { $null }) }
} catch {
    Write-ConnectionProfilesLog "Erreur : $($_.Exception.Message)"
    Write-Host '[network] NETWORK_PROFILE_APPLY_RESULT ok=false profile=gaming'
    Write-KojoJson -Ok $false -Status 'error' -Action 'ApplyGamingNetworkProfile' -Message $_.Exception.Message -Data @{}
}
