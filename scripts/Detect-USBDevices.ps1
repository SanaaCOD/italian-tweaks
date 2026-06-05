<#
.SYNOPSIS
    Detects USB gaming devices (controllers and mice) and checks HIDUSBF prerequisites.
.DESCRIPTION
    Enumerates USB-class and XboxComposite-class devices (not HID children) -- matching
    how HIDUSBF and Lord of Mice work. Xbox controllers via Wireless Adapter use the
    XboxComposite class instead of USB. Filters by known gaming vendor IDs and by
    checking HID children for gaming-related names. Reads registry for filter driver
    status and bInterval. Outputs JSON to stdout for consumption by the Electron IPC layer.
#>

$ErrorActionPreference = 'Stop'

# -- Helper: Determine device type from VID or description --
function Get-DeviceType {
    param([string]$InstanceId, [string]$Description)

    $desc = $Description.ToLower()

    # Check VID (Vendor ID) in instance path
    if ($InstanceId -match 'VID_045E') { return 'xbox' }       # Microsoft
    if ($InstanceId -match 'VID_057E') { return 'nintendo' }    # Nintendo

    # Sony (VID_054C) -- distinguish PS5 DualSense from PS4 DualShock by Product ID
    # HID-level names are generic ("HID-compliant game controller"), so PID is reliable
    # PS5 DualSense: PID_0CE6, DualSense Edge: PID_0DF2
    # PS4 DualShock 4 v1: PID_05C4, v2: PID_09CC
    if ($InstanceId -match 'VID_054C') {
        if ($InstanceId -match 'PID_0CE6|PID_0DF2') { return 'ps5' }
        if ($InstanceId -match 'PID_05C4|PID_09CC') { return 'ps4' }
        # Unknown Sony device -- check description as fallback
        if ($desc -match 'dualsense') { return 'ps5' }
        return 'ps4'
    }

    # Fallback to description keywords
    if ($desc -match 'xbox|xinput')      { return 'xbox' }
    if ($desc -match 'dualsense')        { return 'ps5' }
    if ($desc -match 'dualshock|playstation|wireless controller') { return 'ps4' }
    if ($desc -match 'pro controller|joy.?con|switch') { return 'nintendo' }
    if ($desc -match 'mouse')            { return 'mouse' }

    return 'other'
}

# -- Helper: Convert HIDUSBF bInterval registry value to Hz --
# Map known HIDUSBF bInterval values -- matches Get-BIntervalFromHz in Apply script
# Full-speed: 1=1000, 2=500, 4=250, 8=125
# These are the only values our apply script writes
function Convert-BIntervalToHz {
    param([int]$BInterval)
    if ($BInterval -le 0) { return 125 }
    $knownMap = @{ 1 = 1000; 2 = 500; 4 = 250; 8 = 125 }
    $val = $knownMap[$BInterval]
    if ($val) { return $val }
    # Fallback for unknown values (e.g. firmware defaults not in our map)
    return [math]::Floor(1000 / $BInterval)
}

# -- Get a device's software (driver class) key path --
# HIDUSBF reads bInterval via IoOpenDeviceRegistryKey(PLUGPLAY_REGKEY_DRIVER)
# which maps to HKLM:\SYSTEM\CurrentControlSet\Control\Class\<Driver value>
function Get-DeviceSoftwareKeyPath {
    param([string]$EnumPath)
    try {
        $driverKey = (Get-ItemProperty -Path $EnumPath -Name 'Driver' -ErrorAction SilentlyContinue).Driver
        if ($driverKey) {
            return "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey"
        }
    } catch { }
    return $null
}

# ============================================================
# SECTION 1: Enumerate USB and XboxComposite Devices (not HID children)
# ============================================================
# HIDUSBF and Lord of Mice operate on USB-class devices, not HID children.
# After applying the filter and restarting the USB device, HID children get
# re-enumerated with different names or go into Error state. By enumerating
# USB-class devices directly, the detected instanceId IS the device we write
# LowerFilters and bInterval to -- no parent tracing needed.
#
# Xbox controllers connected via the Xbox Wireless Adapter appear in the
# XboxComposite class instead of USB. We scan both classes to catch them.
# ============================================================

$devices = @()

try {
    # Get USB-class and XboxComposite-class devices including errored ones --
    # devices in error state after a failed boost still need to be visible so
    # users can remove the boost. Xbox controllers via Wireless Adapter use
    # XboxComposite instead of USB.
    $usbDevices = @()
    foreach ($cls in @('USB', 'XboxComposite')) {
        $devs = Get-PnpDevice -Class $cls -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'OK' -or $_.Status -eq 'Error' -or $_.Status -eq 'Degraded' }
        if ($devs) { $usbDevices += $devs }
    }

    if (-not $usbDevices) {
        $usbDevices = @()
    }

    # Known gaming vendor IDs
    $gamingVIDs = @('VID_045E', 'VID_054C', 'VID_057E')

    # Gaming keywords for matching HID child names
    $gamingKeywords = @(
        'controller', 'gamepad', 'mouse', 'xbox', 'dualsense',
        'dualshock', 'hid-compliant game', 'wireless controller',
        'pro controller', 'joy.?con', 'xinput'
    )

    # Pre-fetch all HID devices once (avoid re-querying per USB device)
    $allHidDevices = @()
    try {
        $allHidDevices = Get-PnpDevice -Class 'HIDClass' -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'OK' -or $_.Status -eq 'Error' -or $_.Status -eq 'Degraded' }
        if (-not $allHidDevices) { $allHidDevices = @() }
    } catch { }

    foreach ($dev in $usbDevices) {
        try {
            $instanceId = $dev.InstanceId

            # Skip devices without a VID (hubs, root hubs, etc.)
            if ($instanceId -notmatch 'VID_') { continue }

            # Check if this is a known gaming device by vendor ID
            $isGamingVID = $false
            foreach ($vid in $gamingVIDs) {
                if ($instanceId -match $vid) { $isGamingVID = $true; break }
            }

            # Get the USB device's friendly name as starting point
            $bestName = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.Description }
            if (-not $bestName) { $bestName = '' }

            # Find HID children by matching VID and PID in instance IDs.
            # For non-gaming VIDs we need children to determine relevance.
            # For gaming VIDs with generic names we want a better display name.
            $hidChildren = @()
            $vidPid = ''
            if ($instanceId -match '(VID_[0-9A-F]+&PID_[0-9A-F]+)') {
                $vidPid = $Matches[1]
            }
            if ($vidPid) {
                $escapedVidPid = [regex]::Escape($vidPid)
                foreach ($hid in $allHidDevices) {
                    if ($hid.InstanceId -match $escapedVidPid) {
                        $hidChildren += $hid
                    }
                }
            }

            # Check if any HID child has a gaming-related name
            $hasGamingChild = $false
            foreach ($hid in $hidChildren) {
                $hidName = if ($hid.FriendlyName) { $hid.FriendlyName } else { '' }
                if (-not $hidName) { continue }
                foreach ($kw in $gamingKeywords) {
                    if ($hidName.ToLower() -match $kw) {
                        $hasGamingChild = $true
                        # Use the gaming child's name if the USB name is generic
                        if ($bestName -eq 'USB Composite Device' -or $bestName -eq 'USB Input Device' -or $bestName -eq '') {
                            $bestName = $hidName
                        }
                        break
                    }
                }
                if ($hasGamingChild) { break }
            }

            # Check if device already has hidusbf filter (always include boosted devices)
            $hasFilter = $false
            $bInterval = $null
            $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $instanceId

            try {
                $lowerFilters = (Get-ItemProperty -Path $enumPath -Name 'LowerFilters' -ErrorAction SilentlyContinue).LowerFilters
                if ($lowerFilters -and ($lowerFilters -contains 'hidusbf')) {
                    $hasFilter = $true
                }

                # Read bInterval from device's software (class) key -- this is where
                # HIDUSBF actually stores it via IoOpenDeviceRegistryKey(PLUGPLAY_REGKEY_DRIVER)
                $softwareKeyPath = Get-DeviceSoftwareKeyPath -EnumPath $enumPath
                if ($softwareKeyPath -and (Test-Path $softwareKeyPath)) {
                    $bIntervalReg = (Get-ItemProperty -Path $softwareKeyPath -Name 'bInterval' -ErrorAction SilentlyContinue).bInterval
                    if ($null -ne $bIntervalReg) {
                        $bInterval = [int]$bIntervalReg
                    }
                }

                # If not found on the device's own class key, check HID children class keys
                if ($null -eq $bInterval -and $vidPid) {
                    try {
                        foreach ($hid in $hidChildren) {
                            $hidEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($hid.InstanceId)"
                            $hidClassKey = Get-DeviceSoftwareKeyPath -EnumPath $hidEnumPath
                            if ($hidClassKey -and (Test-Path $hidClassKey)) {
                                $hidBInterval = (Get-ItemProperty -Path $hidClassKey -Name 'bInterval' -ErrorAction SilentlyContinue).bInterval
                                if ($null -ne $hidBInterval) {
                                    $bInterval = [int]$hidBInterval
                                    break
                                }
                            }
                        }
                    } catch { }
                }

                # Last resort fallback: check Device Parameters (old wrong location)
                if ($null -eq $bInterval) {
                    $devParamsPath = "$enumPath\Device Parameters"
                    $bIntervalReg = (Get-ItemProperty -Path $devParamsPath -Name 'bInterval' -ErrorAction SilentlyContinue).bInterval
                    if ($null -ne $bIntervalReg) {
                        $bInterval = [int]$bIntervalReg
                    }
                }
            } catch {
                # Registry read failed -- not critical, continue with defaults
            }

            # Skip if not a gaming device and not already boosted
            if (-not $isGamingVID -and -not $hasGamingChild -and -not $hasFilter) { continue }

            # Skip devices with no usable name (nothing to show in the UI)
            if (-not $bestName -or $bestName -eq '') { continue }

            $devType = Get-DeviceType -InstanceId $instanceId -Description $bestName
            $currentRate = if ($null -ne $bInterval) {
                Convert-BIntervalToHz -BInterval $bInterval
            } else {
                125  # Default assumption
            }

            $devices += @{
                instanceId    = $instanceId
                usbParentId   = $instanceId  # Same -- we ARE the USB device now
                friendlyName  = $bestName
                status        = [string]$dev.Status
                type          = $devType
                hasFilter     = $hasFilter
                currentRateHz = $currentRate
                bInterval     = $bInterval
            }
        } catch {
            Write-Output "Warning: Skipped device $instanceId -- $($_.Exception.Message)"
            continue
        }
    }

    Write-Output "[SQ_CHECK_OK:CONTROLLER_OC_DETECT]"
} catch {
    Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_DETECT:$($_.Exception.Message)]"
    exit 1
}

# ============================================================
# SECTION 2: Check Prerequisites
# ============================================================

$prerequisites = @{
    isAdmin                  = $true  # Script requires admin, so if we got here, we are admin
    memoryIntegrityEnabled   = $false
    hidusbfServiceInstalled  = $false
    hidusbfDriverAvailable   = $false
}

# Check Memory Integrity (HVCI)
try {
    $hvciEnabled = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -ErrorAction SilentlyContinue).Enabled
    if ($hvciEnabled -eq 1) {
        $prerequisites.memoryIntegrityEnabled = $true
    }
} catch {
    # Registry path does not exist -- HVCI not configured
}

# Check hidusbf service
try {
    $svc = Get-Service -Name 'hidusbf' -ErrorAction SilentlyContinue
    if ($svc) {
        $prerequisites.hidusbfServiceInstalled = $true
    }
} catch {
    # Service not found
}

# Check if bundled driver files are available
# The caller passes the driver path via HIDUSBF_DRIVER_PATH env var
$driverPath = $env:HIDUSBF_DRIVER_PATH
if ($driverPath -and (Test-Path -Path $driverPath)) {
    $driverSys = Join-Path $driverPath 'AMD64_AS\hidusbf.sys'
    $driverInf = Join-Path $driverPath 'HIDUSBF_AS.INF'
    if ((Test-Path $driverSys) -and (Test-Path $driverInf)) {
        $prerequisites.hidusbfDriverAvailable = $true
    }
}

Write-Output "[SQ_CHECK_OK:CONTROLLER_OC_PREREQS]"

# ============================================================
# OUTPUT: JSON
# ============================================================

$output = @{
    devices       = $devices
    prerequisites = $prerequisites
}

# Output combined result as JSON
$json = $output | ConvertTo-Json -Depth 10 -Compress
Write-Output $json
exit 0
