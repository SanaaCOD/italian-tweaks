$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Join-Path $root "NvidiaPerformanceRegScan\NvidiaPerformanceRegScan.csproj"
$outExe = Join-Path $root "NvidiaPerformanceRegScan.exe"

Write-Host "Building NvidiaPerformanceRegScan..."
dotnet publish $proj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $root

if (Test-Path $outExe) {
    Write-Host "OK: $outExe"
    exit 0
}

Write-Host "FAIL: exe not found"
exit 1
