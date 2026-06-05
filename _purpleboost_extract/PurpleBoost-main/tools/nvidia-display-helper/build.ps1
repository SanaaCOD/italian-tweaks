# Publie UnrealNvidiaDisplayHelper.exe (self-contained win-x64) vers tools/nvidia-display-helper/
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$proj = Join-Path $root 'UnrealNvidiaDisplayHelper\UnrealNvidiaDisplayHelper.csproj'
$outDir = Join-Path $root 'UnrealNvidiaDisplayHelper.exe'
$publishDir = Join-Path $root '_publish'

Write-Host "Publication..." -ForegroundColor Cyan
dotnet publish $proj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $publishDir

$exe = Join-Path $publishDir 'UnrealNvidiaDisplayHelper.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "Exe introuvable apres publish" }

Copy-Item -LiteralPath $exe -Destination $outDir -Force
Write-Host "OK -> $outDir" -ForegroundColor Green
