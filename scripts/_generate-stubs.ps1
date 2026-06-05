# Génère les scripts stub Kojo (contrat JSON)
$root = Split-Path -Parent $PSScriptRoot

function New-Stub($relPath, $action, $tunedpc) {
    if (-not $tunedpc) { $tunedpc = '—' }
    $full = Join-Path $root ('scripts\' + ($relPath -replace '/', '\'))
    $dir = Split-Path -Parent $full
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $depth = ($relPath -split '/').Count - 1
    $up = (@('..') * $depth) -join '\'
    $content = @"
#Requires -Version 5.1
param([string]`$AppRoot = '', [string]`$LogDir = '')
`$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path `$PSScriptRoot '$up\_common\ItalianTweaks.Json.ps1')
Write-ItalianTweaksStub -Action '$action' -Message "Equivalent TUNEDPC: $tunedpc - remplacez ce script."
"@
    [System.IO.File]::WriteAllText($full, $content, [System.Text.UTF8Encoding]::new($false))
}

$stubs = @(
    @('drivers/Install-LatestNvidiaDriver.ps1','InstallLatestNvidiaDriver','—'),
    @('drivers/Apply-NvidiaOptimization.ps1','ApplyNvidiaOptimization','13_GPU_Optimization.ps1.enc'),
    @('drivers/Apply-SQEngine.ps1','ApplySQEngine','SQEngine.ps1.enc'),
    @('drivers/NVIDIA-ControlPanel-Guide.ps1','NvidiaControlPanelGuide','07_NVIDIA_ControlPanel_Guide.ps1.enc'),
    @('drivers/GPU-Overclock.ps1','GpuOverclock','25_GPU_Overclock.ps1.enc'),
    @('network/Apply-DownloadNetworkProfile.ps1','ApplyDownloadNetworkProfile','—'),
    @('network/Apply-NetworkOptimization.ps1','ApplyNetworkOptimization','21_Network_Optimization.ps1.enc'),
    @('network/Apply-LatencyReduction.ps1','ApplyLatencyReduction','23_Latency_Reduction.ps1.enc'),
    @('games/Restore-WarzoneProfile.ps1','RestoreWarzoneProfile','—'),
    @('games/Apply-BlackOps7Settings.ps1','ApplyBlackOps7Settings','02_BlackOps7_Settings.ps1.enc'),
    @('games/Apply-FortniteSettings.ps1','ApplyFortniteSettings','03_Fortnite_Settings.ps1.enc'),
    @('games/Apply-ValorantSettings.ps1','ApplyValorantSettings','04_Valorant_Settings.ps1.enc'),
    @('games/Apply-CS2Settings.ps1','ApplyCS2Settings','05_CS2_Settings.ps1.enc'),
    @('games/Apply-ArcRaidersSettings.ps1','ApplyArcRaidersSettings','06_ArcRaiders_Settings.ps1.enc'),
    @('games/Apply-ApexLegendsSettings.ps1','ApplyApexLegendsSettings','12_ApexLegends_Settings.ps1.enc'),
    @('games/Apply-TarkovSettings.ps1','ApplyTarkovSettings','14_Tarkov_Settings.ps1.enc'),
    @('games/Apply-RustSettings.ps1','ApplyRustSettings','15_Rust_Settings.ps1.enc'),
    @('games/Apply-RainbowSixSiegeSettings.ps1','ApplyRainbowSixSiegeSettings','16_RainbowSixSiege_Settings.ps1.enc'),
    @('games/Apply-Battlefield6Settings.ps1','ApplyBattlefield6Settings','17_Battlefield6_Settings.ps1.enc'),
    @('games/Apply-MarvelRivalsSettings.ps1','ApplyMarvelRivalsSettings','18_MarvelRivals_Settings.ps1.enc'),
    @('games/Apply-LeagueOfLegendsSettings.ps1','ApplyLeagueOfLegendsSettings','19_LeagueOfLegends_Settings.ps1.enc'),
    @('games/Apply-Dota2Settings.ps1','ApplyDota2Settings','20_Dota2_Settings.ps1.enc'),
    @('games/Apply-FiveMSettings.ps1','ApplyFiveMSettings','22_FiveM_Settings.ps1.enc'),
    @('games/Apply-EAFC26Settings.ps1','ApplyEAFC26Settings','24_EAFC26_Settings.ps1.enc'),
    @('games/Apply-Overwatch2Settings.ps1','ApplyOverwatch2Settings','26_Overwatch2_Settings.ps1.enc'),
    @('games/Apply-MarathonSettings.ps1','ApplyMarathonSettings','27_Marathon_Settings.ps1.enc'),
    @('games/Apply-RocketLeagueSettings.ps1','ApplyRocketLeagueSettings','29_RocketLeague_Settings.ps1.enc'),
    @('optimizations/Get-OptimizationStatus.ps1','GetOptimizationStatus','08_Standard_Windows_Settings.ps1.enc'),
    @('optimizations/Apply-WindowedGameOptimizations.ps1','ApplyWindowedGameOptimizations','—'),
    @('optimizations/Apply-WindowsOptimization.ps1','ApplyWindowsOptimization','01_Windows_Optimization.ps1.enc'),
    @('optimizations/Apply-DeepDebloat.ps1','ApplyDeepDebloat','30_Deep_Debloat.ps1.enc'),
    @('optimizations/Undo-DeepDebloat.ps1','UndoDeepDebloat','31_Undo_Deep_Debloat.ps1.enc'),
    @('optimizations/Disable-Copilot.ps1','DisableCopilot','11_Disable_Copilot.ps1.enc'),
    @('optimizations/Windows-Update-Off.ps1','WindowsUpdateOff','09_Windows_Update_Off.ps1.enc'),
    @('optimizations/Windows-Update-On.ps1','WindowsUpdateOn','10_Windows_Update_On.ps1.enc'),
    @('optimizations/Apply-StandardWindowsSettings.ps1','ApplyStandardWindowsSettings','08_Standard_Windows_Settings.ps1.enc'),
    @('optimizations/Restore-GameMode.ps1','RestoreGameMode','—'),
    @('optimizations/Restore-PowerPlan.ps1','RestorePowerPlan','—'),
    @('audio/Apply-AudioProfile.ps1','ApplyAudioProfile','—'),
    @('audio/Restore-AudioDefaults.ps1','RestoreAudioDefaults','—'),
    @('system/Restore-Defaults.ps1','RestoreDefaults','RESTORE_DEFAULTS.ps1.enc'),
    @('system/Revert-All.ps1','RevertAll','REVERT_ALL.ps1.enc'),
    @('system/Master-Run-All.ps1','MasterRunAll','00_MASTER_RUN_ALL.ps1.enc'),
    @('system/Detect-BiosState.ps1','DetectBiosState','Detect-BiosState.ps1.enc'),
    @('system/Debug-BiosVbsIssue.ps1','DebugBiosVbsIssue','Debug-BiosVbsIssue.ps1.enc')
)

foreach ($s in $stubs) { New-Stub $s[0] $s[1] $s[2] }
Write-Host "Generated $($stubs.Count) stubs"
