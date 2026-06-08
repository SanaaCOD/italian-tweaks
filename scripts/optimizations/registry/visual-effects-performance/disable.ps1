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
    $basePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Set-DwordValue -Path $basePath -Name "VisualFXSetting" -Value 0

    exit 0
}
catch {
    Write-Error "Erreur desactivation effets visuels performance : $($_.Exception.Message)"
    exit 1
}
