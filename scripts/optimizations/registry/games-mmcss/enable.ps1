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

function Set-StringValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value $Value -Force | Out-Null
}

try {
    $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"

    Set-DwordValue -Path $path -Name "Affinity" -Value 0
    Set-StringValue -Path $path -Name "Background Only" -Value "False"
    Set-DwordValue -Path $path -Name "Clock Rate" -Value 10000
    Set-DwordValue -Path $path -Name "GPU Priority" -Value 8
    Set-DwordValue -Path $path -Name "Priority" -Value 6
    Set-StringValue -Path $path -Name "Scheduling Category" -Value "High"
    Set-StringValue -Path $path -Name "SFIO Priority" -Value "High"

    exit 0
}
catch {
    Write-Error "Erreur activation Priorite Jeux MMCSS : $($_.Exception.Message)"
    exit 1
}
