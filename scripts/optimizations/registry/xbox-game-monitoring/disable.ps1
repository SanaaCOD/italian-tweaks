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
    Set-DwordValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\xbgm" -Name "Start" -Value 3
    exit 0
}
catch {
    Write-Error "Erreur desactivation Xbox Game Monitoring : $($_.Exception.Message)"
    exit 1
}
