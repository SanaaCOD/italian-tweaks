#Requires -Version 5.1
<#
  Shared real PnP presence checks (registry Enum alone is NOT proof of connection).
#>

function Normalize-DeviceInstanceId {
    param([string]$Id)
    if (-not $Id) { return '' }
    return ($Id -replace '/', '\').Trim()
}

function Test-PnpStatusPresent {
    param([string]$Status)
    if (-not $Status) { return $false }
    $s = $Status.ToString().Trim()
    if ($s -match '(?i)^OK$') { return $true }
    if ($s -match '(?i)^Present$') { return $true }
    if ($s -match '(?i)^Started$') { return $true }
    return $false
}

function Test-ControllerDevicePresent {
    param(
        [string]$DeviceInstanceId = '',
        [string]$UsbParentDeviceId = '',
        [string]$Vid = '',
        [string]$DevicePid = ''
    )

    $hid = Normalize-DeviceInstanceId $DeviceInstanceId
    $usb = Normalize-DeviceInstanceId $UsbParentDeviceId
    $needles = New-Object System.Collections.Generic.List[string]
    if ($usb) { $needles.Add($usb) | Out-Null }
    if ($hid -and $hid -ne $usb) { $needles.Add($hid) | Out-Null }

    if (-not $needles.Count -and $Vid -and $DevicePid) {
        return [ordered]@{
            Success = $true; Present = $false; Reason = 'No instance id'
            Method = 'none'; Status = ''
        }
    }

    # A — Get-PnpDevice -PresentOnly
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        try {
            $presentSet = @{}
            foreach ($pd in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)) {
                $iid = Normalize-DeviceInstanceId ([string]$pd.InstanceId)
                if ($iid) { $presentSet[$iid.ToUpperInvariant()] = $pd }
            }
            foreach ($n in $needles) {
                $nu = $n.ToUpperInvariant()
                if ($presentSet.ContainsKey($nu)) {
                    $pd = $presentSet[$nu]
                    return [ordered]@{
                        Success = $true; Present = $true
                        DeviceInstanceId = $hid; UsbParentDeviceId = $usb
                        Method = 'Get-PnpDevice -PresentOnly'
                        Status = [string]$pd.Status
                    }
                }
            }
        } catch {}
    }

    # B — Get-PnpDevice exact (not PresentOnly)
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        foreach ($n in $needles) {
            try {
                $pd = Get-PnpDevice -InstanceId $n -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($pd -and (Test-PnpStatusPresent ([string]$pd.Status))) {
                    return [ordered]@{
                        Success = $true; Present = $true
                        DeviceInstanceId = $hid; UsbParentDeviceId = $usb
                        Method = 'Get-PnpDevice Status'
                        Status = [string]$pd.Status
                    }
                }
            } catch {}
        }
    }

    # C — Win32_PnPEntity CIM
    foreach ($n in $needles) {
        try {
            $ent = Get-CimInstance -ClassName Win32_PnPEntity -Filter ("PNPDeviceID = '" + ($n -replace '\\', '\\\\') + "'") -ErrorAction SilentlyContinue
            if (-not $ent) {
                $ent = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
                    Where-Object { (Normalize-DeviceInstanceId $_.PNPDeviceID) -ieq $n } |
                    Select-Object -First 1
            }
            if ($ent -and [int]$ent.ConfigManagerErrorCode -eq 0) {
                $st = if ($ent.Status) { [string]$ent.Status } else { 'OK' }
                return [ordered]@{
                    Success = $true; Present = $true
                    DeviceInstanceId = $hid; UsbParentDeviceId = $usb
                    Method = 'Win32_PnPEntity'
                    Status = $st
                }
            }
        } catch {}
    }

    return [ordered]@{
        Success = $true; Present = $false; Reason = 'Device not present'
        DeviceInstanceId = $hid; UsbParentDeviceId = $usb
        Method = 'none'; Status = ''
    }
}

function Test-IsControllerPnpDevice {
    param([object]$Pd)
    if (-not $Pd) { return $false }
    $id = Normalize-DeviceInstanceId ([string]$Pd.InstanceId)
    $name = ([string]$Pd.FriendlyName + ' ' + [string]$Pd.InstanceId)
    if ($id -match '(?i)VID_054C|VID_045E') { return $true }
    if ($name -match '(?i)DualSense|DualShock|Wireless\s+Controller|Xbox|XInput|Controller|game\s+controller|Contr.leur de jeu') {
        if ($name -match '(?i)keyboard|clavier|mouse|souris') { return $false }
        return $true
    }
    return $false
}
