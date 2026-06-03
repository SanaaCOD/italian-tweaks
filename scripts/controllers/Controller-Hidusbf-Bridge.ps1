#Requires -Version 5.1
<#
  Pont Apply/Restore → Apply-ControllerOC.ps1 (driver variants + registre, aligné TUNEDPC).
  Ne pas utiliser Setup.exe si absent du bundle.
#>

function Write-CtrlBridgeLog {
    param([string]$LogDir, [string]$Line)
    if (-not $LogDir) { return }
    if (Get-Command -Name 'Write-CtrlLog' -ErrorAction SilentlyContinue) {
        Write-CtrlLog -LogDir $LogDir -Line $Line
        return
    }
    if (Get-Command -Name 'Write-ItalianTweaksLog' -ErrorAction SilentlyContinue) {
        Write-ItalianTweaksLog -LogDir $LogDir -Name 'controllers' -Line $Line
    }
}

function Test-HidusbfBundleReady {
    param([string]$Root)
    $tool = Resolve-HidusbfToolPath -AppRoot $Root -LogFile ''
    $missing = @()
    if (-not $tool.Resolved) {
        $missing += 'HIDUSBF bundle (tools/hidusbf)'
    } else {
        if (-not $tool.Sys1khz) { $missing += 'AMD64_AS\1khz\hidusbf.sys' }
        if (-not $tool.Sys4khz8khz) { $missing += 'AMD64_AS\4khz-8khz\hidusbf.sys' }
        if (-not $tool.SysNoPatch) { $missing += 'AMD64_AS\NoPatch\hidusbf.sys' }
        if (-not (Test-Path -LiteralPath $tool.InfPath)) { $missing += 'HIDUSBF_AS.INF' }
    }
    return [ordered]@{
        Found         = [bool]$tool.Found
        Resolved      = [bool]$tool.Resolved
        Root          = [string]$tool.Root
        DriverDir     = [string]$tool.DriverDir
        InfPath       = [string]$tool.InfPath
        Sys1khz       = [string]$tool.Sys1khz
        Sys4khz8khz   = [string]$tool.Sys4khz8khz
        SysNoPatch    = [string]$tool.SysNoPatch
        SetupPath     = [string]$tool.SetupPath
        Ready         = ($tool.Resolved -and $missing.Count -eq 0)
        Missing       = @($missing)
    }
}

function Resolve-ControllerActionTarget {
    param(
        [string]$Root,
        [string]$LogDir,
        [string]$InstanceId,
        [string]$ControllerId,
        [string]$Vid,
        [string]$ProductId
    )
    $logFile = Join-Path $LogDir 'controller-overclocker.log'
    $hid = Normalize-DeviceInstanceId $InstanceId
    $usbHint = Normalize-DeviceInstanceId $ControllerId

    $presence = Test-ControllerDevicePresent -DeviceInstanceId $hid -UsbParentDeviceId $usbHint -Vid $Vid -DevicePid $ProductId
    if (-not $presence.Present) {
        return @{ ok = $false; code = 'NOT_PRESENT'; message = 'Manette non connectée (scan PnP PresentOnly)' }
    }

    $target = $usbHint
    if (-not (Test-IsUsbCompositeHidusbfTargetId $target)) {
        $resolved = Resolve-HidusbfCompositeTarget `
            -DeviceInstanceId $hid `
            -Vid $Vid `
            -DevicePid $ProductId `
            -HintUsbParentId $usbHint `
            -LogFile $logFile
        if ($resolved.Code -eq 'WRONG_TARGET_MI_INTERFACE') {
            return @{ ok = $false; code = 'WRONG_TARGET'; message = [string]$resolved.Message }
        }
        if ($resolved.TargetHidusbfDeviceId) {
            $target = [string]$resolved.TargetHidusbfDeviceId
        }
    }
    if (-not $target) {
        return @{ ok = $false; code = 'TARGET_UNRELIABLE'; message = 'Cible HIDUSBF USB composite introuvable' }
    }
    if (-not (Test-IsUsbCompositeHidusbfTargetId $target)) {
        return @{ ok = $false; code = 'TARGET_UNRELIABLE'; message = ('Cible HIDUSBF non fiable: ' + $target) }
    }

    Write-CtrlBridgeLog $LogDir ("TARGET instance=$hid usb=$target vid=$Vid productId=$ProductId")
    return @{
        ok               = $true
        deviceInstanceId = $hid
        usbParentId      = $target
        presenceMethod   = [string]$presence.Method
    }
}

function Read-ControllerOcResult {
    param([string]$ResultPath)
    if (-not $ResultPath -or -not (Test-Path -LiteralPath $ResultPath)) { return $null }
    try {
        return (Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Invoke-ControllerOcEngine {
    param(
        [string]$Root,
        [string]$LogDir,
        [string]$DeviceInstanceId,
        [string]$UsbParentDeviceId,
        [string]$Vid,
        [string]$ProductId,
        [string]$ControllerType,
        [int]$RateHz = 0,
        [switch]$RestoreMode
    )
    $ocScript = Join-Path $Root 'scripts\lib\devices\Apply-ControllerOC.ps1'
    if (-not (Test-Path -LiteralPath $ocScript)) {
        return @{
            exitCode = 127
            result   = $null
            command  = $ocScript
            stderr   = 'Apply-ControllerOC.ps1 introuvable'
        }
    }

    $ocLog = Join-Path $LogDir 'controller-overclocker.log'
    $resultPath = Join-Path $LogDir 'controller-oc-result.json'
    if (Test-Path -LiteralPath $resultPath) {
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    }

    $cap = Get-ControllerTypeAndCapability -Vid $Vid -DevicePid $ProductId -NameBlob $DeviceInstanceId
    $maxHz = [int]$cap.MaxRateHz
    if ($ControllerType -eq 'PS5') { $maxHz = 8000 }
    elseif ($ControllerType -in @('PS4', 'Xbox')) { $maxHz = 1000 }

    $argList = New-Object System.Collections.Generic.List[string]
    foreach ($token in @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ocScript,
        '-AppRoot', $Root, '-LogPath', $ocLog, '-ResultPath', $resultPath,
        '-DeviceInstanceId', $DeviceInstanceId, '-UsbParentDeviceId', $UsbParentDeviceId,
        '-Vid', $Vid, '-DevicePid', $ProductId, '-MaxRateHz', ([string]$maxHz)
    )) {
        [void]$argList.Add([string]$token)
    }
    if ($RestoreMode.IsPresent) {
        [void]$argList.Add([string]'-Uninstall')
    } else {
        [void]$argList.Add([string]'-RateHz')
        [void]$argList.Add([string]$RateHz)
    }

    $cmdLine = ($argList | ForEach-Object {
        if ($_ -match '[\s\\&]') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
    }) -join ' '
    Write-CtrlBridgeLog $LogDir ("OC_COMMAND " + $cmdLine)

    $exitCode = -1
    $stderr = ''
    try {
        if (-not (Test-IsAdmin)) {
            $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList.ToArray() `
                -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
            $exitCode = if ($proc) { [int]$proc.ExitCode } else { -1 }
        } else {
            & powershell.exe @($argList.ToArray())
            if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE }
            else { $exitCode = 0 }
        }
    } catch {
        $stderr = $_.Exception.Message
        Write-CtrlBridgeLog $LogDir ("OC_SPAWN_ERROR " + $stderr)
        $exitCode = 3
    }

    $result = Read-ControllerOcResult -ResultPath $resultPath
    return @{
        exitCode   = $exitCode
        result     = $result
        command    = $cmdLine
        stderr     = $stderr
        resultPath = $resultPath
        ocLog      = $ocLog
    }
}

function Get-VerifiedHzFromTarget {
    param(
        [string]$UsbParentId,
        [string]$Vid,
        [string]$ProductId
    )
    $st = Get-HidusbfConfirmedStatusForParent -UsbParentDeviceId $UsbParentId -Vid $Vid -DevicePid $ProductId
    if ($st -and $st.ConfirmedRate -gt 0) { return [int]$st.ConfirmedRate }
    return [int](Get-UsbParentPollingRate -UsbParentDeviceId $UsbParentId)
}

function Write-ControllerActionErrorJson {
    param(
        [string]$Action,
        [string]$Message,
        [hashtable]$Data,
        [string]$LogDir
    )
    $payload = @{
        errorDetails = $Message
        command      = $Data.command
        exitCode     = $Data.exitCode
        stderr       = $Data.stderr
        ocCode       = $Data.ocCode
        ocMessage    = $Data.ocMessage
    }
    foreach ($k in $Data.Keys) {
        if ($k -notin @('command', 'exitCode', 'stderr', 'ocCode', 'ocMessage', 'errorDetails')) {
            $payload[$k] = $Data[$k]
        }
    }
    Write-CtrlBridgeLog $LogDir ("FAIL action=$Action " + $Message)
    . (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
    Write-ItalianTweaksJson -Ok $false -Status 'error' -Action $Action -Message $Message -Data $payload
}

function Write-ControllerActionSuccessJson {
    param(
        [string]$Action,
        [string]$Message,
        [hashtable]$Data
    )
    . (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
    Write-ItalianTweaksJson -Ok $true -Status 'success' -Action $Action -Message $Message -Data $Data
}
