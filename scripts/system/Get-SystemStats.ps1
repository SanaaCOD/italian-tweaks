#Requires -Version 5.1
param([string]$AppRoot = '', [string]$LogDir = '')

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Resolve-ItalianTweaksRoot -AppRoot $AppRoot
if (-not $LogDir) { $LogDir = Join-Path $root 'logs' }
$outFile = Join-Path $LogDir 'home-stats-result.json'
$collectScript = Join-Path $PSScriptRoot 'Collect-HomeStats.ps1'
if (-not (Test-Path -LiteralPath $collectScript)) {
    Write-ItalianTweaksLog -LogDir $LogDir -Name 'system' -Line "Collect-HomeStats introuvable: $collectScript"
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
        -File $collectScript -AppRoot $root -LogDir $LogDir -OutPath $outFile -GpuTimeoutSec 4 | Out-Null
}

$live = @{ cpu = $null; gpu = $null; ram = $null }
if (Test-Path -LiteralPath $outFile) {
    try {
        $live = Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {}
}

function Get-CpuName {
    try {
        return ([string](Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)).Trim()
    } catch { return 'CPU' }
}

function Get-GpuName {
    try {
        $ad = Get-CimInstance Win32_VideoController | Where-Object {
            $_.Name -and $_.Name -notmatch 'Microsoft|Basic|Remote'
        } | Select-Object -First 1
        if ($ad) { return [string]$ad.Name }
    } catch {}
    return 'GPU'
}

function Get-RamStatic {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $total = [double]$os.TotalVisibleMemorySize * 1024
        $modules = @(Get-CimInstance Win32_PhysicalMemory)
        $modStr = ($modules | ForEach-Object { "$($_.Manufacturer) $($_.PartNumber)" }) -join ' | '
        $speed = if ($modules.Count) { "$($modules[0].Speed) MHz" } else { '' }
        return @{
            modules = ($modStr -replace '\s+', ' ').Trim()
            speed = "$speed - $([math]::Round($total / 1GB, 1)) Go"
            xmp = 'N/D'
        }
    } catch {
        return @{ modules = ''; speed = ''; xmp = 'N/D' }
    }
}

$os = Get-CimInstance Win32_OperatingSystem
$uptime = ''
try {
    $span = (Get-Date) - $os.LastBootUpTime
    $uptime = '{0}j {1}h {2}m' -f $span.Days, $span.Hours, $span.Minutes
} catch {}

$ramStatic = Get-RamStatic
$data = [ordered]@{
    cpu = @{
        usage = if ($null -ne $live.cpu) { [double]$live.cpu } else { $null }
        name  = Get-CpuName
    }
    gpu = @{
        usage = if ($null -ne $live.gpu) { [double]$live.gpu } else { $null }
        name  = Get-GpuName
    }
    ram = @{
        usage   = if ($null -ne $live.ram) { [double]$live.ram } else { $null }
        modules = $ramStatic.modules
        speed   = $ramStatic.speed
        xmp     = $ramStatic.xmp
    }
    windows = @{ caption = [string]$os.Caption; build = [string]$os.BuildNumber; version = [string]$os.Version }
    uptime = $uptime
    timestamp = (Get-Date).ToString('dd/MM/yyyy - HH:mm')
    updatedAt = if ($live.updatedAt) { $live.updatedAt } else { $null }
}

Write-ItalianTweaksLog -LogDir $LogDir -Name 'system' -Line ("stats cpu=$($data.cpu.usage) gpu=$($data.gpu.usage) ram=$($data.ram.usage)")
Write-ItalianTweaksJson -Ok $true -Status 'success' -Action 'GetSystemStats' -Message 'Statistiques système' -Data $data
