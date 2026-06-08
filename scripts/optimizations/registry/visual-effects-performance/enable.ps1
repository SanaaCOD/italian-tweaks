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
    Set-DwordValue -Path $basePath -Name "VisualFXSetting" -Value 3

    $subKeys = @(
        'AnimateMinMax',
        'ComboBoxAnimation',
        'ControlAnimations',
        'CursorShadow',
        'DragFullWindows',
        'DropShadow',
        'DWMAeroPeekEnabled',
        'DWMEnabled',
        'DWMSaveThumbnailEnabled',
        'ListBoxSmoothScrolling',
        'ListviewAlphaSelect',
        'ListviewShadow',
        'MenuAnimation',
        'SelectionFade',
        'TaskbarAnimations',
        'Themes',
        'ThumbnailsOrIcon',
        'TooltipAnimation'
    )

    foreach ($subKey in $subKeys) {
        Set-DwordValue -Path "$basePath\$subKey" -Name "DefaultApplied" -Value 1
    }

    exit 0
}
catch {
    Write-Error "Erreur activation effets visuels performance : $($_.Exception.Message)"
    exit 1
}
