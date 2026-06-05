$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Join-Path $root "NvidiaPanelClicker\NvidiaPanelClicker.csproj"
$outExe = Join-Path $root "NvidiaPanelClicker.exe"

Write-Host "Building NvidiaPanelClicker..."
dotnet publish $proj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $root

if (Test-Path $outExe) {
    Write-Host "OK: $outExe"
    exit 0
}

Write-Host "FAIL: exe not found"
exit 1
