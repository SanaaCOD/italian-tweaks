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

function Set-MmcssTask {
    param(
        [string]$TaskName,
        [hashtable]$Values
    )

    $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\$TaskName"

    foreach ($entry in $Values.GetEnumerator()) {
        if ($entry.Value -is [int]) {
            Set-DwordValue -Path $path -Name $entry.Key -Value $entry.Value
        }
        else {
            Set-StringValue -Path $path -Name $entry.Key -Value [string]$entry.Value
        }
    }
}

try {
    $profilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-DwordValue -Path $profilePath -Name "NetworkThrottlingIndex" -Value 0xffffffff
    Set-DwordValue -Path $profilePath -Name "SystemResponsiveness" -Value 0

    Set-MmcssTask -TaskName "Audio" -Values @{
        "Affinity" = 0
        "Background Only" = "True"
        "Clock Rate" = 10000
        "GPU Priority" = 8
        "Priority" = 6
        "Scheduling Category" = "Medium"
        "SFIO Priority" = "Normal"
    }

    Set-MmcssTask -TaskName "Capture" -Values @{
        "Affinity" = 0
        "Background Only" = "True"
        "Clock Rate" = 10000
        "GPU Priority" = 8
        "Priority" = 5
        "Scheduling Category" = "Medium"
        "SFIO Priority" = "Normal"
    }

    Set-MmcssTask -TaskName "DisplayPostProcessing" -Values @{
        "Affinity" = 0
        "Background Only" = "True"
        "BackgroundPriority" = 24
        "Clock Rate" = 10000
        "GPU Priority" = 18
        "Priority" = 8
        "Scheduling Category" = "High"
        "SFIO Priority" = "High"
    }

    Set-MmcssTask -TaskName "Distribution" -Values @{
        "Affinity" = 0
        "Background Only" = "True"
        "Clock Rate" = 10000
        "GPU Priority" = 8
        "Priority" = 4
        "Scheduling Category" = "Medium"
        "SFIO Priority" = "Normal"
    }

    Set-MmcssTask -TaskName "Games" -Values @{
        "Affinity" = 0
        "Background Only" = "False"
        "Clock Rate" = 10000
        "GPU Priority" = 8
        "Priority" = 6
        "Scheduling Category" = "High"
        "SFIO Priority" = "High"
    }

    Set-MmcssTask -TaskName "Playback" -Values @{
        "Affinity" = 0
        "Background Only" = "False"
        "BackgroundPriority" = 4
        "Clock Rate" = 10000
        "GPU Priority" = 8
        "Priority" = 3
        "Scheduling Category" = "Medium"
        "SFIO Priority" = "Normal"
    }

    Set-MmcssTask -TaskName "Pro Audio" -Values @{
        "Affinity" = 0
        "Background Only" = "False"
        "Clock Rate" = 10000
        "GPU Priority" = 8
        "Priority" = 1
        "Scheduling Category" = "High"
        "SFIO Priority" = "Normal"
    }

    Set-MmcssTask -TaskName "Window Manager" -Values @{
        "Affinity" = 0
        "Background Only" = "True"
        "Clock Rate" = 10000
        "GPU Priority" = 8
        "Priority" = 5
        "Scheduling Category" = "Medium"
        "SFIO Priority" = "Normal"
    }

    exit 0
}
catch {
    Write-Error "Erreur activation profil multimedia gaming : $($_.Exception.Message)"
    exit 1
}
