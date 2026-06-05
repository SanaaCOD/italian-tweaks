#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

. (Join-Path $PSScriptRoot '..\_common\Kojo.Json.ps1')
. (Join-Path $PSScriptRoot '_Network-Paths.ps1')
Initialize-NetworkPaths -LogDir $LogDir

Write-Host '[network] NETWORK_PROFILE_APPLY_START download'
Write-ConnectionProfilesLog 'Clic : Profil Download'

$bat = "@echo off`r`nnetsh int set global uro=enabled`r`nnetsh winsock set autotuning on`r`nnetsh int tcp set security profile=normal`r`nnetsh int tcp set global autotuninglevel=normal`r`n"
$path = Join-Path $script:NetworkScriptsDir 'Download.bat'
Write-ConnectionProfilesLog 'Fichier BAT créé ou remplacé : Download.bat'
Write-ConnectionProfilesLog "Chemin du BAT : $path"
[System.IO.File]::WriteAllText($path, $bat, [System.Text.UTF8Encoding]::new($false))

try {
    $p = Start-Process -FilePath $path -Wait -PassThru -WindowStyle Hidden
    $ok = ($p.ExitCode -eq 0)
    Write-ConnectionProfilesLog "Profil Download terminé exit=$($p.ExitCode)"
    if ($ok) { Set-ActiveNetworkProfile -Profile 'download' | Out-Null }
    Write-Host "[network] NETWORK_PROFILE_APPLY_RESULT ok=$ok profile=download"
    Write-KojoJson -Ok $ok -Status $(if ($ok) { 'success' } else { 'error' }) `
        -Action 'ApplyDownloadNetworkProfile' `
        -Message $(if ($ok) { 'Profil Download appliqué.' } else { 'Erreur profil Download.' }) `
        -Data @{ batPath = $path; exitCode = $p.ExitCode; activeProfile = $(if ($ok) { 'download' } else { $null }) }
} catch {
    Write-ConnectionProfilesLog "Erreur : $($_.Exception.Message)"
    Write-Host '[network] NETWORK_PROFILE_APPLY_RESULT ok=false profile=download'
    Write-KojoJson -Ok $false -Status 'error' -Action 'ApplyDownloadNetworkProfile' -Message $_.Exception.Message -Data @{}
}
