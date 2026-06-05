#Requires -Version 5.1
# Shared helpers for Controller Overclocker (HIDUSBF).

function Write-ScriptExitCode {
    param([string]$AppRoot, [int]$Code)
    if (-not $AppRoot) { return }
    try {
        $exitPath = Join-Path $AppRoot 'logs\controller-overclocker-exitcode.txt'
        $dir = Split-Path -Parent $exitPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath $exitPath -Value $Code -Encoding ascii -Force
    } catch {}
}

function Import-ControllerOverclockerParams {
    param([string]$ParamFile)
    if (-not $ParamFile) { return $null }
    try {
        if (-not [System.IO.Path]::IsPathRooted($ParamFile)) {
            $ParamFile = Join-Path (Get-Location).Path $ParamFile
        }
        if (-not (Test-Path -LiteralPath $ParamFile)) { return $null }
        $ParamFile = (Resolve-Path -LiteralPath $ParamFile).Path
        $raw = [System.IO.File]::ReadAllText($ParamFile)
        if (-not $raw) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Resolve-UnrealAppRoot {
    param([string]$Root)
    if ($Root -and (Test-Path -LiteralPath $Root)) {
        return (Resolve-Path -LiteralPath $Root).Path
    }
    $here = $PSScriptRoot
    if ($here) {
        $c = Split-Path -Parent (Split-Path -Parent $here)
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}

function Write-DeviceLog {
    param([string]$Line, [string]$LogFile)
    if (-not $LogFile) { return }
    $dir = Split-Path -Parent $LogFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $LogFile -Value "[$ts] $Line" -Encoding UTF8
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-RelaunchElevated {
    param(
        [string]$ScriptPath,
        [hashtable]$BoundParams
    )
    $argParts = New-Object System.Collections.Generic.List[string]
    foreach ($key in $BoundParams.Keys) {
        $val = $BoundParams[$key]
        if ($null -eq $val -or $val -eq '') { continue }
        if ($val -is [switch]) {
            if ($val) { $argParts.Add("-$key") }
            continue
        }
        $argParts.Add("-$key")
        $argParts.Add([string]$val)
    }
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $argParts
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Verb RunAs -PassThru -Wait -ErrorAction Stop
        if ($null -eq $p) { exit 3 }
        $code = $p.ExitCode
        if ($null -eq $code) { $code = 0 }
        exit [int]$code
    } catch {
        exit 3
    }
}

function Write-HidusbfOcLog {
    param(
        [string]$Line,
        [string]$LogFile
    )
    if (-not $LogFile) { return }
    Write-DeviceLog ("[CONTROLLER-OC] " + $Line) $LogFile
}

function Find-HidusbfFileRecursive {
    param(
        [string]$Root,
        [string]$LeafName,
        [int]$MaxDepth = 10
    )
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return '' }
    $leaf = Split-Path -Leaf $LeafName
    try {
        $hit = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $leaf -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $leaf } |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    } catch {}
    return ''
}

function Find-HidusbfSysInFolderAliases {
    param(
        [string]$Root,
        [string[]]$FolderAliases
    )
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return '' }
    try {
        $dirs = Get-ChildItem -LiteralPath $Root -Recurse -Directory -ErrorAction SilentlyContinue
        foreach ($alias in $FolderAliases) {
            foreach ($dir in $dirs) {
                if ($dir.Name -ieq $alias) {
                    $sys = Join-Path $dir.FullName 'hidusbf.sys'
                    if (Test-Path -LiteralPath $sys) { return $sys }
                }
            }
        }
    } catch {}
    return ''
}

function Resolve-HidusbfToolPath {
    param(
        [string]$AppRoot,
        [string]$LogFile = ''
    )
    Write-HidusbfOcLog 'Resolving HIDUSBF tool path...' $LogFile

    $searchRoots = New-Object System.Collections.Generic.List[string]
    $app = Resolve-UnrealAppRoot $AppRoot
    if ($app) {
        $searchRoots.Add((Join-Path $app 'Tools\hidusbf')) | Out-Null
        $searchRoots.Add((Join-Path $app 'tools\hidusbf')) | Out-Null
    }
    if ($PSScriptRoot) {
        $proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        if ($proj) {
            $pr = Join-Path $proj 'Tools\hidusbf'
            if ($searchRoots -notcontains $pr) { $searchRoots.Add($pr) | Out-Null }
        }
    }

    $infPath = ''
    $usedRoot = ''
    foreach ($root in ($searchRoots | Select-Object -Unique)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        Write-HidusbfOcLog ("Search root: " + $root) $LogFile
        $hit = Find-HidusbfFileRecursive -Root $root -LeafName 'HIDUSBF_AS.INF'
        if ($hit) {
            $infPath = $hit
            $usedRoot = $root
            break
        }
    }

    if (-not $infPath) {
        Write-HidusbfOcLog 'HIDUSBF resolved=false' $LogFile
        $fallbackRoot = if ($searchRoots.Count -gt 0) { $searchRoots[0] } else { '' }
        return [ordered]@{
            Found    = $false
            Resolved = $false
            Root     = $fallbackRoot
        }
    }

    $driverDir = Split-Path -Parent $infPath
    Write-HidusbfOcLog ("HIDUSBF_AS.INF found: " + $infPath) $LogFile

    $infU = Find-HidusbfFileRecursive -Root $usedRoot -LeafName 'HIDUSBFU.INF'
    if (-not $infU) { $infU = Join-Path $driverDir 'HIDUSBFU.INF' }
    if (Test-Path -LiteralPath $infU) {
        Write-HidusbfOcLog ("HIDUSBFU.INF found: " + $infU) $LogFile
    }

    $cert = Find-HidusbfFileRecursive -Root $usedRoot -LeafName 'SweetLow.CER'
    if (-not $cert) { $cert = Join-Path $driverDir 'SweetLow.CER' }
    if (Test-Path -LiteralPath $cert) {
        Write-HidusbfOcLog ("SweetLow.CER found: " + $cert) $LogFile
    }

    $sys1k = Find-HidusbfSysInFolderAliases -Root $usedRoot -FolderAliases @('1khz', '1kHz', '1KHZ')
    $sys24 = Find-HidusbfSysInFolderAliases -Root $usedRoot -FolderAliases @('2khz-4khz', '2kHz-4kHz', '2KHZ-4KHZ')
    $sys48 = Find-HidusbfSysInFolderAliases -Root $usedRoot -FolderAliases @('4khz-8khz', '4kHz-8kHz', '4KHZ-8KHZ')
    $sysNp = Find-HidusbfSysInFolderAliases -Root $usedRoot -FolderAliases @('NoPatch', 'nopatch', 'NOPATCH')

    if ($sys1k) { Write-HidusbfOcLog ("1khz driver found: " + $sys1k) $LogFile }
    if ($sys24) { Write-HidusbfOcLog ("2khz-4khz driver found: " + $sys24) $LogFile }
    if ($sys48) { Write-HidusbfOcLog ("4khz-8khz driver found: " + $sys48) $LogFile }
    if ($sysNp) { Write-HidusbfOcLog ("NoPatch driver found: " + $sysNp) $LogFile }

    $amd64Dir = ''
    if ($sys1k) { $amd64Dir = Split-Path -Parent $sys1k }
    elseif ($sys48) { $amd64Dir = Split-Path -Parent $sys48 }
    else {
        $amdHit = Get-ChildItem -LiteralPath $usedRoot -Recurse -Directory -Filter 'AMD64_AS' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($amdHit) { $amd64Dir = $amdHit.FullName }
    }

    $missing = New-Object System.Collections.Generic.List[string]
    if (-not $infPath) { $missing.Add('HIDUSBF_AS.INF') | Out-Null }
    if (-not $infU -or -not (Test-Path -LiteralPath $infU)) { $missing.Add('HIDUSBFU.INF') | Out-Null }
    if (-not $cert -or -not (Test-Path -LiteralPath $cert)) { $missing.Add('SweetLow.CER') | Out-Null }
    if (-not $sys1k) { $missing.Add('AMD64_AS\1khz\hidusbf.sys (ou AMD64\1khz)') | Out-Null }
    if (-not $sys24) { $missing.Add('AMD64_AS\2khz-4khz\hidusbf.sys') | Out-Null }
    if (-not $sys48) { $missing.Add('AMD64_AS\4khz-8khz\hidusbf.sys') | Out-Null }
    if (-not $sysNp) { $missing.Add('AMD64_AS\NoPatch\hidusbf.sys') | Out-Null }

    $resolved = ($missing.Count -eq 0)
    Write-HidusbfOcLog ("HIDUSBF resolved=" + $resolved.ToString().ToLowerInvariant()) $LogFile
    if (-not $resolved -and $missing.Count -gt 0) {
        Write-HidusbfOcLog ("HIDUSBF missing: " + ($missing -join '; ')) $LogFile
    }

    $setupPath = Find-HidusbfFileRecursive -Root $usedRoot -LeafName 'Setup.exe'

    return [ordered]@{
        Found         = [bool]$infPath
        Resolved      = [bool]$resolved
        Root          = $usedRoot
        SearchRoot    = $usedRoot
        DriverDir     = $driverDir
        Amd64Dir      = $amd64Dir
        InfPath       = $infPath
        InfUninstall  = if (Test-Path -LiteralPath $infU) { $infU } else { '' }
        CertPath      = if (Test-Path -LiteralPath $cert) { $cert } else { '' }
        Sys1khz       = $sys1k
        Sys2khz4khz   = $sys24
        Sys4khz8khz   = $sys48
        SysNoPatch    = $sysNp
        SetupPath     = $setupPath
        MissingFiles  = @($missing)
    }
}

function Resolve-HidusbfBundle {
    param([string]$AppRoot)
    $tool = Resolve-HidusbfToolPath -AppRoot $AppRoot -LogFile ''
    if ($tool.Resolved) {
        return [ordered]@{
            Found        = $true
            Root         = $tool.Root
            DriverDir    = $tool.DriverDir
            InfPath      = $tool.InfPath
            InfUninstall = $tool.InfUninstall
            CertPath     = $tool.CertPath
            SetupPath    = $tool.SetupPath
            Sys1khz      = $tool.Sys1khz
            Sys2khz4khz  = $tool.Sys2khz4khz
            Sys4khz8khz  = $tool.Sys4khz8khz
            SysNoPatch   = $tool.SysNoPatch
            Amd64Dir     = $tool.Amd64Dir
        }
    }
    $fallback = if ($AppRoot) { Join-Path $AppRoot 'Tools\hidusbf' } else { '' }
    return [ordered]@{
        Found = $false
        Root  = $fallback
    }
}

function Get-HidusbfVariantSysPath {
    param(
        [hashtable]$Bundle,
        [int]$Rate
    )
    $rateHz = [int]$Rate
    if ($rateHz -eq 8000) {
        if ($Bundle.Sys4khz8khz) { return $Bundle.Sys4khz8khz }
        $folderNames = @('4khz-8khz', '4kHz-8kHz', '4KHZ-8KHZ')
        $searchRoot = if ($Bundle.SearchRoot) { $Bundle.SearchRoot } else { $Bundle.Root }
        return Find-HidusbfSysInFolderAliases -Root $searchRoot -FolderAliases $folderNames
    }
    if ($rateHz -eq 2000 -or $rateHz -eq 4000) {
        if ($Bundle.Sys2khz4khz) { return $Bundle.Sys2khz4khz }
    }
    if ($rateHz -eq 125 -and $Bundle.SysNoPatch) { return $Bundle.SysNoPatch }
    if ($Bundle.Sys1khz) { return $Bundle.Sys1khz }

    $folderNames = if ($rateHz -eq 2000 -or $rateHz -eq 4000) {
        @('2khz-4khz', '2kHz-4kHz', '2KHZ-4KHZ')
    } elseif ($rateHz -eq 125) {
        @('NoPatch', 'nopatch', 'NOPATCH')
    } else {
        @('1khz', '1kHz', '1KHZ')
    }
    $searchRoot = if ($Bundle.SearchRoot) { $Bundle.SearchRoot } else { $Bundle.Root }
    return Find-HidusbfSysInFolderAliases -Root $searchRoot -FolderAliases $folderNames
}

function Copy-HidusbfVariantToActive {
    param(
        [hashtable]$Bundle,
        [string]$VariantSysPath,
        [int]$Rate = 1000,
        [string]$LogFile = ''
    )
    $cmdName = if ($Rate -eq 8000) { '4kHz-8kHz.cmd' } else { '1kHz.cmd' }
    $cmdPath = Join-Path $Bundle.DriverDir $cmdName
    if (Test-Path -LiteralPath $cmdPath) {
        try {
            $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $cmdPath) -WorkingDirectory $Bundle.DriverDir -Wait -PassThru -WindowStyle Hidden
            $code = if ($proc) { $proc.ExitCode } else { -1 }
            Write-DeviceLog ("[DEVICE] Variant cmd result: exit=" + $code + " cmd=" + $cmdPath) $LogFile
            if ($code -eq 0) { return $true }
        } catch {
            Write-DeviceLog ("[DEVICE] Variant cmd result: error " + $_.Exception.Message) $LogFile
        }
    }

    $destDirs = @(
        (Join-Path $Bundle.DriverDir 'AMD64_AS'),
        (Join-Path $Bundle.Root 'AMD64_AS')
    )
    $copied = $false
    foreach ($destDir in $destDirs) {
        try {
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $VariantSysPath -Destination (Join-Path $destDir 'hidusbf.sys') -Force
            $copied = $true
        } catch {}
    }
    return $copied
}

function Get-HidusbfPatchHintRate {
    try {
        foreach ($keyPath in @(
            'HKLM:\SYSTEM\CurrentControlSet\Services\HIDUSBF\Parameters',
            'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF'
        )) {
            if (-not (Test-Path -LiteralPath $keyPath)) { continue }
            $patch = (Get-ItemProperty -LiteralPath $keyPath -Name PatchUSBXHCI -ErrorAction SilentlyContinue).PatchUSBXHCI
            if ($null -eq $patch) { continue }
            if ([int]$patch -eq 3) { return 8000 }
            if ([int]$patch -eq 1) { return 1000 }
        }
    } catch {}
    return $null
}

function Get-ActiveHidusbfVariantRateFromBundle {
    param([hashtable]$Bundle)
    if (-not $Bundle -or -not $Bundle.DriverDir) { return $null }
    $activeCandidates = @(
        (Join-Path $Bundle.DriverDir 'AMD64_AS\hidusbf.sys'),
        (Join-Path $Bundle.Root 'AMD64_AS\hidusbf.sys')
    )
    $activeSys = $activeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $activeSys) { return $null }
    try {
        $activeHash = (Get-FileHash -LiteralPath $activeSys -Algorithm SHA256).Hash
        foreach ($rate in @(1000, 8000)) {
            $variant = Get-HidusbfVariantSysPath -Bundle $Bundle -Rate $rate
            if (-not $variant -or -not (Test-Path -LiteralPath $variant)) { continue }
            $variantHash = (Get-FileHash -LiteralPath $variant -Algorithm SHA256).Hash
            if ($variantHash -eq $activeHash) { return [int]$rate }
        }
        $activeSize = (Get-Item -LiteralPath $activeSys).Length
        foreach ($rate in @(1000, 8000)) {
            $variant = Get-HidusbfVariantSysPath -Bundle $Bundle -Rate $rate
            if (-not $variant -or -not (Test-Path -LiteralPath $variant)) { continue }
            if ((Get-Item -LiteralPath $variant).Length -eq $activeSize) { return [int]$rate }
        }
    } catch {}
    return $null
}

function Get-DriverVariantLabelForRate {
    param([int]$RateHz)
    if ($RateHz -eq 8000) { return '4khz-8khz' }
    if ($RateHz -eq 1000) { return '1khz' }
    return 'unknown'
}

function Get-ConfirmedControllerRate {
    param(
        [hashtable]$Bundle
    )
    $active = Get-ActiveHidusbfVariantRateFromBundle -Bundle $Bundle
    if ($active -in @(1000, 8000)) { return [int]$active }
    $patch = Get-HidusbfPatchHintRate
    if ($patch -in @(1000, 8000)) { return [int]$patch }
    return 125
}

function Test-ActiveDriverVariantMatchesRate {
    param(
        [hashtable]$Bundle,
        [int]$RequestedRate
    )
    if ($RequestedRate -notin @(1000, 8000)) { return $false }
    $active = Get-ActiveHidusbfVariantRateFromBundle -Bundle $Bundle
    if ($null -eq $active) { return $false }
    return ([int]$active -eq [int]$RequestedRate)
}

function Set-HidusbfPatchUsbXhci {
    param(
        [int]$Rate,
        [string]$LogFile = ''
    )
    $patchValue = if ($Rate -eq 8000) { 3 } else { 1 }
    $keyPaths = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\HIDUSBF\Parameters',
        'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF'
    )
    foreach ($keyPath in $keyPaths) {
        try {
            if (-not (Test-Path -LiteralPath $keyPath)) {
                New-Item -Path $keyPath -Force | Out-Null
            }
            Set-ItemProperty -LiteralPath $keyPath -Name 'PatchUSBXHCI' -Value $patchValue -Type DWord -Force
            Set-ItemProperty -LiteralPath $keyPath -Name 'PatchUSBPort' -Value 1 -Type DWord -Force
            Write-DeviceLog ("[DEVICE] PatchUSBXHCI set: " + $patchValue + " PatchUSBPort=1 at " + $keyPath) $LogFile
        } catch {
            Write-DeviceLog ("[DEVICE] PatchUSBXHCI failed at " + $keyPath + ": " + $_.Exception.Message) $LogFile
        }
    }
    return $true
}

function Ensure-HidusbfFullBundle {
    param(
        [string]$AppRoot,
        [string]$LogFile = ''
    )
    $tool = Resolve-HidusbfToolPath -AppRoot $AppRoot -LogFile $LogFile
    if ($tool.Resolved) {
        return [ordered]@{
            Found        = $true
            Root         = $tool.Root
            DriverDir    = $tool.DriverDir
            InfPath      = $tool.InfPath
            InfUninstall = $tool.InfUninstall
            CertPath     = $tool.CertPath
            SetupPath    = $tool.SetupPath
            Sys1khz      = $tool.Sys1khz
            Sys2khz4khz  = $tool.Sys2khz4khz
            Sys4khz8khz  = $tool.Sys4khz8khz
            SysNoPatch   = $tool.SysNoPatch
            Amd64Dir     = $tool.Amd64Dir
        }
    }
    if ($LogFile) {
        Write-DeviceLog '[DEVICE] HIDUSBF extrait introuvable dans Tools\hidusbf (aucun telechargement zip)' $LogFile
    }
    return [ordered]@{
        Found = $false
        Root  = if ($AppRoot) { Join-Path $AppRoot 'Tools\hidusbf' } else { '' }
    }
}

function Find-HidusbfSetupExe {
    param(
        [string]$AppRoot,
        [string]$LogFile = ''
    )
    $roots = @(
        (Join-Path $AppRoot 'Tools\hidusbf'),
        (Join-Path $AppRoot 'tools\hidusbf')
    )
    $relCandidates = @(
        'Setup.exe',
        'setup.exe',
        'USB Devices Rate Setup.exe',
        'DRIVER\Setup.exe',
        'hidusbf\DRIVER\Setup.exe',
        'HIDUSBF\DRIVER\Setup.exe'
    )
    foreach ($root in @($roots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)) {
        foreach ($rel in $relCandidates) {
            $p = Join-Path $root $rel
            if (Test-Path -LiteralPath $p) {
                $resolved = (Resolve-Path -LiteralPath $p).Path
                Write-DeviceLog ("[DEVICE] HIDUSBF setup exe found: " + $resolved) $LogFile
                return $resolved
            }
        }
        try {
            $found = Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -eq 'Setup.exe' -or
                    $_.Name -eq 'setup.exe' -or
                    $_.Name -eq 'USB Devices Rate Setup.exe'
                } |
                Select-Object -First 1
            if ($found) {
                Write-DeviceLog ("[DEVICE] HIDUSBF setup exe found: " + $found.FullName) $LogFile
                return $found.FullName
            }
        } catch {}
    }
    Write-DeviceLog '[DEVICE] HIDUSBF setup exe found: none' $LogFile
    return ''
}

function Start-HidusbfSetupProcess {
    param(
        [string]$SetupExePath,
        [string]$LogFile = ''
    )
    if (-not $SetupExePath -or -not (Test-Path -LiteralPath $SetupExePath)) { return $false }
    try {
        Start-Process -FilePath $SetupExePath -ArgumentList @('/all') -Verb RunAs -ErrorAction Stop | Out-Null
        Write-DeviceLog ("[DEVICE] Setup.exe launched: " + $SetupExePath + ' /all') $LogFile
        return $true
    } catch {
        Write-DeviceLog ("[DEVICE] Setup.exe launch failed: " + $_.Exception.Message) $LogFile
        return $false
    }
}

function Analyze-HidusbfCapabilities {
    param(
        [string]$SetupExePath,
        [string]$LogFile = ''
    )
    if (-not $SetupExePath -or -not (Test-Path -LiteralPath $SetupExePath)) {
        Write-DeviceLog '[DEVICE] No supported CLI detected, manual assisted mode only.' $LogFile
        return $false
    }

    $hasUsableCli = $false
    $helpCaptured = $false
    foreach ($arg in @('/?', '/help')) {
        $stdoutFile = $null
        $stderrFile = $null
        try {
            $stdoutFile = [System.IO.Path]::GetTempFileName()
            $stderrFile = [System.IO.Path]::GetTempFileName()
            Start-Process -FilePath $SetupExePath -ArgumentList $arg -Wait -PassThru -NoNewWindow `
                -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -ErrorAction Stop | Out-Null
            $chunks = @()
            if (Test-Path -LiteralPath $stdoutFile) { $chunks += [System.IO.File]::ReadAllText($stdoutFile) }
            if (Test-Path -LiteralPath $stderrFile) { $chunks += [System.IO.File]::ReadAllText($stderrFile) }
            $text = ($chunks -join [Environment]::NewLine).Trim()
            if ($text) {
                if (-not $helpCaptured) {
                    Write-DeviceLog '[DEVICE] HIDUSBF CLI help:' $LogFile
                    $helpCaptured = $true
                }
                foreach ($line in ($text -split "`r?`n")) {
                    $trim = $line.Trim()
                    if ($trim) { Write-DeviceLog ("[DEVICE]   " + $trim) $LogFile }
                }
                if ($text -match '(?i)(usage|help|/all|command|switch|parameter)') {
                    $hasUsableCli = $true
                }
            }
        } catch {
            # GUI-only Setup may not expose CLI output.
        } finally {
            foreach ($tmp in @($stdoutFile, $stderrFile)) {
                if ($tmp -and (Test-Path -LiteralPath $tmp)) {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    if (-not $helpCaptured) {
        Write-DeviceLog '[DEVICE] HIDUSBF CLI help: (no output)' $LogFile
    }
    if (-not $hasUsableCli) {
        Write-DeviceLog '[DEVICE] No supported CLI detected, manual assisted mode only.' $LogFile
    }
    return $hasUsableCli
}

function Launch-HidusbfSetupTool {
    param(
        [hashtable]$Bundle,
        [string]$LogFile = ''
    )
    $setupPath = if ($Bundle.SetupPath) { $Bundle.SetupPath } else { Join-Path $Bundle.DriverDir 'Setup.exe' }
    if (-not (Test-Path -LiteralPath $setupPath)) {
        Write-DeviceLog '[DEVICE] Setup.exe launch: missing' $LogFile
        return $false
    }
    return Start-HidusbfSetupProcess -SetupExePath $setupPath -LogFile $LogFile
}

function Restart-HidusbfDriverService {
    param([string]$LogFile = '')
    $name = 'hidusbf'
    try {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-DeviceLog '[DEVICE] HIDUSBF service restart: not installed yet' $LogFile
            return $false
        }
        if ($svc.Status -eq 'Running') {
            Restart-Service -Name $name -Force -ErrorAction Stop
        } else {
            Start-Service -Name $name -ErrorAction Stop
        }
        Write-DeviceLog '[DEVICE] HIDUSBF service restart: ok' $LogFile
        return $true
    } catch {
        try {
            & sc.exe stop $name 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500
            & sc.exe start $name 2>&1 | Out-Null
            Write-DeviceLog '[DEVICE] HIDUSBF service restart: ok (sc.exe)' $LogFile
            return $true
        } catch {
            Write-DeviceLog ("[DEVICE] HIDUSBF service restart: failed " + $_.Exception.Message) $LogFile
            return $false
        }
    }
}

function Convert-RegPathToInstanceId {
    param([string]$RegPath)
    if (-not $RegPath) { return '' }
    return ($RegPath -replace '^HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\', '')
}

function Import-SweetLowCertificate {
    param([string]$CertPath, [string]$LogFile)
    if (-not $CertPath -or -not (Test-Path -LiteralPath $CertPath)) {
        Write-DeviceLog '[DEVICE] Certificate import result: skipped (SweetLow.CER absent)' $LogFile
        return $true
    }
    $tp = & certutil.exe -addstore -f 'TrustedPublisher' $CertPath 2>&1 | Out-String
    $root = & certutil.exe -addstore -f 'Root' $CertPath 2>&1 | Out-String
    Write-DeviceLog ("[DEVICE] Certificate import result: TrustedPublisher=" + ($tp.Trim() -replace '\s+', ' ')) $LogFile
    Write-DeviceLog ("[DEVICE] Certificate import result: Root=" + ($root.Trim() -replace '\s+', ' ')) $LogFile
    return ($LASTEXITCODE -eq 0 -or $tp -match 'CertUtil: -addstore command completed successfully')
}

function Install-HidusbfDriverInf {
    param([string]$InfPath, [string]$LogFile)
    if (-not (Test-Path -LiteralPath $InfPath)) {
        Write-DeviceLog '[DEVICE] INF install result: error inf_missing' $LogFile
        return $false
    }
    $section = 'DefaultInstall.nt'
    $argLine = "setupapi,InstallHinfSection $section 132 `"$InfPath`""
    $proc = Start-Process -FilePath 'rundll32.exe' -ArgumentList $argLine -Wait -PassThru -WindowStyle Hidden
    $code = if ($proc) { $proc.ExitCode } else { -1 }
    Write-DeviceLog ("[DEVICE] INF install result: exit=" + $code + " inf=" + $InfPath) $LogFile
    if ($code -eq 0) { return $true }
    $svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\hidusbf'
    if (Test-Path -LiteralPath $svcKey) {
        Write-DeviceLog '[DEVICE] INF install result: driver service already present (continuing)' $LogFile
        return $true
    }
    return $false
}

function Test-BlockedInputDevice {
    param([string]$Text)
    if (-not $Text) { return $false }
    return ($Text -match '(?i)keyboard|clavier|mouse|souris|touchpad|trackpad|track\s*point')
}

function Test-AllowedControllerDevice {
    param(
        [string]$Text,
        [string]$Vid = '',
        [string]$DevicePid = ''
    )
    if (Test-BlockedInputDevice $Text) { return $false }
    if ($Vid -and $DevicePid) {
        $vidU = $Vid.ToUpperInvariant()
        $productU = $DevicePid.ToUpperInvariant()
        if ($vidU -eq '054C' -and $productU -match '^(0CE6|0DF2|05C4|09CC|0BA0|0E5F|054C|0268|0C5E)$') { return $true }
        if ($vidU -eq '045E' -and $productU -match '^(02FF|0B12|0B13|02E0|02FD|02FE|028E|028F|02D1|02DD|0719|0B05|0B06|0B22)$') { return $true }
    }
    if ($Text -match '(?i)dualsense|xbox|controller|game controller|scuf|ps4|ps5|manette|joystick|gamepad|hid controller|contrôleur de jeu|contrôleur') {
        return $true
    }
    if ($Text -match '(?i)^HID\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}') { return $true }
    if ($Text -match '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}') { return $true }
    return $false
}

function Convert-InstanceIdToRegPath {
    param([string]$InstanceId)
    if (-not $InstanceId) { return @() }
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $InstanceId
    if (Test-Path -LiteralPath $path) { return @($path) }
    return @()
}

function Get-VidPidFromInstanceId {
    param([string]$InstanceId)
    $vid = ''
    $productId = ''
    if ($InstanceId -match '(?i)VID_([0-9A-F]{4})') { $vid = $Matches[1].ToUpperInvariant() }
    if ($InstanceId -match '(?i)PID_([0-9A-F]{4})') { $productId = $Matches[1].ToUpperInvariant() }
    return @{ Vid = $vid; Pid = $productId }
}

function Test-UsbParentCandidateBlocked {
    param([string]$Text)
    if (-not $Text) { return $false }
    if ($Text -match '(?i)keyboard|clavier|mouse|souris|touchpad|trackpad|camera|webcam|biometric|digitizer') { return $true }
    if (Get-ControllerChildMatchReason $Text) { return $false }
    return ($Text -match '(?i)razer\s*mouse|audio|usbaudio|microphone|micro\s|headset|speaker|casque')
}

function Get-UsbCompositeClassGuid {
    return '{36fc9e60-c465-11cf-8056-444553540000}'
}

function Get-ControllerChildMatchReason {
    param([string]$Text)
    if (-not $Text) { return '' }
    if ($Text -match '(?i)keyboard|clavier|mouse|souris|touchpad|trackpad') { return '' }
    $rules = @(
        @{ Reason = 'DualSense'; Pattern = '(?i)DualSense' },
        @{ Reason = 'Wireless Controller'; Pattern = '(?i)Wireless\s+Controller' },
        @{ Reason = 'DUALSHOCK'; Pattern = '(?i)DUALSHOCK' },
        @{ Reason = 'DualShock'; Pattern = '(?i)DualShock' },
        @{ Reason = 'PS4'; Pattern = '(?i)PS4' },
        @{ Reason = 'PS5'; Pattern = '(?i)PS5' },
        @{ Reason = 'Contrôleur de jeu'; Pattern = '(?i)Contr.leur de jeu' },
        @{ Reason = 'Controleur de jeu'; Pattern = '(?i)Controleur de jeu' },
        @{ Reason = 'HID-compliant game controller'; Pattern = '(?i)HID-compliant\s+game\s+controller' },
        @{ Reason = 'Game controller'; Pattern = '(?i)Game\s+Controller' },
        @{ Reason = 'XInput'; Pattern = '(?i)XInput' },
        @{ Reason = 'Xbox'; Pattern = '(?i)Xbox' },
        @{ Reason = 'gamepad'; Pattern = '(?i)gamepad' },
        @{ Reason = 'joystick'; Pattern = '(?i)joystick' },
        @{ Reason = 'manette'; Pattern = '(?i)manette' }
    )
    foreach ($rule in $rules) {
        if ($Text -match $rule.Pattern) { return [string]$rule.Reason }
    }
    return ''
}

function Test-IsControllerChildName {
    param([string]$Text)
    return [bool](Get-ControllerChildMatchReason $Text)
}

function Test-IsHidusbfControllerChildName {
    param([string]$Text)
    return (Test-IsControllerChildName $Text)
}

function Get-ContainerControllerChildBlob {
    param([string]$ContainerId)
    $parts = New-Object System.Collections.Generic.List[string]
    $childName = ''
    $priority = @{
        'DualSense' = 100
        'Wireless Controller' = 90
        'DUALSHOCK' = 85
        'HID-compliant game controller' = 80
        'Contrôleur de jeu' = 75
        'Game controller' = 70
    }
    $bestScore = -1
    if (-not $ContainerId) {
        return @{ Blob = ''; ChildName = '' }
    }
    try {
        foreach ($dev in (Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)) {
            $id = [string]$dev.DeviceID
            if (-not $id) { continue }
            $reg = Get-EnumDeviceRegistryInfo -InstanceId $id
            if (-not $reg.ContainerId -or ($reg.ContainerId -ine $ContainerId)) { continue }
            $blob = (
                (Get-DeviceDisplayName -InstanceId $id -PnpDevice $dev) + ' ' +
                [string]$dev.Name + ' ' +
                [string]$dev.Caption
            ).Trim()
            if ($blob) { $parts.Add($blob) | Out-Null }
            $reason = Get-ControllerChildMatchReason $blob
            if ($reason) {
                $score = if ($priority.ContainsKey($reason)) { [int]$priority[$reason] } else { 50 }
                if ($score -gt $bestScore) {
                    $bestScore = $score
                    $childName = $reason
                }
            }
        }
    } catch {}
    return @{ Blob = (($parts | Select-Object -Unique) -join ' | '); ChildName = $childName }
}

function Get-ControllerTypeAndCapability {
    param(
        [string]$Vid,
        [string]$DevicePid,
        [string]$NameBlob = '',
        [string]$ChildName = ''
    )
    $blob = (($NameBlob + ' ' + $ChildName).Trim())
    $vidU = ($Vid + '').ToUpperInvariant()
    $pidU = ($DevicePid + '').ToUpperInvariant()

    if ($vidU -eq '054C' -and $pidU -match '^(0CE6|0DF2|0E5F)$') {
        return [ordered]@{ Type = 'DualSense'; Badge = 'PS5 DUALSENSE'; MaxRateHz = 8000 }
    }
    if ($blob -match '(?i)dualsense|\bps5\b') {
        return [ordered]@{ Type = 'DualSense'; Badge = 'PS5 DUALSENSE'; MaxRateHz = 8000 }
    }
    if ($blob -match '(?i)dualshock|\bps4\b') {
        return [ordered]@{ Type = 'PS4'; Badge = 'PS4 DUALSHOCK'; MaxRateHz = 1000 }
    }
    if ($vidU -eq '054C' -and $pidU -match '^(05C4|09CC|0BA0|054C|0268|0C5E)$') {
        return [ordered]@{ Type = 'PS4'; Badge = 'PS4 DUALSHOCK'; MaxRateHz = 1000 }
    }
    if ($vidU -eq '054C' -and $blob -match '(?i)wireless\s+controller' -and $blob -notmatch '(?i)dualsense') {
        return [ordered]@{ Type = 'PS4'; Badge = 'PS4 DUALSHOCK'; MaxRateHz = 1000 }
    }
    if ($vidU -eq '045E' -or $blob -match '(?i)xbox|xinput') {
        return [ordered]@{ Type = 'Xbox'; Badge = 'XBOX CONTROLLER'; MaxRateHz = 1000 }
    }
    return [ordered]@{ Type = 'HID Controller'; Badge = 'HID CONTROLLER'; MaxRateHz = 1000 }
}

function Get-UsbParentPollingRate {
    param([string]$UsbParentDeviceId)
    if (-not $UsbParentDeviceId) { return 125 }
    $usbKey = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $UsbParentDeviceId
    $hasFilter = $false
    $rate = 125
    try {
        $lf = (Get-ItemProperty -LiteralPath $usbKey -Name LowerFilters -ErrorAction SilentlyContinue).LowerFilters
        if ($lf -and @($lf) -contains 'hidusbf') { $hasFilter = $true }
    } catch {}
    if (-not $hasFilter) { return 125 }
    $patchXhci = $null
    foreach ($keyPath in @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\hidusbf\Parameters',
        'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF'
    )) {
        if (-not (Test-Path -LiteralPath $keyPath)) { continue }
        try {
            if ($null -eq $patchXhci) {
                $patchXhci = (Get-ItemProperty -LiteralPath $keyPath -Name PatchUSBXHCI -ErrorAction SilentlyContinue).PatchUSBXHCI
            }
        } catch {}
    }
    if ($patchXhci -eq 3) { return 8000 }
    try {
        $drv = (Get-ItemProperty -LiteralPath $usbKey -Name Driver -ErrorAction SilentlyContinue).Driver
        if ($drv) {
            $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $drv
            $bi = (Get-ItemProperty -LiteralPath $classKey -Name bInterval -ErrorAction SilentlyContinue).bInterval
            if ($bi -eq 1) { return 1000 }
            if ($bi -eq 2) { return 500 }
            if ($bi -eq 4) { return 250 }
        }
    } catch {}
    if ($patchXhci -eq 1) { return 1000 }
    return 125
}

function Test-IsUsbCompositeHidusbfTargetId {
    param([string]$InstanceId)
    if (-not $InstanceId) { return $false }
    if ($InstanceId -match '(?i)&MI_\d+') { return $false }
    if ($InstanceId -notmatch '(?i)^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}\\') { return $false }
    return $true
}

function Test-RegistryClassGuidMatchesUsbComposite {
    param([string]$ClassGuid)
    if (-not $ClassGuid) { return $false }
    $norm = $ClassGuid.Trim().Trim('{}').ToUpperInvariant()
    $want = (Get-UsbCompositeClassGuid).Trim().Trim('{}').ToUpperInvariant()
    return ($norm -eq $want)
}

function Get-DeviceDisplayName {
    param(
        [string]$InstanceId,
        [object]$PnpDevice = $null
    )
    $reg = Get-EnumDeviceRegistryInfo -InstanceId $InstanceId
    if ($reg.FriendlyName) { return [string]$reg.FriendlyName }
    if ($PnpDevice) {
        $n = [string]$PnpDevice.Name
        if ($n) { return $n }
        return [string]$PnpDevice.Caption
    }
    return ''
}

function Test-CompositeHasControllerChild {
    param(
        [string]$ContainerId,
        [string]$Vid = '',
        [string]$DevicePid = '',
        [string]$SelectedDeviceInstanceId = '',
        [string]$LogFile = ''
    )
    if (-not $ContainerId) { return $false }
    try {
        foreach ($dev in (Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)) {
            $id = [string]$dev.DeviceID
            if (-not $id) { continue }
            $reg = Get-EnumDeviceRegistryInfo -InstanceId $id
            if (-not $reg.ContainerId -or ($reg.ContainerId -ine $ContainerId)) { continue }

            $blob = (
                (Get-DeviceDisplayName -InstanceId $id -PnpDevice $dev) + ' ' +
                [string]$dev.Name + ' ' +
                [string]$dev.Caption + ' ' +
                [string]$dev.Description
            ).Trim()

            if ($LogFile) { Write-UsbParentResolveLog ("Child candidate text=" + $blob) $LogFile }

            if ($SelectedDeviceInstanceId -and ($id -ieq $SelectedDeviceInstanceId)) {
                if ($LogFile) {
                    Write-UsbParentResolveLog 'Child controller match=true' $LogFile
                    Write-UsbParentResolveLog 'Match reason=selected device instance' $LogFile
                }
                return $true
            }

            $reason = Get-ControllerChildMatchReason $blob
            $matched = [bool]$reason
            if ($LogFile) {
                Write-UsbParentResolveLog ("Child controller match=" + $matched.ToString().ToLowerInvariant()) $LogFile
                if ($reason) { Write-UsbParentResolveLog ("Match reason=" + $reason) $LogFile }
            }
            if ($matched) {
                if ($LogFile) { Write-UsbParentResolveLog ("Controller child matched: " + $id) $LogFile }
                return $true
            }
        }
    } catch {
        if ($LogFile) { Write-UsbParentResolveLog ("Child scan error: " + $_.Exception.Message) $LogFile }
    }
    return $false
}

function Test-IsRelaxedHidusbfUsbCompositeParent {
    param(
        $RegInfo,
        [string]$ContainerId,
        [string]$Vid,
        [string]$DevicePid,
        [string]$SelectedDeviceInstanceId,
        [string]$LogFile
    )
    if (-not $RegInfo -or -not $RegInfo.Exists) { return $false }
    if ([string]$RegInfo.Service -ine 'usbccgp') { return $false }
    return (Test-CompositeHasControllerChild `
        -ContainerId $ContainerId `
        -Vid $Vid `
        -DevicePid $DevicePid `
        -SelectedDeviceInstanceId $SelectedDeviceInstanceId `
        -LogFile $LogFile)
}

function Test-IsStrictHidusbfUsbCompositeParent {
    param(
        $RegInfo,
        [string]$ContainerId,
        [string]$Vid,
        [string]$DevicePid,
        [string]$SelectedDeviceInstanceId,
        [string]$LogFile
    )
    if (-not (Test-IsRelaxedHidusbfUsbCompositeParent -RegInfo $RegInfo -ContainerId $ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $SelectedDeviceInstanceId -LogFile '')) {
        return $false
    }
    if (-not (Test-RegistryClassGuidMatchesUsbComposite ([string]$RegInfo.ClassGuid))) { return $false }
    return $true
}

function Add-UsbCompositeParentCandidates {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$Vid,
        [string]$DevicePid,
        [string]$HidContainerId,
        [string]$SelectedDeviceInstanceId,
        [string]$LogFile,
        [switch]$RelaxedOnly
    )
    foreach ($usbId in (Get-UsbEnumInstanceIdsByVidPid -Vid $Vid -DevicePid $DevicePid)) {
        if (-not (Test-IsUsbCompositeHidusbfTargetId $usbId)) { continue }
        $reg = Get-EnumDeviceRegistryInfo -InstanceId $usbId
        $display = Get-DeviceDisplayName -InstanceId $usbId
        if (Test-UsbParentCandidateBlocked ($usbId + ' ' + $display)) { continue }
        $ok = if ($RelaxedOnly) {
            (Test-IsRelaxedHidusbfUsbCompositeParent -RegInfo $reg -ContainerId $reg.ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $SelectedDeviceInstanceId -LogFile $LogFile)
        } else {
            (Test-IsStrictHidusbfUsbCompositeParent -RegInfo $reg -ContainerId $reg.ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $SelectedDeviceInstanceId -LogFile $LogFile)
        }
        if (-not $ok) { continue }
        $score = if ($RelaxedOnly) { 70 } else { 100 }
        if ($HidContainerId -and $reg.ContainerId -and ($HidContainerId -ieq $reg.ContainerId)) { $score += 50 }
        $src = if ($RelaxedOnly) { 'usb_enum_relaxed' } else { 'usb_enum_strict' }
        $Candidates.Add((New-UsbParentCandidate -InstanceId $usbId -Source $src -Score $score -RegInfo $reg)) | Out-Null
    }
}

function Write-UsbParentResolveLog {
    param([string]$Line, [string]$LogFile)
    if (-not $LogFile) { return }
    Write-DeviceLog ("[CONTROLLER-OC] " + $Line) $LogFile
}

function Get-EnumDeviceRegistryInfo {
    param([string]$InstanceId)
    $info = [ordered]@{
        InstanceId     = $InstanceId
        RegPath        = ''
        ContainerId    = ''
        ParentIdPrefix = ''
        Service        = ''
        ClassGuid      = ''
        FriendlyName   = ''
        Exists         = $false
    }
    if (-not $InstanceId) { return $info }
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $InstanceId
    $info.RegPath = $regPath
    if (-not (Test-Path -LiteralPath $regPath)) { return $info }
    $info.Exists = $true
    try {
        $p = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
        if ($p.ContainerID) { $info.ContainerId = [string]$p.ContainerID }
        if ($p.ParentIdPrefix) { $info.ParentIdPrefix = [string]$p.ParentIdPrefix }
        if ($p.Service) { $info.Service = [string]$p.Service }
        if ($p.ClassGUID) { $info.ClassGuid = [string]$p.ClassGUID }
        if ($p.FriendlyName) { $info.FriendlyName = [string]$p.FriendlyName }
        elseif ($p.DeviceDesc) { $info.FriendlyName = [string]$p.DeviceDesc }
    } catch {}
    return $info
}

function Get-UsbEnumInstanceIdsByVidPid {
    param(
        [string]$Vid,
        [Alias('Pid')]
        [string]$DevicePid
    )
    $list = New-Object System.Collections.Generic.List[string]
    if (-not $Vid -or -not $DevicePid) { return @() }
    $usbRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB'
    if (-not (Test-Path -LiteralPath $usbRoot)) { return @() }
    $vidPidNeedle = ('VID_' + $Vid + '&PID_' + $DevicePid).ToUpperInvariant()
    try {
        foreach ($vidPidKey in Get-ChildItem -LiteralPath $usbRoot -ErrorAction SilentlyContinue) {
            if ($vidPidKey.PSChildName.ToUpperInvariant() -notlike ($vidPidNeedle + '*')) { continue }
            foreach ($instKey in Get-ChildItem -LiteralPath $vidPidKey.PSPath -ErrorAction SilentlyContinue) {
                $id = 'USB\' + $vidPidKey.PSChildName + '\' + $instKey.PSChildName
                $list.Add($id) | Out-Null
            }
        }
    } catch {}
    return @($list | Select-Object -Unique)
}

function New-UsbParentCandidate {
    param(
        [string]$InstanceId,
        [string]$Source,
        [int]$Score,
        $RegInfo = $null
    )
    if (-not $RegInfo) { $RegInfo = Get-EnumDeviceRegistryInfo -InstanceId $InstanceId }
    return [ordered]@{
        InstanceId     = $InstanceId
        Source         = $Source
        Score          = $Score
        ContainerId    = [string]$RegInfo.ContainerId
        Service        = [string]$RegInfo.Service
        ClassGuid      = [string]$RegInfo.ClassGuid
        FriendlyName   = [string]$RegInfo.FriendlyName
        ParentIdPrefix = [string]$RegInfo.ParentIdPrefix
        HasMi          = ($InstanceId -match '(?i)&MI_\d+')
        RegExists      = [bool]$RegInfo.Exists
    }
}

function Get-UsbParentCandidateScore {
    param(
        $Candidate,
        [string]$HidContainerId,
        [string]$HidParentIdPrefix,
        [string]$PreferredMi
    )
    $id = [string]$Candidate.InstanceId
    $blob = ($id + ' ' + $Candidate.FriendlyName + ' ' + $Candidate.Service).Trim()
    if (Test-UsbParentCandidateBlocked $blob) { return -10000 }

    $score = [int]$Candidate.Score
    if ($HidContainerId -and $Candidate.ContainerId -and ($HidContainerId -ieq $Candidate.ContainerId)) { $score += 50 }
    if ($HidParentIdPrefix -and $Candidate.ParentIdPrefix -and ($HidParentIdPrefix -ieq $Candidate.ParentIdPrefix)) { $score += 35 }

    if ($id -match '(?i)^USB\\') {
        if ($Candidate.Service -ieq 'usbccgp' -and -not $Candidate.HasMi) { $score += 120 }
        elseif ($Candidate.Service -ieq 'usbccgp') { $score += 90 }
        if ($blob -match '(?i)USB Composite Device|périphérique USB composite|composite') { $score += 40 }
        if (-not $Candidate.HasMi) { $score += 70 }
        if ($PreferredMi -and $id -match ('(?i)&MI_' + [regex]::Escape([string]$PreferredMi) + '(\D|$|&)')) { $score += 55 }
        elseif ($Candidate.HasMi) { $score += 25 }
    } elseif ($id -match '(?i)^HID\\') {
        $score += 5
    }
    if (-not $Candidate.RegExists) { $score -= 200 }
    return $score
}

function Get-FlattenedUsbParentCandidates {
    param($Candidates)
    if ($null -eq $Candidates) { return @() }
    if ($Candidates -is [System.Collections.Generic.List[object]]) {
        return [object[]]$Candidates.ToArray()
    }
    if ($Candidates -is [System.Collections.ArrayList]) {
        return [object[]]$Candidates.ToArray()
    }
    $arr = @($Candidates)
    if ($arr.Count -eq 1 -and $arr[0] -is [System.Collections.IEnumerable] -and $arr[0] -isnot [string] -and $arr[0] -isnot [System.Collections.IDictionary]) {
        return @($arr[0] | ForEach-Object { $_ })
    }
    return $arr
}

function Select-BestUsbParentCandidate {
    param(
        $Candidates,
        [string]$HidContainerId,
        [string]$HidParentIdPrefix,
        [string]$PreferredMi
    )
    $all = Get-FlattenedUsbParentCandidates $Candidates
    $pool = @($all | Where-Object { $_.InstanceId -match '(?i)^USB\\' })
    if (-not $pool.Count) { $pool = @($all) }
    $ranked = @()
    foreach ($c in @($pool)) {
        if (-not $c -or -not $c.InstanceId) { continue }
        $s = Get-UsbParentCandidateScore -Candidate $c -HidContainerId $HidContainerId -HidParentIdPrefix $HidParentIdPrefix -PreferredMi $PreferredMi
        if ($s -lt -5000) { continue }
        $ranked += [PSCustomObject]@{ Candidate = $c; Score = $s }
    }
    if (-not $ranked.Count) { return $null }
    return ($ranked | Sort-Object Score -Descending | Select-Object -First 1).Candidate
}

function Resolve-HidusbfCompositeTarget {
    param(
        [string]$DeviceInstanceId,
        [string]$Vid = '',
        [Alias('Pid')]
        [string]$DevicePid = '',
        [string]$HintUsbParentId = '',
        [string]$LogFile = ''
    )
    $empty = [ordered]@{
        Success               = $false
        Code                  = 'USB_COMPOSITE_NOT_FOUND'
        Message               = 'Parent USB composite introuvable'
        DeviceInstanceId      = $DeviceInstanceId
        UsbCompositeParentId  = ''
        TargetHidusbfDeviceId = ''
        UsbParentDeviceId     = ''
    }

    Write-UsbParentResolveLog 'Resolve USB composite target start' $LogFile
    Write-UsbParentResolveLog ("HID selected=" + $DeviceInstanceId) $LogFile

    $vp = Get-VidPidFromInstanceId $DeviceInstanceId
    if (-not $Vid) { $Vid = $vp.Vid }
    if (-not $DevicePid) { $DevicePid = $vp.Pid }
    Write-UsbParentResolveLog ("Selected VID/PID=" + $Vid + '/' + $DevicePid) $LogFile

    $hidContainerId = ''
    $hidParentIdPrefix = ''
    if ($DeviceInstanceId -match '^(?i)HID\\') {
        $hidInfo = Get-EnumDeviceRegistryInfo -InstanceId $DeviceInstanceId
        $hidContainerId = [string]$hidInfo.ContainerId
        $hidParentIdPrefix = [string]$hidInfo.ParentIdPrefix
        Write-UsbParentResolveLog ("HID registry key=" + $hidInfo.RegPath) $LogFile
        Write-UsbParentResolveLog ("HID ContainerID=" + $(if ($hidContainerId) { $hidContainerId } else { '(none)' })) $LogFile
    }

    $hintTarget = ''
    if ($HintUsbParentId) {
        if ($HintUsbParentId -match '(?i)^(.+?)&MI_\d+') {
            $hintTarget = $Matches[1]
            Write-UsbParentResolveLog ("Hint MI stripped to composite=" + $hintTarget) $LogFile
        } elseif (Test-IsUsbCompositeHidusbfTargetId $HintUsbParentId) {
            $hintTarget = $HintUsbParentId
        } elseif ($HintUsbParentId -match '(?i)&MI_\d+') {
            Write-UsbParentResolveLog ("Hint rejected (MI interface): " + $HintUsbParentId) $LogFile
            $bad = [ordered]@{
                Success               = $false
                Code                  = 'WRONG_TARGET_MI_INTERFACE'
                Message               = 'Cible HIDUSBF invalide: interface MI (utiliser le composite USB sans MI_)'
                DeviceInstanceId      = $DeviceInstanceId
                UsbCompositeParentId  = ''
                TargetHidusbfDeviceId = ''
                UsbParentDeviceId     = ''
            }
            Write-UsbParentResolveLog 'Resolve USB composite target result=error_wrong_mi' $LogFile
            return $bad
        }
        if ($hintTarget) {
            $hintReg = Get-EnumDeviceRegistryInfo -InstanceId $hintTarget
            $hintOk = $false
            if ($hintReg.Exists) {
                $hintOk = (Test-IsStrictHidusbfUsbCompositeParent -RegInfo $hintReg -ContainerId $hintReg.ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $DeviceInstanceId -LogFile $LogFile)
                if (-not $hintOk) {
                    $hintOk = (Test-IsRelaxedHidusbfUsbCompositeParent -RegInfo $hintReg -ContainerId $hintReg.ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $DeviceInstanceId -LogFile $LogFile)
                }
            }
            if ($hintOk) {
                Write-UsbParentResolveLog ("Selected USB composite parent=" + $hintTarget) $LogFile
                Write-UsbParentResolveLog ("Selected TargetHidusbfDeviceId=" + $hintTarget + " (hint)") $LogFile
                Write-UsbParentResolveLog 'Resolve USB composite target result=success' $LogFile
                return [ordered]@{
                    Success               = $true
                    Code                  = 'USB_COMPOSITE_RESOLVED'
                    Message               = 'Parent USB composite resolu'
                    DeviceInstanceId      = $DeviceInstanceId
                    UsbCompositeParentId  = $hintTarget
                    TargetHidusbfDeviceId = $hintTarget
                    UsbParentDeviceId     = $hintTarget
                }
            }
        }
    }

    if (-not $Vid -or -not $DevicePid) {
        Write-UsbParentResolveLog 'Resolve USB composite target result=error_no_vidpid' $LogFile
        return $empty
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $preferredMi = ''
    if ($DeviceInstanceId -match '(?i)MI_(\d+)') { $preferredMi = $Matches[1] }

    Add-UsbCompositeParentCandidates -Candidates $candidates -Vid $Vid -DevicePid $DevicePid -HidContainerId $hidContainerId -SelectedDeviceInstanceId $DeviceInstanceId -LogFile $LogFile
    if ($candidates.Count -eq 0) {
        Write-UsbParentResolveLog 'No strict USB composite parent; trying relaxed (usbccgp + controller child)' $LogFile
        Add-UsbCompositeParentCandidates -Candidates $candidates -Vid $Vid -DevicePid $DevicePid -HidContainerId $hidContainerId -SelectedDeviceInstanceId $DeviceInstanceId -LogFile $LogFile -RelaxedOnly
    }

    if ($hidContainerId) {
        try {
            foreach ($dev in (Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)) {
                $id = [string]$dev.DeviceID
                if ($id -notmatch ('(?i)VID_' + [regex]::Escape($Vid))) { continue }
                if ($id -notmatch ('(?i)PID_' + [regex]::Escape($DevicePid))) { continue }
                if ($id -notmatch '(?i)^USB\\') { continue }
                if ($id -match '(?i)&MI_\d+') { continue }
                $reg = Get-EnumDeviceRegistryInfo -InstanceId $id
                if (-not $reg.ContainerId -or ($reg.ContainerId -ine $hidContainerId)) { continue }
                if (Test-UsbParentCandidateBlocked ($id + ' ' + (Get-DeviceDisplayName -InstanceId $id -PnpDevice $dev))) { continue }
                $containerOk = (Test-IsStrictHidusbfUsbCompositeParent -RegInfo $reg -ContainerId $reg.ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $DeviceInstanceId -LogFile $LogFile)
                if (-not $containerOk) {
                    $containerOk = (Test-IsRelaxedHidusbfUsbCompositeParent -RegInfo $reg -ContainerId $reg.ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $DeviceInstanceId -LogFile $LogFile)
                }
                if (-not $containerOk) { continue }
                $candidates.Add((New-UsbParentCandidate -InstanceId $id -Source 'container_match' -Score 130 -RegInfo $reg)) | Out-Null
            }
        } catch {}
    }

    $best = Select-BestUsbParentCandidate -Candidates $candidates -HidContainerId $hidContainerId -HidParentIdPrefix $hidParentIdPrefix -PreferredMi $preferredMi
    if (-not $best -or -not $best.InstanceId) {
        foreach ($usbId in (Get-UsbEnumInstanceIdsByVidPid -Vid $Vid -DevicePid $DevicePid)) {
            if ($usbId -notmatch '(?i)&MI_\d+') { continue }
            $parentGuess = $usbId -replace '&MI_\d+.*$', ''
            if (-not (Test-IsUsbCompositeHidusbfTargetId $parentGuess)) { continue }
            $reg = Get-EnumDeviceRegistryInfo -InstanceId $parentGuess
            if (Test-UsbParentCandidateBlocked ($parentGuess + ' ' + (Get-DeviceDisplayName -InstanceId $parentGuess))) { continue }
            $miOk = (Test-IsStrictHidusbfUsbCompositeParent -RegInfo $reg -ContainerId $reg.ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $DeviceInstanceId -LogFile $LogFile)
            if (-not $miOk) {
                $miOk = (Test-IsRelaxedHidusbfUsbCompositeParent -RegInfo $reg -ContainerId $reg.ContainerId -Vid $Vid -DevicePid $DevicePid -SelectedDeviceInstanceId $DeviceInstanceId -LogFile $LogFile)
            }
            if (-not $miOk) { continue }
            Write-UsbParentResolveLog ("MI fallback parent candidate=" + $parentGuess) $LogFile
            $candidates.Add((New-UsbParentCandidate -InstanceId $parentGuess -Source 'mi_stripped' -Score 90 -RegInfo $reg)) | Out-Null
        }
        $best = Select-BestUsbParentCandidate -Candidates $candidates -HidContainerId $hidContainerId -HidParentIdPrefix $hidParentIdPrefix -PreferredMi $preferredMi
    }
    if (-not $best -or -not $best.InstanceId) {
        Write-UsbParentResolveLog 'ERROR USB composite parent not found' $LogFile
        Write-UsbParentResolveLog 'Resolve USB composite target result=error' $LogFile
        return $empty
    }

    $bestId = [string]$best.InstanceId
    $bestReg = Get-EnumDeviceRegistryInfo -InstanceId $bestId
    if ($bestReg.Service -ine 'usbccgp') {
        Write-UsbParentResolveLog ("WARN parent Service=" + $bestReg.Service + " (expected usbccgp)") $LogFile
    }
    if (-not (Test-IsUsbCompositeHidusbfTargetId $bestId)) {
        Write-UsbParentResolveLog ("ERROR selected target has MI or invalid form: " + $bestId) $LogFile
        return [ordered]@{
            Success               = $false
            Code                  = 'WRONG_TARGET_MI_INTERFACE'
            Message               = 'Cible HIDUSBF invalide: interface MI (utiliser le composite USB sans MI_)'
            DeviceInstanceId      = $DeviceInstanceId
            UsbCompositeParentId  = ''
            TargetHidusbfDeviceId = ''
            UsbParentDeviceId     = ''
        }
    }

    Write-UsbParentResolveLog ("Selected USB composite parent=" + $bestId) $LogFile
    Write-UsbParentResolveLog ("Selected TargetHidusbfDeviceId=" + $bestId) $LogFile
    Write-UsbParentResolveLog 'Resolve USB composite target result=success' $LogFile
    return [ordered]@{
        Success               = $true
        Code                  = 'USB_COMPOSITE_RESOLVED'
        Message               = 'Parent USB composite resolu'
        DeviceInstanceId      = $DeviceInstanceId
        UsbCompositeParentId  = $bestId
        TargetHidusbfDeviceId = $bestId
        UsbParentDeviceId     = $bestId
    }
}

function Resolve-UsbParentDeviceId {
    param(
        [string]$DeviceInstanceId,
        [string]$Vid = '',
        [Alias('Pid')]
        [string]$DevicePid = '',
        [string]$HintUsbParentId = '',
        [string]$LogFile = ''
    )
    $target = Resolve-HidusbfCompositeTarget `
        -DeviceInstanceId $DeviceInstanceId `
        -Vid $Vid `
        -DevicePid $DevicePid `
        -HintUsbParentId $HintUsbParentId `
        -LogFile $LogFile
    if ($target.TargetHidusbfDeviceId) { return [string]$target.TargetHidusbfDeviceId }
    return ''
}

function Resolve-UsbCompositeParentDeviceId {
    param(
        [string]$DeviceInstanceId,
        [string]$Vid = '',
        [Alias('Pid')]
        [string]$DevicePid = '',
        [string]$HintUsbParentId = '',
        [string]$LogFile = ''
    )
    return (Resolve-UsbParentDeviceId @PSBoundParameters)
}

function Find-DeviceRegistryPaths {
    param(
        [string]$DeviceInstanceId,
        [string]$Vid,
        [Alias('Pid')]
        [string]$DevicePid,
        [string]$LogFile = ''
    )
    $usbIds = New-Object System.Collections.Generic.List[string]
    $hidIds = New-Object System.Collections.Generic.List[string]
    $mi = ''
    if ($DeviceInstanceId -match '(?i)MI_(\d+)') { $mi = $Matches[1] }

    if ($DeviceInstanceId -match '(?i)^HID\\') {
        $hidIds.Add($DeviceInstanceId) | Out-Null
    } elseif ($DeviceInstanceId -match '(?i)^USB\\') {
        $usbIds.Add($DeviceInstanceId) | Out-Null
    }

    if ($Vid -and $DevicePid) {
        try {
            $devs = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
            foreach ($dev in $devs) {
                $id = [string]$dev.DeviceID
                if ($id -notmatch ('(?i)VID_' + [regex]::Escape($Vid))) { continue }
                if ($id -notmatch ('(?i)PID_' + [regex]::Escape($DevicePid))) { continue }
                if ($mi -and $id -notmatch ('(?i)MI_' + [regex]::Escape($mi))) { continue }
                if ($id -match '(?i)^USB\\' -and $id -match '(?i)MI_\d+') {
                    $usbIds.Add($id) | Out-Null
                } elseif ($id -match '(?i)^HID\\') {
                    $hidIds.Add($id) | Out-Null
                }
            }
        } catch {}
    }

    $usbPaths = @()
    foreach ($id in ($usbIds | Select-Object -Unique)) {
        $usbPaths += Convert-InstanceIdToRegPath $id
    }
    $usbPaths = @($usbPaths | Where-Object { $_ } | Select-Object -Unique)

    $hidPaths = @()
    foreach ($id in ($hidIds | Select-Object -Unique)) {
        $hidPaths += Convert-InstanceIdToRegPath $id
    }
    $hidPaths = @($hidPaths | Where-Object { $_ } | Select-Object -Unique)

    if ($usbPaths.Count -gt 0 -or $hidPaths.Count -gt 0) {
        $applyPaths = @()
        if ($usbPaths.Count -gt 0) { $applyPaths += $usbPaths[0] }
        if ($hidPaths.Count -gt 0) { $applyPaths += $hidPaths[0] }
        $applyPaths = @($applyPaths | Select-Object -Unique)

        $restartIds = New-Object System.Collections.Generic.List[string]
        foreach ($path in $applyPaths) {
            $instance = Convert-RegPathToInstanceId $path
            if ($instance) { $restartIds.Add($instance) | Out-Null }
        }
        $usbInstance = if ($usbPaths.Count -gt 0) { Convert-RegPathToInstanceId $usbPaths[0] } else { '' }
        if ($usbInstance -match '(?i)MI_\d+') {
            $compositePrefix = $usbInstance -replace '&MI_\d+.*$', ''
            try {
                foreach ($dev in (Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)) {
                    $id = [string]$dev.DeviceID
                    if ($id -match '(?i)^USB\\' -and $id -eq $compositePrefix) {
                        $restartIds.Add($id) | Out-Null
                    }
                }
            } catch {}
        }

        Write-DeviceLog ("[DEVICE] Registry apply target(s): " + ($applyPaths -join ' | ')) $LogFile
        if ($restartIds.Count -gt 0) {
            Write-DeviceLog ("[DEVICE] Device restart plan: " + (($restartIds | Select-Object -Unique) -join ' | ')) $LogFile
        }
        return [ordered]@{
            ApplyPaths   = $applyPaths
            CleanupPaths = @()
            RestartIds   = @($restartIds | Select-Object -Unique)
        }
    }

    return $null
}

function Backup-DeviceRegistryKey {
    param(
        [string]$RegPath,
        [string]$BackupDir,
        [string]$LogFile
    )
    if (-not (Test-Path -LiteralPath $RegPath)) { return '' }
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    $safeName = ($RegPath -replace '[\\\\:*?"<>|]', '_')
    $out = Join-Path $BackupDir ('device-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $safeName + '.reg')
    $hivePath = $RegPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
    & reg.exe export $hivePath $out /y 2>&1 | Out-Null
    if (Test-Path -LiteralPath $out) {
        Write-DeviceLog ("[DEVICE] Registry backup path: " + $out) $LogFile
        return $out
    }
    Write-DeviceLog '[DEVICE] Registry backup path: failed' $LogFile
    return ''
}

function Add-HidusbfLowerFilter {
    param([string]$RegPath)
    if (-not (Test-Path -LiteralPath $RegPath)) { return $false }
    $filters = @()
    try {
        $prop = Get-ItemProperty -LiteralPath $RegPath -Name LowerFilters -ErrorAction SilentlyContinue
        if ($null -ne $prop -and $null -ne $prop.LowerFilters) {
            $filters = @($prop.LowerFilters)
        }
    } catch {}
    if ($filters -contains 'hidusbf') { return $true }
    $filters = @($filters + 'hidusbf')
    Set-ItemProperty -LiteralPath $RegPath -Name LowerFilters -Value $filters -Type MultiString -Force
    return $true
}

function Remove-HidusbfLowerFilter {
    param([string]$RegPath)
    if (-not (Test-Path -LiteralPath $RegPath)) { return $false }
    try {
        $prop = Get-ItemProperty -LiteralPath $RegPath -Name LowerFilters -ErrorAction SilentlyContinue
        if ($null -eq $prop -or $null -eq $prop.LowerFilters) { return $true }
        $filters = @($prop.LowerFilters) | Where-Object { $_ -and $_ -ne 'hidusbf' }
        if ($filters.Count -gt 0) {
            Set-ItemProperty -LiteralPath $RegPath -Name LowerFilters -Value $filters -Type MultiString -Force
        } else {
            Remove-ItemProperty -LiteralPath $RegPath -Name LowerFilters -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        return $false
    }
}

function Restart-PnpDeviceSafe {
    param(
        [string[]]$InstanceIds,
        [string]$LogFile = ''
    )
    foreach ($instanceId in @($InstanceIds | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            Write-DeviceLog ("[DEVICE] Device restart: " + $instanceId) $LogFile
            Disable-PnpDevice -InstanceId $instanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Milliseconds 700
            Enable-PnpDevice -InstanceId $instanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Milliseconds 400
        } catch {
            Write-DeviceLog ("[DEVICE] Device restart failed: " + $instanceId) $LogFile
        }
    }
}
