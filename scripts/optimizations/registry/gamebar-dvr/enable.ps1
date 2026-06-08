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

try {
    $gameBarPath = "HKCU:\Software\Microsoft\GameBar"
    Set-DwordValue -Path $gameBarPath -Name "UseNexusForGameBarEnabled" -Value 0
    Set-DwordValue -Path $gameBarPath -Name "GamepadNexusChordEnabled" -Value 0
    Set-DwordValue -Path $gameBarPath -Name "ShowStartupPanel" -Value 0

    Set-DwordValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0
    Set-DwordValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
    Set-DwordValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0

    exit 0
}
catch {
    Write-Error "Erreur activation Game Bar / GameDVR : $($_.Exception.Message)"
    exit 1
}
