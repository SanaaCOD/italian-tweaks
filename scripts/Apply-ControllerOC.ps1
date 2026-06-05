<#
.SYNOPSIS
    Apply or remove HIDUSBF filter driver for USB polling rate overclock.
.DESCRIPTION
    Installs the hidusbf filter driver on a specific USB HID device to change its
    polling rate. Can also uninstall (remove the filter) to revert to default.
    Uses SQ_CHECK markers for status reporting to the Electron host.

    All parameters are read from environment variables (no named params) to avoid
    any command-injection risk from the Electron host:
      CONTROLLER_OC_INSTANCE_ID  -- PnP device instance ID (e.g., HID\VID_045E...)
      CONTROLLER_OC_USB_PARENT_ID -- USB parent device ID where HIDUSBF filter is applied
      CONTROLLER_OC_RATE_HZ      -- Target Hz: 125, 250, 500, 1000, 2000, 4000, or 8000 (default 1000)
      CONTROLLER_OC_DRIVER_PATH  -- Directory containing AMD64_AS\hidusbf.sys and HIDUSBF_AS.INF
      CONTROLLER_OC_UNINSTALL    -- Set to "1" to remove filter instead of install
#>

# Read all inputs from environment variables
$InstanceId   = $env:CONTROLLER_OC_INSTANCE_ID
# USB parent is where HIDUSBF filter goes (USB\VID_...) -- falls back to InstanceId
$UsbParentId  = if ($env:CONTROLLER_OC_USB_PARENT_ID) { $env:CONTROLLER_OC_USB_PARENT_ID } else { $InstanceId }
$DesiredRateHz = if ($env:CONTROLLER_OC_RATE_HZ) { [int]$env:CONTROLLER_OC_RATE_HZ } else { 1000 }
$DriverPath   = if ($env:CONTROLLER_OC_DRIVER_PATH) { $env:CONTROLLER_OC_DRIVER_PATH } else { '' }
$Uninstall    = $env:CONTROLLER_OC_UNINSTALL -eq '1'

$ErrorActionPreference = 'Stop'

# -- Map Hz to bInterval registry value --
# For rates > 1000Hz (High-Speed USB): Hz = 8000 / 2^(bInterval-1)
# For rates <= 1000Hz (Full-Speed USB): Hz = 1000 / bInterval
# HIDUSBF writes bInterval to the endpoint descriptor -- the device speed class
# determines the actual polling rate achieved.
function Get-BIntervalFromHz {
    param([int]$Hz)
    if ($Hz -gt 1000) {
        # High-Speed USB mapping
        $hsMap = @{ 8000 = 1; 4000 = 2; 2000 = 3; 1000 = 4 }
        $val = $hsMap[$Hz]
        if ($val) { return $val }
    } else {
        # Full-Speed USB mapping
        $fsMap = @{ 1000 = 1; 500 = 2; 250 = 4; 125 = 8 }
        $val = $fsMap[$Hz]
        if ($val) { return $val }
    }
    Write-Warning "Unsupported rate $Hz Hz, defaulting to 1000 Hz (bInterval=1)"
    return 1
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

# -- Find HID children matching a VID and PID and return their class key paths --
function Get-HidChildClassKeyPaths {
    param([string]$VidPid)
    $paths = @()
    if (-not $VidPid) { return $paths }
    try {
        $hidDevices = Get-PnpDevice -Class 'HIDClass' -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match [regex]::Escape($VidPid) }
        foreach ($hid in $hidDevices) {
            $hidEnumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($hid.InstanceId)"
            $classKeyPath = Get-DeviceSoftwareKeyPath -EnumPath $hidEnumPath
            if ($classKeyPath) {
                $paths += $classKeyPath
            }
        }
    } catch { }
    return $paths
}

# ============================================================
# SECTION 1: Validate inputs
# ============================================================

try {
    # Validate InstanceId is not empty and looks reasonable
    if ([string]::IsNullOrWhiteSpace($InstanceId)) {
        Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_VALIDATE:InstanceId is empty]"
        exit 1
    }

    # Validate rate
    $validRates = @(125, 250, 500, 1000, 2000, 4000, 8000)
    if ($DesiredRateHz -notin $validRates) {
        Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_VALIDATE:Invalid rate ${DesiredRateHz}Hz. Valid: 125, 250, 500, 1000, 2000, 4000, 8000]"
        exit 1
    }

    # Verify device exists
    $device = Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue
    if (-not $device) {
        Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_VALIDATE:Device not found: $InstanceId]"
        exit 1
    }

    Write-Output "Device found: $($device.FriendlyName) ($($device.Status))"
    Write-Output "[SQ_CHECK_OK:CONTROLLER_OC_VALIDATE]"
} catch {
    Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_VALIDATE:$($_.Exception.Message)]"
    exit 1
}

# ============================================================
# SECTION 2: Install or verify hidusbf service
# ============================================================

if (-not $Uninstall) {
    try {
        # Check if hidusbf is already usable on the system:
        # 1. The .sys file exists in System32\drivers (loaded or loadable)
        # 2. As a Windows service
        # 3. Any device already has the hidusbf LowerFilter (proof it works)
        # 4. Driver in the Windows driver store
        $driverReady = $false

        # Check 1: hidusbf.sys in the drivers directory
        $sysPath = Join-Path $env:SystemRoot 'System32\drivers\hidusbf.sys'
        if (Test-Path $sysPath) {
            Write-Output "hidusbf.sys found in drivers directory"
            $driverReady = $true
        }

        # Check 2: Windows service
        if (-not $driverReady) {
            $svc = Get-Service -Name 'hidusbf' -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Output "hidusbf service present (Status: $($svc.Status))"
                $driverReady = $true
            }
        }

        # Check 3: Any device already using the filter (installed via Lord of Mice etc.)
        if (-not $driverReady) {
            try {
                $existingFilters = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB' -ErrorAction SilentlyContinue |
                    Where-Object { (Get-ItemProperty $_.PSPath -Name 'LowerFilters' -EA SilentlyContinue).LowerFilters -contains 'hidusbf' } |
                    Select-Object -First 1
                if ($existingFilters) {
                    Write-Output "hidusbf filter already active on at least one device"
                    $driverReady = $true
                }
            } catch { }
        }

        # Check 4: Driver store
        if (-not $driverReady) {
            try {
                $drvList = & pnputil.exe /enum-drivers 2>&1 | Out-String
                if ($drvList -match 'hidusbf') {
                    Write-Output "hidusbf driver found in Windows driver store"
                    $driverReady = $true
                }
            } catch { }
        }

        if (-not $driverReady) {
            # Driver not found on system -- install from bundled path
            if ([string]::IsNullOrWhiteSpace($DriverPath) -or -not (Test-Path $DriverPath)) {
                Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_SERVICE:Bundled HIDUSBF driver not found at: $DriverPath]"
                exit 1
            }

            # Select the correct driver variant based on target rate
            # NoPatch: up to 1000Hz (Memory Integrity compatible)
            # 1khz: patching variant for 1kHz
            # 2khz-4khz: patching variant for 2-4kHz
            # 4khz-8khz: patching variant for 4-8kHz (needed for PS5 DualSense at 8000Hz)
            $variantDir = if ($DesiredRateHz -gt 4000) {
                Join-Path $DriverPath 'AMD64_AS\4khz-8khz'
            } elseif ($DesiredRateHz -gt 1000) {
                Join-Path $DriverPath 'AMD64_AS\2khz-4khz'
            } else {
                Join-Path $DriverPath 'AMD64_AS\NoPatch'
            }

            $variantSys = Join-Path $variantDir 'hidusbf.sys'
            if (-not (Test-Path $variantSys)) {
                Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_SERVICE:Driver variant not found: $variantSys]"
                exit 1
            }

            $infPath = Join-Path $DriverPath 'HIDUSBF_AS.INF'
            if (-not (Test-Path $infPath)) {
                Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_SERVICE:HIDUSBF_AS.INF not found in $DriverPath]"
                exit 1
            }

            # Copy variant .sys to where the INF expects it
            $targetSysPath = Join-Path $DriverPath 'AMD64_AS\hidusbf.sys'
            Write-Output "Copying driver variant to: $targetSysPath"
            Copy-Item -Path $variantSys -Destination $targetSysPath -Force

            # Install SweetLow signing certificate to TrustedPublisher store
            # Required for pnputil to accept the driver on machines without Lord of Mice
            $certPath = Join-Path $DriverPath 'SweetLow.CER'
            if (Test-Path $certPath) {
                Write-Output "Installing SweetLow signing certificate..."
                try {
                    $certResult = & certutil.exe -addstore "TrustedPublisher" "$certPath" 2>&1
                    $certExit = $LASTEXITCODE
                    if ($certExit -ne 0) {
                        Write-Output "Warning: certutil exit $certExit -- driver install may fail"
                    } else {
                        Write-Output "Certificate installed to TrustedPublisher store"
                    }
                } catch {
                    Write-Output "Warning: Failed to install certificate -- $($_.Exception.Message)"
                }
            } else {
                Write-Output "Warning: SweetLow.CER not found at $certPath -- driver install may fail"
            }

            Write-Output "Installing hidusbf driver (variant: $variantDir)"
            Write-Output "INF: $infPath"
            $pnpResult = & pnputil.exe /add-driver "$infPath" /install 2>&1
            $pnpExitCode = $LASTEXITCODE

            if ($pnpExitCode -ne 0) {
                $pnpOutput = ($pnpResult | Out-String).Trim()
                Write-Output "pnputil failed (exit $pnpExitCode) -- falling back to manual installation"

                # Fallback: manually copy .sys and create service (how Lord of Mice does it)
                $driversDest = Join-Path $env:SystemRoot 'System32\drivers\hidusbf.sys'
                try {
                    Copy-Item -Path $variantSys -Destination $driversDest -Force
                    Write-Output "Copied hidusbf.sys to $driversDest"
                } catch {
                    Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_SERVICE:Failed to copy driver to System32\drivers -- $($_.Exception.Message)]"
                    exit 1
                }

                # Create the kernel service if it does not exist
                $svc = Get-Service -Name 'hidusbf' -ErrorAction SilentlyContinue
                if (-not $svc) {
                    $scResult = & sc.exe create hidusbf type= kernel start= demand binPath= System32\drivers\hidusbf.sys 2>&1
                    $scExit = $LASTEXITCODE
                    if ($scExit -ne 0 -and $scExit -ne 1073) {
                        # 1073 = ERROR_SERVICE_EXISTS (race condition -- fine)
                        $scOutput = ($scResult | Out-String).Trim()
                        Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_SERVICE:Failed to create hidusbf service (exit $scExit) -- $scOutput]"
                        exit 1
                    }
                    Write-Output "Created hidusbf kernel service"
                } else {
                    Write-Output "hidusbf service already exists"
                }

                Write-Output "hidusbf driver installed via manual fallback"
            }

            Write-Output "hidusbf driver installed successfully"
        }

        Write-Output "[SQ_CHECK_OK:CONTROLLER_OC_SERVICE]"
    } catch {
        Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_SERVICE:$($_.Exception.Message)]"
        exit 1
    }
}

# ============================================================
# SECTION 3: Modify LowerFilters registry
# ============================================================

# Apply filter to the USB parent device, not the HID child
$enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$UsbParentId"
Write-Output "Filter target: $UsbParentId"

try {
    if (-not (Test-Path $enumPath)) {
        Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_FILTER:Registry path not found: $enumPath]"
        exit 1
    }

    # Read current LowerFilters
    $currentFilters = @()
    try {
        $regVal = (Get-ItemProperty -Path $enumPath -Name 'LowerFilters' -ErrorAction SilentlyContinue).LowerFilters
        if ($regVal) {
            $currentFilters = @($regVal)
        }
    } catch {
        # LowerFilters does not exist yet -- that is fine
    }

    $hasHidusbf = $currentFilters -contains 'hidusbf'

    if ($Uninstall) {
        # Remove hidusbf from LowerFilters
        if ($hasHidusbf) {
            $newFilters = @($currentFilters | Where-Object { $_ -ne 'hidusbf' })
            if ($newFilters.Count -eq 0) {
                # Remove the property entirely if empty
                try {
                    Remove-ItemProperty -Path $enumPath -Name 'LowerFilters' -ErrorAction Stop
                } catch {
                    Write-Output "[SQ_CHECK_WARN:CONTROLLER_OC_FILTER:Failed to remove LowerFilters: $($_.Exception.Message)]"
                }
                Write-Output "Removed LowerFilters property (was only hidusbf)"
            } else {
                Set-ItemProperty -Path $enumPath -Name 'LowerFilters' -Value $newFilters -Type MultiString
                Write-Output "Removed hidusbf from LowerFilters"
            }
        } else {
            Write-Output "hidusbf not present in LowerFilters -- nothing to remove"
        }

        # Remove bInterval from the device's software (class) key
        $softwareKeyPath = Get-DeviceSoftwareKeyPath -EnumPath $enumPath
        if ($softwareKeyPath -and (Test-Path $softwareKeyPath)) {
            try {
                Remove-ItemProperty -Path $softwareKeyPath -Name 'bInterval' -ErrorAction Stop
                Write-Output "Removed bInterval from software key: $softwareKeyPath"
            } catch {
                # Property may not exist -- that is fine
                if ($_.Exception.Message -notmatch 'does not exist') {
                    Write-Output "[SQ_CHECK_WARN:CONTROLLER_OC_FILTER:Failed to remove bInterval from software key: $($_.Exception.Message)]"
                }
            }
        }

        # Remove bInterval from HID children class keys
        $vidPid = ''
        if ($UsbParentId -match '(VID_[0-9A-F]+&PID_[0-9A-F]+)') {
            $vidPid = $Matches[1]
        }
        $hidClassKeys = Get-HidChildClassKeyPaths -VidPid $vidPid
        foreach ($hidKey in $hidClassKeys) {
            try {
                if (Test-Path $hidKey) {
                    Remove-ItemProperty -Path $hidKey -Name 'bInterval' -ErrorAction Stop
                    Write-Output "Removed bInterval from HID child: $hidKey"
                }
            } catch {
                if ($_.Exception.Message -notmatch 'does not exist') {
                    Write-Output "[SQ_CHECK_WARN:CONTROLLER_OC_FILTER:Failed to remove bInterval from HID child $hidKey -- $($_.Exception.Message)]"
                }
            }
        }

        # Clean up old wrong location (Device Parameters) if present
        $devParamsPath = "$enumPath\Device Parameters"
        if (Test-Path $devParamsPath) {
            try {
                $oldVal = (Get-ItemProperty -Path $devParamsPath -Name 'bInterval' -ErrorAction SilentlyContinue).bInterval
                if ($null -ne $oldVal) {
                    Remove-ItemProperty -Path $devParamsPath -Name 'bInterval' -ErrorAction Stop
                    Write-Output "Cleaned up stale bInterval from Device Parameters"
                }
            } catch {
                Write-Output "Warning: Failed to clean up bInterval from Device Parameters -- $($_.Exception.Message)"
            }
        }

        Write-Output "[SQ_CHECK_OK:CONTROLLER_OC_FILTER]"
    } else {
        # Add hidusbf to LowerFilters if not already present
        if (-not $hasHidusbf) {
            # Backup current LowerFilters value
            if ($currentFilters.Count -gt 0) {
                Write-Output "Backing up LowerFilters: $($currentFilters -join ', ')"
            }

            $newFilters = @($currentFilters) + @('hidusbf')
            Set-ItemProperty -Path $enumPath -Name 'LowerFilters' -Value $newFilters -Type MultiString
            Write-Output "Added hidusbf to LowerFilters"
        } else {
            Write-Output "hidusbf already present in LowerFilters"
        }

        # Set bInterval on the device's software (class) key -- this is where
        # HIDUSBF actually reads it via IoOpenDeviceRegistryKey(PLUGPLAY_REGKEY_DRIVER)
        $targetBInterval = Get-BIntervalFromHz -Hz $DesiredRateHz
        $softwareKeyPath = Get-DeviceSoftwareKeyPath -EnumPath $enumPath

        if ($softwareKeyPath -and (Test-Path $softwareKeyPath)) {
            try {
                Set-ItemProperty -Path $softwareKeyPath -Name 'bInterval' -Value $targetBInterval -Type DWord
                Write-Output "Set bInterval=$targetBInterval (${DesiredRateHz}Hz) on software key: $softwareKeyPath"
            } catch {
                Write-Output "[SQ_CHECK_WARN:CONTROLLER_OC_FILTER:Failed to write bInterval to software key: $($_.Exception.Message)]"
            }
        } else {
            # Fallback: write to Device Parameters if no software key exists
            Write-Output "No software key found -- falling back to Device Parameters"
            $devParamsPath = "$enumPath\Device Parameters"
            if (-not (Test-Path $devParamsPath)) {
                New-Item -Path $devParamsPath -Force | Out-Null
            }
            Set-ItemProperty -Path $devParamsPath -Name 'bInterval' -Value $targetBInterval -Type DWord
            Write-Output "Set bInterval=$targetBInterval (${DesiredRateHz}Hz) on Device Parameters (fallback)"
        }

        # Also write bInterval to HID children class keys (Lord of Mice compatibility)
        $vidPid = ''
        if ($UsbParentId -match '(VID_[0-9A-F]+&PID_[0-9A-F]+)') {
            $vidPid = $Matches[1]
        }
        $hidClassKeys = Get-HidChildClassKeyPaths -VidPid $vidPid
        foreach ($hidKey in $hidClassKeys) {
            try {
                if (Test-Path $hidKey) {
                    Set-ItemProperty -Path $hidKey -Name 'bInterval' -Value $targetBInterval -Type DWord
                    Write-Output "Set bInterval=$targetBInterval on HID child: $hidKey"
                }
            } catch {
                Write-Output "[SQ_CHECK_WARN:CONTROLLER_OC_FILTER:Failed to write bInterval to HID child $hidKey -- $($_.Exception.Message)]"
            }
        }

        Write-Output "[SQ_CHECK_OK:CONTROLLER_OC_FILTER]"
    }
} catch {
    Write-Output "[SQ_CHECK_FAIL:CONTROLLER_OC_FILTER:$($_.Exception.Message)]"
    exit 1
}

# ============================================================
# SECTION 4: Restart device to apply changes
# ============================================================

try {
    Write-Output "Restarting device to apply changes..."

    # Try pnputil /restart-device first (Windows 10 1903+)
    $restartResult = & pnputil.exe /restart-device "$UsbParentId" 2>&1
    $restartExit = $LASTEXITCODE

    if ($restartExit -eq 0) {
        Write-Output "Device restarted successfully via pnputil"
        Write-Output "[SQ_CHECK_OK:CONTROLLER_OC_RESTART]"
    } else {
        # Fallback: disable then re-enable the device
        Write-Output "pnputil restart failed (exit $restartExit), trying disable/enable cycle..."

        $disableResult = & pnputil.exe /disable-device "$UsbParentId" 2>&1
        $disableExit = $LASTEXITCODE
        Start-Sleep -Milliseconds 500

        if ($disableExit -ne 0) {
            $disableOutput = ($disableResult | Out-String).Trim()
            Write-Output "[SQ_CHECK_WARN:CONTROLLER_OC_RESTART:Failed to disable device (exit $disableExit): $disableOutput -- Unplug and replug to apply]"
        } else {
            $enableResult = & pnputil.exe /enable-device "$UsbParentId" 2>&1
            $enableExit = $LASTEXITCODE
            if ($enableExit -eq 0) {
                Write-Output "Device restarted via disable/enable cycle"
                Write-Output "[SQ_CHECK_OK:CONTROLLER_OC_RESTART]"
            } else {
                $enableOutput = ($enableResult | Out-String).Trim()
                Write-Output "[SQ_CHECK_WARN:CONTROLLER_OC_RESTART:Device disabled but re-enable failed (exit $enableExit) -- Unplug and replug: $enableOutput]"
            }
        }
    }
} catch {
    Write-Output "[SQ_CHECK_WARN:CONTROLLER_OC_RESTART:$($_.Exception.Message) -- Unplug and replug the device to apply changes]"
}

# ============================================================
# FINAL: Summary
# ============================================================

if ($Uninstall) {
    Write-Output ""
    Write-Output "=== Controller overclock REMOVED ==="
    Write-Output "Device: $($device.FriendlyName)"
    Write-Output "Polling rate restored to device default"
} else {
    Write-Output ""
    Write-Output "=== Controller overclock APPLIED ==="
    Write-Output "Device: $($device.FriendlyName)"
    Write-Output "Target polling rate: ${DesiredRateHz}Hz (bInterval=$targetBInterval)"
}
