$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Join-Path $root "NvidiaAutomationV2\NvidiaAutomationV2.csproj"
$outDir = Join-Path $root "NvidiaAutomationV2.exe"

Write-Host "Building NvidiaAutomationV2..."
dotnet publish $proj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $root

if (Test-Path (Join-Path $root "NvidiaAutomationV2.exe")) {
    Write-Host "OK: $outDir"
    exit 0
}

Write-Host "FAIL: exe not found"
exit 1
