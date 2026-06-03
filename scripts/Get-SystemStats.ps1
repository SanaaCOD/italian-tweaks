#Requires -Version 5.1
param(
    [string]$AppRoot = '',
    [string]$LogDir = ''
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-CpuUsage {
    try {
        $c = Get-CimInstance Win32_Processor | Select-Object -First 1
        $name = [string]$c.Name
        $load = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -ExpandProperty PercentProcessorTime -First 1
        return @{ usage = [math]::Round([double]$load, 1); name = $name.Trim() }
    } catch {
        return @{ usage = 0; name = 'CPU' }
    }
}

function Get-RamInfo {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $total = [double]$os.TotalVisibleMemorySize * 1024
        $free = [double]$os.FreePhysicalMemory * 1024
        $used = $total - $free
        $pct = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }
        $modules = @(Get-CimInstance Win32_PhysicalMemory)
        $modStr = ($modules | ForEach-Object { $_.Manufacturer + ' ' + $_.PartNumber }) -join ' | '
        $speed = if ($modules.Count) { [string]$modules[0].Speed + ' MHz' } else { '' }
        $totalGb = [math]::Round($total / 1GB, 1)
        return @{
            usage = $pct
            modules = ($modStr -replace '\s+', ' ').Trim()
            speed = "$speed - $totalGb Go"
            xmp = 'N/D'
        }
    } catch {
        return @{ usage = 0; modules = ''; speed = ''; xmp = '—' }
    }
}

function Get-GpuInfo {
    $gpu = @{ usage = $null; name = 'GPU non détecté' }
    try {
        $ad = Get-CimInstance Win32_VideoController | Where-Object {
            $_.Name -and $_.Name -notmatch 'Microsoft|Basic'
        } | Select-Object -First 1
        if ($ad) { $gpu.name = [string]$ad.Name }
    } catch {}
    try {
        $eng = Get-CimInstance -Namespace root/cimv2 -ClassName Win32_PerfFormattedData_GPUEngine_GPUEngine -ErrorAction Stop |
            Where-Object { $_.UtilizationPercentage -ne $null }
        if ($eng) {
            $vals = @($eng | ForEach-Object { [double]$_.UtilizationPercentage })
            if ($vals.Count) { $gpu.usage = [math]::Round(($vals | Measure-Object -Maximum).Maximum, 1) }
        }
    } catch {}
    if ($null -eq $gpu.usage) {
        try {
            $nv = Get-CimInstance -Namespace root/cimv2 -ClassName Win32_PerfFormattedData_Counters_GPUAdapterEngine -ErrorAction Stop
            if ($nv) {
                $gpu.usage = [math]::Round(([double]($nv | Measure-Object -Property UtilizationPercentage -Maximum).Maximum), 1)
            }
        } catch {}
    }
    return $gpu
}

$cpu = Get-CpuUsage
$ram = Get-RamInfo
$gpu = Get-GpuInfo
$os = Get-CimInstance Win32_OperatingSystem
$uptime = ''
try {
    $boot = $os.LastBootUpTime
    $span = (Get-Date) - $boot
    $uptime = ('{0}j {1}h {2}m' -f $span.Days, $span.Hours, $span.Minutes)
} catch {}

$out = [ordered]@{
    cpu = $cpu
    gpu = $gpu
    ram = $ram
    windows = [ordered]@{
        caption = [string]$os.Caption
        build = [string]$os.BuildNumber
        version = [string]$os.Version
    }
    uptime = $uptime
    timestamp = (Get-Date).ToString('dd/MM/yyyy - HH:mm')
}

Write-Output ($out | ConvertTo-Json -Depth 5 -Compress)
exit 0
