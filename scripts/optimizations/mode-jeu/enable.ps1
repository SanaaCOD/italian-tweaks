# Kojo — ENABLE Mode Jeu
# Active :
# 1. Mode Jeu Windows
# 2. Optimisation pour les jeux en mode fenetre / borderless
# 3. HAGS / Planification de processeur graphique a acceleration materielle
#
# HAGS utilise HKLM et necessite admin + redemarrage PC.

$ErrorActionPreference = "Stop"

function Set-DwordValue {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Set-DirectXGlobalSetting {
    param(
        [string]$SettingName,
        [string]$SettingValue
    )

    $path = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    $propertyName = "DirectXUserGlobalSettings"

    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    $currentValue = ""
    $existing = Get-ItemProperty -Path $path -Name $propertyName -ErrorAction SilentlyContinue

    if ($null -ne $existing) {
        $currentValue = [string]$existing.$propertyName
    }

    $settings = [ordered]@{}

    if (-not [string]::IsNullOrWhiteSpace($currentValue)) {
        $parts = $currentValue -split ";"

        foreach ($part in $parts) {
            $clean = $part.Trim()

            if ([string]::IsNullOrWhiteSpace($clean)) {
                continue
            }

            $index = $clean.IndexOf("=")

            if ($index -gt 0) {
                $key = $clean.Substring(0, $index)
                $value = $clean.Substring($index + 1)
                $settings[$key] = $value
            }
        }
    }

    $settings[$SettingName] = $SettingValue

    $newValue = (($settings.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$($_.Value)"
    }) -join ";") + ";"

    New-ItemProperty -Path $path -Name $propertyName -PropertyType String -Value $newValue -Force | Out-Null
}

try {
    # 1. Mode Jeu Windows ON
    $gameBarPath = "HKCU:\Software\Microsoft\GameBar"

    Set-DwordValue -Path $gameBarPath -Name "AllowAutoGameMode" -Value 1
    Set-DwordValue -Path $gameBarPath -Name "AutoGameModeEnabled" -Value 1

    # 2. Optimisation pour les jeux en mode fenetre / borderless ON
    Set-DirectXGlobalSetting -SettingName "SwapEffectUpgradeEnable" -SettingValue "1"

    # Cache graphique utilise par Windows sur certaines builds
    $graphicsPath = "HKCU:\Software\Microsoft\DirectX\GraphicsSettings"
    Set-DwordValue -Path $graphicsPath -Name "SwapEffectUpgradeCache" -Value 1

    # 3. HAGS ON - Planification de processeur graphique a acceleration materielle
    $graphicsDriversPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    Set-DwordValue -Path $graphicsDriversPath -Name "HwSchMode" -Value 2

    Write-Host "OK - Mode Jeu active." -ForegroundColor Green
    Write-Host "OK - Optimisation jeux en mode fenetre activee." -ForegroundColor Green
    Write-Host "OK - HAGS active : redemarrage PC requis." -ForegroundColor Green

    exit 0
}
catch {
    Write-Error "Erreur activation Mode Jeu / optimisation fenetree / HAGS : $($_.Exception.Message)"
    exit 1
}