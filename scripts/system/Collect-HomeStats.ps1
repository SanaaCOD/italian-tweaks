#Requires -Version 5.1
# Logique stats Accueil — pourcentages CPU/GPU/RAM
param(
    [string]$AppRoot = '',
    [string]$LogDir = '',
    [string]$OutPath = '',
    [int]$GpuTimeoutSec = 4
)

$ErrorActionPreference = 'SilentlyContinue'

function Clamp-Pct($n) {
    if ($null -eq $n -or [double]::IsNaN([double]$n)) { return $null }
    $v = [double]$n
    if ($v -lt 0) { $v = 0 }
    if ($v -gt 100) { $v = 100 }
    return [math]::Round($v, 1)
}

$result = @{ cpu = $null; gpu = $null; ram = $null; updatedAt = [int][double]::Parse((Get-Date -UFormat %s)) }

try {
    $cpus = @(Get-CimInstance Win32_Processor -ErrorAction Stop | ForEach-Object { [double]$_.LoadPercentage })
    $valid = @($cpus | Where-Object { -not [double]::IsNaN($_) })
    if ($valid.Count -gt 0) {
        $result.cpu = Clamp-Pct(($valid | Measure-Object -Average).Average)
    }
} catch {}

if ($null -eq $result.cpu) {
    try {
        $pt = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -ExpandProperty PercentProcessorTime -First 1
        $result.cpu = Clamp-Pct($pt)
    } catch {}
}

try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
    $total = [double]$os.TotalVisibleMemorySize
    $free = [double]$os.FreePhysicalMemory
    if ($total -gt 0) {
        $result.ram = Clamp-Pct((($total - $free) * 100.0) / $total)
    }
} catch {}

try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $maxGpu = $null
    $engines = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue
    foreach ($e in $engines) {
        if ($sw.Elapsed.TotalSeconds -gt $GpuTimeoutSec) { break }
        $u = [double]$e.UtilizationPercentage
        if (-not [double]::IsNaN($u)) {
            if ($null -eq $maxGpu -or $u -gt $maxGpu) { $maxGpu = $u }
        }
    }
    if ($null -eq $maxGpu) {
        $engines2 = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterEngine -ErrorAction SilentlyContinue
        foreach ($e2 in $engines2) {
            if ($sw.Elapsed.TotalSeconds -gt $GpuTimeoutSec) { break }
            $u2 = [double]$e2.UtilizationPercentage
            if (-not [double]::IsNaN($u2)) {
                if ($null -eq $maxGpu -or $u2 -gt $maxGpu) { $maxGpu = $u2 }
            }
        }
    }
    $result.gpu = Clamp-Pct($maxGpu)
} catch {}

$json = $result | ConvertTo-Json -Compress
if ($OutPath) {
    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($OutPath, $json, [System.Text.UTF8Encoding]::new($false))
}
Write-Output $json
exit 0
