$ErrorActionPreference = "Stop"

function Remove-DwordIfPresent {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Remove-ItemProperty -Path $Path -Name $Name -Force
    }
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

    foreach ($name in @('DisableTaskOffload', 'MaxUserPort', 'TcpTimedWaitDelay', 'DefaultTTL', 'Tcp1323Opts')) {
        Remove-DwordIfPresent -Path $paramsPath -Name $name
    }

    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if (Test-Path $interfacesPath) {
        Get-ChildItem -Path $interfacesPath | ForEach-Object {
            if (-not (Test-RealTcpInterface -InterfacePath $_.PsPath)) {
                return
            }

            foreach ($name in @('TcpAckFrequency', 'TCPNoDelay', 'TcpDelAckTicks')) {
                Remove-DwordIfPresent -Path $_.PsPath -Name $name
            }
        }
    }

    Remove-DwordIfPresent -Path "$paramsPath\Winsock" -Name "UseDelayedAcceptance"

    exit 0
}
catch {
    Write-Error "Erreur desactivation TCP/IP faible latence : $($_.Exception.Message)"
    exit 1
}
