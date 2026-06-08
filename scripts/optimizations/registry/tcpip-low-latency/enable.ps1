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

function Test-RealTcpInterface {
    param([string]$InterfacePath)

    if ($InterfacePath -match '\{001596aa-') {
        return $false
    }

    $props = Get-ItemProperty -Path $InterfacePath -ErrorAction SilentlyContinue
    if ($null -eq $props) {
        return $false
    }

    return (
        $null -ne $props.PSObject.Properties['EnableDHCP'] -or
        $null -ne $props.PSObject.Properties['DhcpIPAddress'] -or
        $null -ne $props.PSObject.Properties['IPAddress'] -or
        $null -ne $props.PSObject.Properties['TcpAckFrequency']
    )
}

try {
    $paramsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
    Set-DwordValue -Path $paramsPath -Name "DisableTaskOffload" -Value 1
    Set-DwordValue -Path $paramsPath -Name "MaxUserPort" -Value 65534
    Set-DwordValue -Path $paramsPath -Name "TcpTimedWaitDelay" -Value 30
    Set-DwordValue -Path $paramsPath -Name "DefaultTTL" -Value 64
    Set-DwordValue -Path $paramsPath -Name "Tcp1323Opts" -Value 0

    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if (Test-Path $interfacesPath) {
        Get-ChildItem -Path $interfacesPath | ForEach-Object {
            if (-not (Test-RealTcpInterface -InterfacePath $_.PsPath)) {
                return
            }

            Set-DwordValue -Path $_.PsPath -Name "TcpAckFrequency" -Value 1
            Set-DwordValue -Path $_.PsPath -Name "TCPNoDelay" -Value 1
            Set-DwordValue -Path $_.PsPath -Name "TcpDelAckTicks" -Value 0
        }
    }

    Set-DwordValue -Path "$paramsPath\Winsock" -Name "UseDelayedAcceptance" -Value 0

    exit 0
}
catch {
    Write-Error "Erreur activation TCP/IP faible latence : $($_.Exception.Message)"
    exit 1
}
