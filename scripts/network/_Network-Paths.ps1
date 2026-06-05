# Chemins réseau Kojo (PurpleBoost / ProgramData\Kojo)

$script:NetworkDataRoot = $null
$script:NetworkScriptsDir = $null
$script:NetworkLogsDir = $null
$script:NetworkBackupsDir = $null
$script:NetworkBackupDir = $null
$script:NetworkTcpDir = $null
$script:NetworkTcpExe = $null
$script:NetworkTcpUrl = 'https://www.speedguide.net/files/TCPOptimizer.exe'
$script:NetworkStatePath = $null
$script:NetworkProfileStatePath = $null

function Initialize-NetworkPaths {
    param([string]$LogDir = '')
    . (Join-Path $PSScriptRoot '..\_common\Kojo.Json.ps1')
    $root = Get-KojoProgramDataRoot
    $script:NetworkDataRoot = $root
    $script:NetworkScriptsDir = Join-Path $root 'Scripts'
    $script:NetworkLogsDir = if ($LogDir -and (Test-Path -LiteralPath (Split-Path $LogDir -Parent))) { $LogDir } else { Join-Path $root 'Logs' }
    $script:NetworkBackupsDir = Join-Path $root 'Backups'
    $script:NetworkBackupDir = Join-Path $root 'backup'
    $script:NetworkTcpDir = Join-Path $root 'Tools\TCPOptimizer'
    $script:NetworkTcpExe = Join-Path $script:NetworkTcpDir 'TCPOptimizer.exe'
    $script:NetworkStatePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Kojo\network-state.json'
    $script:NetworkProfileStatePath = Join-Path $root 'network-profile-state.json'

    foreach ($d in @($script:NetworkScriptsDir, $script:NetworkLogsDir, $script:NetworkBackupsDir, $script:NetworkBackupDir, $script:NetworkTcpDir)) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Force -Path $d | Out-Null
        }
    }
}

function Get-NetworkStatePath {
    if (-not $script:NetworkStatePath) {
        $script:NetworkStatePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Kojo\network-state.json'
    }
    return $script:NetworkStatePath
}

function Read-NetworkState {
    try {
        $p = Get-NetworkStatePath
        if (-not (Test-Path -LiteralPath $p)) { return @{} }
        $raw = Get-Content -LiteralPath $p -Raw -Encoding UTF8
        if (-not $raw) { return @{} }
        return (ConvertFrom-Json $raw)
    } catch {
        return @{}
    }
}

function Update-NetworkState {
    param([hashtable]$Patch)
    try {
        $p = Get-NetworkStatePath
        $dir = Split-Path -Parent $p
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $prev = Read-NetworkState
        $out = @{}
        foreach ($k in $prev.PSObject.Properties.Name) { $out[$k] = $prev.$k }
        foreach ($k in $Patch.Keys) { $out[$k] = $Patch[$k] }
        ($out | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $p -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

function Test-TcpGamingProfileApplied {
    $checks = @(
        @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Test = { param($v) [uint32]$v -eq [uint32]::MaxValue } },
        @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Test = { param($v) [int]$v -eq 0 } },
        @{ Key = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; Name = 'TcpMaxSynRetransmissions'; Test = { param($v) [int]$v -eq 2 } },
        @{ Key = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'; Name = 'NonSackRttResiliency'; Test = { param($v) [int]$v -eq 0 } }
    )
    foreach ($c in $checks) {
        try {
            $p = Get-ItemProperty -LiteralPath $c.Key -Name $c.Name -ErrorAction Stop
            $val = $p.($c.Name)
            if (-not (& $c.Test $val)) { return $false }
        } catch {
            return $false
        }
    }
    return $true
}

function Get-NetworkProfileStatePath {
    if (-not $script:NetworkProfileStatePath) {
        $script:NetworkProfileStatePath = Join-Path (Get-KojoProgramDataRoot) 'network-profile-state.json'
    }
    return $script:NetworkProfileStatePath
}

function Get-ActiveNetworkProfile {
    try {
        $p = Get-NetworkProfileStatePath
        if (-not (Test-Path -LiteralPath $p)) { return $null }
        $raw = Get-Content -LiteralPath $p -Raw -Encoding UTF8
        if (-not $raw) { return $null }
        $o = ConvertFrom-Json $raw
        if ($o.activeProfile -eq 'gaming' -or $o.activeProfile -eq 'download') {
            return [string]$o.activeProfile
        }
        return $null
    } catch {
        return $null
    }
}

function Set-ActiveNetworkProfile {
    param([string]$Profile)
    try {
        $p = Get-NetworkProfileStatePath
        $dir = Split-Path -Parent $p
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $obj = [ordered]@{
            activeProfile = $Profile
            updatedAt     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $p -Encoding UTF8
        Write-Host "[network] NETWORK_PROFILE_ACTIVE=$Profile"
        return $true
    } catch {
        return $false
    }
}

function Write-ConnectionProfilesLog {
    param([string]$Line)
    if (-not $script:NetworkLogsDir) { return }
    $path = Join-Path $script:NetworkLogsDir 'connection-profiles.log'
    $entry = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Line
    Add-Content -LiteralPath $path -Value $entry -Encoding UTF8
}
