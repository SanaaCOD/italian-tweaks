#Requires -Version 5.1
<#
.SYNOPSIS
  HIDUSBF registry probe: mandatory BEFORE snapshot, manual apply, AFTER snapshot, diff.
#>
param(
    [string]$AppRoot = '',
    [string]$DeviceInstanceId = '',
    [string]$Vid = '',
    [Alias('Pid')]
    [string]$DevicePid = '',
    [ValidateSet('Before', 'After')]
    [string]$Phase = 'Before',
    [int]$Rate = 0
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'Controller-Hidusbf-Common.ps1')

function Write-ProbeLog {
    param([string]$Line, [string]$LogFile)
    Write-DeviceLog ("[HIDUSBF-PROBE] " + $Line) $LogFile
}

function Format-RegValue {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [array]) { return '[' + ($Value | ForEach-Object { "$_" }) -join ', ' + ']' }
    if ($Value -is [byte[]]) { return '0x' + ([BitConverter]::ToString($Value) -replace '-', '') }
    return [string]$Value
}

function Test-ProbeClassKeyRelevant {
    param(
        [string]$RegPath,
        [string]$VidU,
        [string]$PidU
    )
    $pathU = ($RegPath + '').ToUpperInvariant()
    if ($pathU -match ('VID_' + [regex]::Escape($VidU))) { return $true }
    if ($pathU -match ('PID_' + [regex]::Escape($PidU))) { return $true }
    if ($pathU -match 'HIDUSBF') { return $true }

    if (-not (Test-Path -LiteralPath $RegPath)) { return $false }
    try {
        $props = Get-ItemProperty -LiteralPath $RegPath -ErrorAction Stop
        foreach ($name in $props.PSObject.Properties.Name) {
            if ($name -match '^PS') { continue }
            if ($name -match '(?i)LowerFilters|UpperFilters|Device Parameters|Polling|Rate|bInterval') { return $true }
            $val = Format-RegValue $props.$name
            $valU = $val.ToUpperInvariant()
            if ($valU -match ('VID_' + [regex]::Escape($VidU)) -or $valU -match ('PID_' + [regex]::Escape($PidU))) { return $true }
            if ($valU -match 'HIDUSBF') { return $true }
        }
    } catch {}
    return $false
}

function Test-ProbePathIncluded {
    param(
        [string]$RegPath,
        [string]$VidU,
        [string]$PidU,
        [bool]$IsClassSubtree
    )
    $pathU = ($RegPath + '').ToUpperInvariant()
    if ($pathU -match '\\ENUM\\USB\\' -and $pathU -match ('VID_' + [regex]::Escape($VidU) + '&PID_' + [regex]::Escape($PidU))) { return $true }
    if ($pathU -match '\\ENUM\\HID\\' -and $pathU -match ('VID_' + [regex]::Escape($VidU) + '&PID_' + [regex]::Escape($PidU))) { return $true }
    if ($pathU -match '\\SERVICES\\' -and $pathU -match 'HIDUSBF') { return $true }
    if ($pathU -match '\\CONTROL\\HIDUSBF') { return $true }
    if ($IsClassSubtree) { return (Test-ProbeClassKeyRelevant -RegPath $RegPath -VidU $VidU -PidU $PidU) }
    return $false
}

function Export-RegistryKeyRecursive {
    param(
        [string]$RegPath,
        [int]$Depth,
        [int]$MaxDepth,
        [string]$VidU,
        [string]$PidU,
        [bool]$IsClassSubtree,
        [System.Collections.Generic.List[object]]$Collector
    )
    if ($Depth -gt $MaxDepth) { return }
    if (-not $RegPath) { return }

    $includeSelf = Test-ProbePathIncluded -RegPath $RegPath -VidU $VidU -PidU $PidU -IsClassSubtree $IsClassSubtree
    if ($includeSelf) {
        $values = @{}
        if (Test-Path -LiteralPath $RegPath) {
            try {
                $props = Get-ItemProperty -LiteralPath $RegPath -ErrorAction Stop
                foreach ($name in $props.PSObject.Properties.Name) {
                    if ($name -match '^PS') { continue }
                    if ($IsClassSubtree) {
                        $interestingName = $name -match '(?i)LowerFilters|UpperFilters|Device Parameters|Polling|Rate|bInterval|HardwareID|CompatibleIDs|DeviceDesc'
                        $val = Format-RegValue $props.$name
                        $valU = $val.ToUpperInvariant()
                        $interestingVal = $valU -match ('VID_' + [regex]::Escape($VidU)) -or $valU -match ('PID_' + [regex]::Escape($PidU)) -or $valU -match 'HIDUSBF'
                        if (-not $interestingName -and -not $interestingVal) { continue }
                    }
                    $values[$name] = Format-RegValue $props.$name
                }
            } catch {}
        }
        $Collector.Add(@{ Path = $RegPath; Values = $values }) | Out-Null
    }

    if (-not (Test-Path -LiteralPath $RegPath)) { return }
    try {
        Get-ChildItem -LiteralPath $RegPath -ErrorAction Stop | ForEach-Object {
            if ($_.PSChildName -match '^PS') { return }
            $child = Join-Path $RegPath $_.PSChildName
            $childIsClass = $IsClassSubtree -or ($RegPath -match '(?i)\\Control\\Class$')
            Export-RegistryKeyRecursive -RegPath $child -Depth ($Depth + 1) -MaxDepth $MaxDepth -VidU $VidU -PidU $PidU -IsClassSubtree $childIsClass -Collector $Collector
        }
    } catch {}
}

function Get-ProbeRegistryRoots {
    param([string]$VidU, [string]$PidU)
    $roots = New-Object System.Collections.Generic.List[string]

    foreach ($enumRoot in @('USB', 'HID')) {
        $enumBase = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $enumRoot
        if (-not (Test-Path -LiteralPath $enumBase)) { continue }
        try {
            Get-ChildItem -LiteralPath $enumBase -ErrorAction Stop | ForEach-Object {
                $child = $_.PSChildName
                if ($child -notmatch ('(?i)^VID_' + [regex]::Escape($VidU) + '&PID_' + [regex]::Escape($PidU))) { return }
                $roots.Add((Join-Path $enumBase $child)) | Out-Null
            }
        } catch {}
    }

    $svcBase = 'HKLM:\SYSTEM\CurrentControlSet\Services'
    if (Test-Path -LiteralPath $svcBase) {
        Get-ChildItem -LiteralPath $svcBase -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.PSChildName -match '(?i)^hidusbf') {
                $roots.Add((Join-Path $svcBase $_.PSChildName)) | Out-Null
            }
        }
    }

    $ctrlBase = 'HKLM:\SYSTEM\CurrentControlSet\Control'
    if (Test-Path -LiteralPath $ctrlBase) {
        Get-ChildItem -LiteralPath $ctrlBase -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.PSChildName -match '(?i)^hidusbf') {
                $roots.Add((Join-Path $ctrlBase $_.PSChildName)) | Out-Null
            }
        }
    }

    $classRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class'
    if (Test-Path -LiteralPath $classRoot) {
        $roots.Add($classRoot) | Out-Null
    }

    return @($roots | Select-Object -Unique)
}

function New-RegistrySnapshot {
    param(
        [string]$Vid,
        [string]$DevicePid,
        [int]$Rate,
        [string]$PhaseLabel
    )
    $vidU = ($Vid + '').ToUpperInvariant()
    $pidU = ($DevicePid + '').ToUpperInvariant()
    $collector = New-Object System.Collections.Generic.List[object]
    $roots = Get-ProbeRegistryRoots -VidU $vidU -PidU $pidU

    foreach ($root in $roots) {
        $isClass = $root -match '(?i)\\Control\\Class$'
        $maxDepth = if ($isClass) { 4 } else { 12 }
        Export-RegistryKeyRecursive -RegPath $root -Depth 0 -MaxDepth $maxDepth -VidU $vidU -PidU $pidU -IsClassSubtree $isClass -Collector $collector
    }

    return @{
        GeneratedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Phase       = $PhaseLabel
        Rate        = $Rate
        Vid         = $vidU
        Pid         = $pidU
        EntryCount  = $collector.Count
        Entries     = @($collector.ToArray())
        Roots       = @($roots)
    }
}

function Save-JsonFile {
    param([object]$Payload, [string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Payload | ConvertTo-Json -Depth 20 -Compress:$false
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Export-SnapshotToRegFile {
    param(
        [object]$Snapshot,
        [string]$OutRegFile
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Windows Registry Editor Version 5.00') | Out-Null
    $lines.Add('') | Out-Null

    foreach ($entry in @($Snapshot.Entries)) {
        $regPath = [string]$entry.Path
        if (-not $regPath) { continue }
        $winPath = $regPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
        $lines.Add('[' + $winPath + ']') | Out-Null
        foreach ($prop in @($entry.Values.Keys)) {
            $val = [string]$entry.Values[$prop]
            if ($val -match '^\[') {
                $lines.Add('"' + $prop + '"=' + $val) | Out-Null
            } else {
                $lines.Add('"' + $prop + '"="' + ($val -replace '\\', '\\') + '"') | Out-Null
            }
        }
        $lines.Add('') | Out-Null
    }

    $dir = Split-Path -Parent $OutRegFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllLines($OutRegFile, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Import-SnapshotFromJsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-ValueMapFromSnapshotEntry {
    param($ValuesObj)
    $map = @{}
    if (-not $ValuesObj) { return $map }
    foreach ($p in $ValuesObj.PSObject.Properties) {
        if ($p.Name -match '^PS') { continue }
        $map[$p.Name] = [string]$p.Value
    }
    return $map
}

function Compare-RegistrySnapshotsJson {
    param(
        [object]$BeforeSnap,
        [object]$AfterSnap,
        [string]$DiffLogFile,
        [string]$DiffJsonFile,
        [string]$VidU,
        [string]$PidU
    )
    $beforeMap = @{}
    $afterMap = @{}
    foreach ($e in @($BeforeSnap.Entries)) {
        $beforeMap[[string]$e.Path] = Get-ValueMapFromSnapshotEntry -ValuesObj $e.Values
    }
    foreach ($e in @($AfterSnap.Entries)) {
        $afterMap[[string]$e.Path] = Get-ValueMapFromSnapshotEntry -ValuesObj $e.Values
    }

    $allPaths = @($beforeMap.Keys + $afterMap.Keys | Select-Object -Unique)
    $changes = New-Object System.Collections.Generic.List[object]
    $diffLines = New-Object System.Collections.Generic.List[string]
    $diffLines.Add('# HIDUSBF registry diff ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-Null
    $diffLines.Add('# Vid=' + $VidU + ' Pid=' + $PidU) | Out-Null

    foreach ($path in $allPaths) {
        $bProps = if ($beforeMap.ContainsKey($path)) { $beforeMap[$path] } else { @{} }
        $aProps = if ($afterMap.ContainsKey($path)) { $afterMap[$path] } else { @{} }
        $propNames = @($bProps.Keys + $aProps.Keys | Select-Object -Unique)

        $keyChanged = $false
        foreach ($prop in $propNames) {
            $bVal = if ($bProps.ContainsKey($prop)) { $bProps[$prop] } else { '(absent)' }
            $aVal = if ($aProps.ContainsKey($prop)) { $aProps[$prop] } else { '(absent)' }
            if ($bVal -ne $aVal) {
                if (-not $keyChanged) {
                    $diffLines.Add('') | Out-Null
                    $diffLines.Add('[' + $path + ']') | Out-Null
                    $keyChanged = $true
                }
                $diffLines.Add('  ' + $prop + ': ' + $bVal + ' -> ' + $aVal) | Out-Null
                $changes.Add(@{
                    Key      = $path
                    Property = $prop
                    Before   = $bVal
                    After    = $aVal
                }) | Out-Null
            }
        }
    }

    $count = $changes.Count
    $diffLines.Add('') | Out-Null
    $diffLines.Add('# Differences count: ' + $count) | Out-Null

    $dir = Split-Path -Parent $DiffLogFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllLines($DiffLogFile, $diffLines, [System.Text.UTF8Encoding]::new($false))

    $beforeCount = 0
    $afterCount = 0
    try { $beforeCount = [int]$BeforeSnap.EntryCount } catch {}
    if ($beforeCount -le 0 -and $BeforeSnap.Entries) { $beforeCount = @($BeforeSnap.Entries).Count }
    try { $afterCount = [int]$AfterSnap.EntryCount } catch {}
    if ($afterCount -le 0 -and $AfterSnap.Entries) { $afterCount = @($AfterSnap.Entries).Count }

    $payload = @{
        GeneratedAt      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        HasDiff          = ($count -gt 0)
        ChangeCount      = $count
        Changes          = @($changes.ToArray())
        BeforeEntryCount = $beforeCount
        AfterEntryCount  = $afterCount
    }
    Save-JsonFile -Payload $payload -Path $DiffJsonFile
    return $count
}

function Write-ProbeResult {
    param(
        [bool]$Success,
        [string]$Code,
        [string]$Message,
        [int]$DifferenceCount,
        [string]$ResultPath
    )
    $payload = @{
        Success          = $Success
        Code             = $Code
        Message          = $Message
        DifferenceCount  = $DifferenceCount
        Phase            = $Phase
        Rate             = $Rate
    }
    Save-JsonFile -Payload $payload -Path $ResultPath
}

$app = Resolve-UnrealAppRoot $AppRoot
if (-not $app) { exit 9 }

$logDir = Join-Path $app 'logs'
$probeLog = Join-Path $logDir 'controller-overclocker.log'
$beforeJson = Join-Path $logDir 'hidusbf-probe-before.json'
$afterJson = Join-Path $logDir 'hidusbf-probe-after.json'
$beforeReg = Join-Path $logDir 'hidusbf-probe-before.reg'
$afterReg = Join-Path $logDir 'hidusbf-probe-after.reg'
$diffLog = Join-Path $logDir 'hidusbf-registry-diff.log'
$diffJson = Join-Path $logDir 'hidusbf-registry-diff.json'
$resultJson = Join-Path $logDir 'hidusbf-probe-result.json'
$metaJson = Join-Path $logDir 'hidusbf-probe-meta.json'

$vidU = ($Vid + '').ToUpperInvariant()
$pidU = ($DevicePid + '').ToUpperInvariant()
if (-not $vidU) { $vidU = '054C' }
if (-not $pidU) { $pidU = '0CE6' }

if ($Phase -eq 'Before') {
    Write-ProbeLog 'Snapshot BEFORE started' $probeLog
    Write-ProbeLog ("Target VID/PID=" + $vidU + '/' + $pidU + " Rate=" + $Rate) $probeLog

    $snap = New-RegistrySnapshot -Vid $vidU -DevicePid $pidU -Rate $Rate -PhaseLabel 'Before'
    Save-JsonFile -Payload $snap -Path $beforeJson
    Export-SnapshotToRegFile -Snapshot $snap -OutRegFile $beforeReg

    $meta = @{
        BeforeCapturedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Rate             = $Rate
        Vid              = $vidU
        Pid              = $pidU
        DeviceInstanceId = $DeviceInstanceId
        BeforeJson       = $beforeJson
        BeforeReg        = $beforeReg
    }
    Save-JsonFile -Payload $meta -Path $metaJson

    Write-ProbeLog ("Snapshot BEFORE saved: " + $beforeJson) $probeLog
    Write-ProbeLog ("Snapshot BEFORE reg saved: " + $beforeReg) $probeLog
    Write-ProbeLog ("Entries captured: " + $snap.EntryCount) $probeLog
    Write-ProbeLog 'Waiting manual HIDUSBF apply' $probeLog

    Write-ProbeResult -Success $true -Code 'BEFORE_SAVED' -Message 'Snapshot AVANT termine.' -DifferenceCount 0 -ResultPath $resultJson
    exit 0
}

# --- Phase After ---
Write-ProbeLog 'Snapshot AFTER started' $probeLog

if (-not (Test-Path -LiteralPath $beforeJson)) {
    Write-ProbeLog 'Snapshot BEFORE missing — diff aborted' $probeLog
    Write-ProbeResult -Success $false -Code 'BEFORE_MISSING' -Message 'Snapshot AVANT manquant — lance d abord Analyser HIDUSBF.' -DifferenceCount -1 -ResultPath $resultJson
    exit 1
}

$beforeSnap = Import-SnapshotFromJsonFile -Path $beforeJson
if (-not $beforeSnap) {
    Write-ProbeLog 'Snapshot BEFORE unreadable — diff aborted' $probeLog
    Write-ProbeResult -Success $false -Code 'BEFORE_INVALID' -Message 'Snapshot AVANT illisible — relance Analyser HIDUSBF.' -DifferenceCount -1 -ResultPath $resultJson
    exit 1
}

$afterSnap = New-RegistrySnapshot -Vid $vidU -DevicePid $pidU -Rate $Rate -PhaseLabel 'After'
Save-JsonFile -Payload $afterSnap -Path $afterJson
Export-SnapshotToRegFile -Snapshot $afterSnap -OutRegFile $afterReg

Write-ProbeLog ("Snapshot AFTER saved: " + $afterJson) $probeLog
Write-ProbeLog ("Snapshot AFTER reg saved: " + $afterReg) $probeLog
Write-ProbeLog ("Entries captured: " + $afterSnap.EntryCount) $probeLog

$diffCount = Compare-RegistrySnapshotsJson -BeforeSnap $beforeSnap -AfterSnap $afterSnap -DiffLogFile $diffLog -DiffJsonFile $diffJson -VidU $vidU -PidU $pidU

Write-ProbeLog ("Diff generated: " + $diffLog) $probeLog
Write-ProbeLog ("Diff JSON: " + $diffJson) $probeLog
Write-ProbeLog ("Differences count: " + $diffCount) $probeLog

if ($diffCount -gt 0) {
  try {
    $sigPath = Join-Path $logDir 'hidusbf-probe-signature.json'
    $raw = [System.IO.File]::ReadAllText($diffJson)
    $dj = $raw | ConvertFrom-Json
    $rateKeys = New-Object System.Collections.Generic.List[object]
    foreach ($ch in @($dj.Changes)) {
      if ($ch.Property -match '(?i)LowerFilters|UpperFilters|rate|polling|binterval|patch') {
        $rateKeys.Add(@{ Name = $ch.Property; Path = $ch.Key; After = $ch.After }) | Out-Null
      }
    }
    if ($rateKeys.Count -gt 0) {
      Save-JsonFile -Payload (@{ UpdatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Rate = $Rate; RateKeys = @($rateKeys) }) -Path $sigPath
      Write-ProbeLog ("Probe signature: " + $sigPath) $probeLog
    }
  } catch {
    Write-ProbeLog ("Probe signature error: " + $_.Exception.Message) $probeLog
  }
  Write-ProbeResult -Success $true -Code 'DIFF_OK' -Message ('Diff genere — ' + $diffCount + ' changement(s).') -DifferenceCount $diffCount -ResultPath $resultJson
  exit 0
}

Write-ProbeResult -Success $true -Code 'DIFF_EMPTY' -Message 'Aucune difference detectee. Verifie Filter? Yes et Rate 1000/8000 dans HIDUSBF avant le snapshot APRES.' -DifferenceCount 0 -ResultPath $resultJson
exit 2
