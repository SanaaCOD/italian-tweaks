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

function Set-BinaryValue {
    param(
        [string]$Path,
        [string]$Name,
        [byte[]]$Value
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -PropertyType Binary -Value $Value -Force | Out-Null
}

try {
    $path = "HKCU:\Control Panel\Mouse"

    Set-DwordValue -Path $path -Name "ActiveWindowTracking" -Value 0
    Set-StringValue -Path $path -Name "Beep" -Value "No"
    Set-StringValue -Path $path -Name "DoubleClickHeight" -Value "4"
    Set-StringValue -Path $path -Name "DoubleClickSpeed" -Value "500"
    Set-StringValue -Path $path -Name "DoubleClickWidth" -Value "4"
    Set-StringValue -Path $path -Name "ExtendedSounds" -Value "No"
    Set-StringValue -Path $path -Name "MouseHoverHeight" -Value "4"
    Set-StringValue -Path $path -Name "MouseHoverTime" -Value "400"
    Set-StringValue -Path $path -Name "MouseHoverWidth" -Value "4"
    Set-StringValue -Path $path -Name "MouseSensitivity" -Value "10"
    Set-StringValue -Path $path -Name "MouseSpeed" -Value "0"
    Set-StringValue -Path $path -Name "MouseThreshold1" -Value "0"
    Set-StringValue -Path $path -Name "MouseThreshold2" -Value "0"
    Set-StringValue -Path $path -Name "MouseTrails" -Value "0"
    Set-StringValue -Path $path -Name "SnapToDefaultButton" -Value "0"
    Set-StringValue -Path $path -Name "SwapMouseButtons" -Value "0"
    Set-DwordValue -Path $path -Name "RawMouseThrottleDuration" -Value 14

    $smoothX = [byte[]](
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x15, 0x6e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x40, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x29, 0xdc, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00
    )
    $smoothY = [byte[]](
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xfd, 0x11, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x24, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0xfc, 0x12, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0xc0, 0xbb, 0x01, 0x00, 0x00, 0x00, 0x00
    )

    Set-BinaryValue -Path $path -Name "SmoothMouseXCurve" -Value $smoothX
    Set-BinaryValue -Path $path -Name "SmoothMouseYCurve" -Value $smoothY

    exit 0
}
catch {
    Write-Error "Erreur activation souris precision brute : $($_.Exception.Message)"
    exit 1
}
