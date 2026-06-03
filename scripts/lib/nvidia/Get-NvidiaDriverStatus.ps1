#Requires -Version 5.1
<#
.SYNOPSIS
  Vérification silencieuse : GPU NVIDIA, pilote installé, dernière version Game Ready (cache 6 h).
#>
param(
    [string]$AppRoot = '',
    [string]$CachePath = '',
    [int]$MaxAgeHours = 6,
    [int]$WebTimeoutSec = 10,
    [switch]$Force
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
} catch {}

function Resolve-AppRoot {
    param([string]$Root)
    if ($Root -and (Test-Path -LiteralPath $Root)) {
        return (Resolve-Path -LiteralPath $Root).Path
    }
    $here = $PSScriptRoot
    if ($here) {
        $c = Split-Path -Parent $here
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'Unreal.hta'))) { return $c }
        if ($c) { return $c }
    }
    return ''
}

function Get-PurpleBoostDir {
    $pd = $env:ProgramData
    if (-not $pd) { $pd = 'C:\ProgramData' }
    $dir = Join-Path $pd 'PurpleBoost'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Write-NvCheckLog {
    param([string]$Line, [string]$LogPath)
    if (-not $LogPath) { return }
    try {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -LiteralPath $LogPath -Value "[$ts] $Line" -Encoding UTF8
    } catch {}
}

function Compare-DriverVersion {
    param([string]$Installed, [string]$Latest)
    if (-not $Installed -or -not $Latest) { return 0 }
    $a = ($Installed -replace '[^0-9.]', '').Split('.')
    $b = ($Latest -replace '[^0-9.]', '').Split('.')
    $n = [Math]::Max($a.Count, $b.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $av = 0; $bv = 0
        if ($i -lt $a.Count -and $a[$i] -match '^\d+$') { $av = [int]$a[$i] }
        if ($i -lt $b.Count -and $b[$i] -match '^\d+$') { $bv = [int]$b[$i] }
        if ($av -lt $bv) { return -1 }
        if ($av -gt $bv) { return 1 }
    }
    return 0
}

function Convert-NvidiaDrvWmi([string]$raw) {
    if (-not $raw) { return '' }
    if ($raw -match '^(\d+)\.(\d+)\.(\d+)\.(\d+)$') {
        if ($Matches[3] -eq '15' -and $Matches[4].Length -ge 4) {
            return ('5' + $Matches[4].Substring(0, 2) + '.' + $Matches[4].Substring($Matches[4].Length - 2))
        }
    }
    if ($raw -match '([0-9]{3}\.[0-9]{2})') { return $Matches[1] }
    return ''
}

function Get-NvidiaOsIds {
    try {
        $bv = [Environment]::OSVersion.Version
        if ($bv.Major -ge 10 -and $bv.Build -ge 22000) { return @(135, 57) }
    } catch {}
    return @(57, 135)
}

function Get-NvidiaGpuFamily {
    param([string]$GpuName)
    $n = ($GpuName -replace '(?i)^NVIDIA\s+', '').Trim().ToUpperInvariant()
    $n = $n -replace '\s+', ' '
    if ($n -match 'RTX\s*50|5090|5080|5070') {
        return @{ family = 'GeForce RTX 50 Series'; pfids = @(1030, 1029, 1028, 995, 994, 999) }
    }
    if ($n -match 'RTX\s*40|4090|4080|4070|4060|4050') {
        return @{ family = 'GeForce RTX 40 Series'; pfids = @(995, 994, 1030, 1029, 1028, 999) }
    }
    if ($n -match 'RTX\s*30|3090|3080|3070|3060|3050') {
        return @{ family = 'GeForce RTX 30 Series'; pfids = @(935, 932, 930, 919, 918, 999) }
    }
    if ($n -match 'RTX\s*20|2080|2070|2060') {
        return @{ family = 'GeForce RTX 20 Series'; pfids = @(877, 876, 875, 999) }
    }
    if ($n -match 'GTX\s*16|1660|1650') {
        return @{ family = 'GeForce GTX 16 Series'; pfids = @(860, 858, 857, 999) }
    }
    if ($n -match 'GTX\s*10|1080|1070|1060|1050') {
        return @{ family = 'GeForce GTX 10 Series'; pfids = @(816, 815, 814, 999) }
    }
    return @{ family = 'GeForce'; pfids = @(995, 994, 1030, 1029, 1028, 1019, 1018, 935, 932, 930, 919, 918, 999) }
}

function Get-InstalledNvidiaGpu {
    $gpuName = ''
    $installed = ''
    $raw = ''
    $pnpDeviceId = ''

    try {
        $adapters = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)NVIDIA' })
        $best = $adapters | Sort-Object {
            $p = 0
            if ($_.Name -match '(?i)NVIDIA') { $p += 100 }
            if ($_.Name -notmatch '(?i)Microsoft|Remote|Virtual|Basic') { $p += 50 }
            $p
        } -Descending | Select-Object -First 1
        if ($best) {
            $gpuName = [string]$best.Name
            $raw = [string]$best.DriverVersion
            $pnpDeviceId = [string]$best.PNPDeviceID
        }
    } catch {}

    try {
        $smi = & nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>$null
        if ($smi) {
            $line = @($smi -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1)
            if ($line) {
                $parts = $line -split ',', 2
                if ($parts.Count -ge 1 -and -not $gpuName) { $gpuName = $parts[0].Trim() }
                if ($parts.Count -ge 2 -and $parts[1] -match '([0-9]{3}\.[0-9]{2})') {
                    $installed = $Matches[1]
                }
            }
        }
    } catch {}

    if (-not $installed) {
        $regKeys = @(
            @{ k = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm'; v = 'DisplayVersion' },
            @{ k = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm'; v = 'DriverVersion' },
            @{ k = 'HKLM:\SOFTWARE\NVIDIA Corporation\Installer'; v = 'LastInstallerVersion' },
            @{ k = 'HKLM:\SOFTWARE\NVIDIA Corporation\Installer2'; v = 'Version' }
        )
        foreach ($rk in $regKeys) {
            try {
                $rv = (Get-ItemProperty -LiteralPath $rk.k -ErrorAction Stop).($rk.v)
                if ($rv -match '([0-9]{3}\.[0-9]{2})') { $installed = $Matches[1]; break }
            } catch {}
        }
    }

    if (-not $installed -and $raw) {
        $cv = Convert-NvidiaDrvWmi $raw
        if ($cv) { $installed = $cv }
    }

    return @{
        gpuName           = $gpuName
        installedVersion  = $installed
        pnpDeviceId       = $pnpDeviceId
    }
}

function Get-VersionFromAjaxBody {
    param([string]$Body, [string]$Url)
    if (-not $Body) { return '' }
    if ($Body -match '"Version"\s*:\s*"([0-9]+\.[0-9]+)"') { return $Matches[1] }
    if ($Body -match '"DisplayVersion"\s*:\s*"([0-9]+\.[0-9]+)"') { return $Matches[1] }
    if ($Url -match '/([0-9]{2,3}\.[0-9]{2})/') { return $Matches[1] }
    if ($Url -match '([0-9]{2,3}\.[0-9]{2})-desktop') { return $Matches[1] }
    try {
        $j = $Body | ConvertFrom-Json
        if ($j.IDS -and @($j.IDS).Count -gt 0) {
            $di = $j.IDS[0].downloadInfo
            if ($di.Version -match '([0-9]+\.[0-9]+)') { return $Matches[1] }
            if ($di.DisplayVersion -match '([0-9]+\.[0-9]+)') { return $Matches[1] }
        }
    } catch {}
    return ''
}

function Try-NvcleanstallCacheVersion {
    $roots = @(
        "$env:LOCALAPPDATA\NVCleanstall",
        "$env:APPDATA\NVCleanstall",
        "$env:LOCALAPPDATA\TechPowerUp\NVCleanstall"
    )
    $cfgNames = @('*.json', '*.xml', 'NVCleanstall.ini', 'settings.ini')
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        try {
            $files = Get-ChildItem -LiteralPath $root -Recurse -Include $cfgNames -ErrorAction SilentlyContinue |
                Select-Object -First 30
            foreach ($f in $files) {
                try {
                    $t = [IO.File]::ReadAllText($f.FullName)
                    if ($t -match '"Version"\s*:\s*"([0-9]{3}\.[0-9]{2})"') {
                        return @{ version = $Matches[1]; source = 'nvcleanstall-cache' }
                    }
                    if ($t -match '"DisplayVersion"\s*:\s*"([0-9]{3}\.[0-9]{2})"') {
                        return @{ version = $Matches[1]; source = 'nvcleanstall-cache' }
                    }
                    if ($t -match '([0-9]{3}\.[0-9]{2})') {
                        return @{ version = $Matches[1]; source = 'nvcleanstall-cache' }
                    }
                } catch {}
            }
        } catch {}
    }
    return $null
}

function Get-LatestNvidiaDriverVersion {
    param(
        [string]$GpuName,
        [int]$TimeoutSec = 10
    )

    $hit = Try-NvcleanstallCacheVersion
    if ($hit -and $hit.version) { return $hit }

    $family = Get-NvidiaGpuFamily -GpuName $GpuName
    $pfids = @($family.pfids | Select-Object -Unique)
    $osIds = Get-NvidiaOsIds
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
    $lastErr = ''

    foreach ($os in $osIds) {
        foreach ($pf in $pfids) {
            $api = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php' +
                '?beta=null&dch=1&dltype=-1&func=DriverManualLookup&isWHQL=1&languageCode=1033' +
                '&numberOfResults=1&sort1=0&osID=' + $os + '&pfid=' + $pf
            try {
                $resp = Invoke-WebRequest -Uri $api -Method Get -TimeoutSec $TimeoutSec -UseBasicParsing -Headers @{ 'User-Agent' = $ua }
                $body = [string]$resp.Content
                if ($body -notmatch 'DownloadURL') { continue }
                $url = ''
                if ($body -match '"DownloadURL"\s*:\s*"([^"]+)"') {
                    $url = ($Matches[1] -replace '\\/', '/')
                }
                $ver = Get-VersionFromAjaxBody -Body $body -Url $url
                if ($ver) {
                    return @{ version = $ver; source = 'nvidia-web' }
                }
            } catch {
                if (-not $lastErr) { $lastErr = $_.Exception.Message }
            }
        }
    }

    return @{ version = ''; source = ''; error = $(if ($lastErr) { $lastErr } else { 'NVIDIA AjaxDriverService: aucune version' }) }
}

function Read-CacheFile([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
        if (-not $raw.Trim()) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch { return $null }
}

function Write-ResultFile {
    param([hashtable]$Result, [string]$Path)
    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Result | ConvertTo-Json -Compress)
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$app = Resolve-AppRoot $AppRoot
$pbDir = Get-PurpleBoostDir
if (-not $CachePath) { $CachePath = Join-Path $pbDir 'nvidia-driver-latest.json' }
$logPath = if ($app) { Join-Path $app 'logs\nvidia-driver-check.log' } else { Join-Path $pbDir 'logs\nvidia-driver-check.log' }

$previousCache = Read-CacheFile $CachePath
if (-not $Force -and $previousCache -and $previousCache.checkedAt) {
    try {
        $t = [datetime]::Parse($previousCache.checkedAt)
        if (((Get-Date) - $t).TotalHours -lt $MaxAgeHours) {
            Write-NvCheckLog "cache_hit age_hours=$([math]::Round(((Get-Date)-$t).TotalHours,2))" $logPath
            Write-Output ($previousCache | ConvertTo-Json -Compress)
            exit 0
        }
    } catch {}
}

$gpu = Get-InstalledNvidiaGpu
$familyInfo = Get-NvidiaGpuFamily -GpuName $gpu.gpuName
$latestVer = ''
$source = ''
$errorMsg = ''
$status = 'unknown'
$freshCheckFailed = $false

Write-NvCheckLog ("check_start gpu=" + $gpu.gpuName + " installed=" + $gpu.installedVersion) $logPath

if (-not $gpu.gpuName) {
    $status = 'no_gpu'
    $errorMsg = 'Aucun GPU NVIDIA détecté.'
} else {
    $lookup = Get-LatestNvidiaDriverVersion -GpuName $gpu.gpuName -TimeoutSec $WebTimeoutSec
    if ($lookup.version) {
        $latestVer = $lookup.version
        $source = $lookup.source
        $status = 'ok'
    } else {
        $errorMsg = if ($lookup.error) { $lookup.error } else { 'Impossible de vérifier la dernière version' }
        if ($previousCache -and $previousCache.latestVersion) {
            $latestVer = [string]$previousCache.latestVersion
            $source = 'cache'
            $freshCheckFailed = $true
            Write-NvCheckLog ("stale_cache_used latest=" + $latestVer) $logPath
        }
    }
}

$updateAvailable = $false
if ($status -eq 'ok' -and $gpu.installedVersion -and $latestVer) {
    $updateAvailable = (Compare-DriverVersion $gpu.installedVersion $latestVer) -lt 0
} elseif ($freshCheckFailed -and $gpu.installedVersion -and $latestVer) {
    $updateAvailable = (Compare-DriverVersion $gpu.installedVersion $latestVer) -lt 0
}

$result = [ordered]@{
    gpuName           = $gpu.gpuName
    gpuFamily         = $familyInfo.family
    installedVersion  = $gpu.installedVersion
    latestVersion     = if ($latestVer) { $latestVer } else { $null }
    updateAvailable   = $updateAvailable
    status            = $status
    checkedAt         = (Get-Date).ToString('o')
    source            = $source
    error             = $errorMsg
    freshCheckFailed  = $freshCheckFailed
    pnpDeviceId       = $gpu.pnpDeviceId
}

$sw.Stop()
Write-NvCheckLog ("check_done ms=" + $sw.ElapsedMilliseconds + " status=" + $status + " latest=" + $latestVer + " source=" + $source) $logPath
if ($errorMsg) { Write-NvCheckLog ("error=" + $errorMsg) $logPath }

Write-ResultFile -Result $result -Path $CachePath
Write-Output ($result | ConvertTo-Json -Compress)
exit 0
