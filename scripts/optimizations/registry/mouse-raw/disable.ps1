$ErrorActionPreference = "Stop"

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
    $path = "HKCU:\Control Panel\Mouse"

    Set-StringValue -Path $path -Name "MouseSpeed" -Value "0"
    Set-StringValue -Path $path -Name "MouseThreshold1" -Value "0"
    Set-StringValue -Path $path -Name "MouseThreshold2" -Value "0"

    if (Test-Path $path) {
        Remove-ItemProperty -Path $path -Name "RawMouseThrottleDuration" -ErrorAction SilentlyContinue
    }

    exit 0
}
catch {
    Write-Error "Erreur desactivation souris precision brute : $($_.Exception.Message)"
    exit 1
}
