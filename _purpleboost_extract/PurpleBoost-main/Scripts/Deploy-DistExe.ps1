# Publie le lanceur et remplace dist\Unreal Gaming Optimizer.exe (pc-tune-launch-v4).
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$staging = Join-Path $ProjectRoot "dist-staging"
$distDir = Join-Path $ProjectRoot "dist"
$dest = Join-Path $distDir "Unreal Gaming Optimizer.exe"
$csproj = Join-Path $ProjectRoot "UnrealLauncher\UnrealLauncher.csproj"

function Stop-OwnUnrealProcesses {
    Get-CimInstance Win32_Process -Filter "Name='mshta.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'Unreal\.hta' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-Process -Name "Unreal Gaming Optimizer" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

function Test-BuildTag {
    param([string]$Path, [string]$Tag)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($Path))
    return $text.Contains($Tag)
}

Write-Host "[Deploy] Arret processus PurpleBoost / Unreal..."
Stop-OwnUnrealProcesses

if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

Write-Host "[Deploy] dotnet publish -> dist-staging"
dotnet publish $csproj -c Release -r win-x64 `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    --self-contained true `
    -o $staging
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$built = Join-Path $staging "Unreal Gaming Optimizer.exe"
if (-not (Test-Path -LiteralPath $built)) {
    Write-Error "EXE introuvable apres publish: $built"
}

if (-not (Test-BuildTag $built "pc-tune-launch-v4")) {
    Write-Warning "Tag pc-tune-launch-v4 absent du binaire staging."
}
if (Test-BuildTag $built "Une instance de Unreal Gaming Optimizer") {
    Write-Error "Le binaire staging contient encore l'ancien message single-instance."
}

$retries = 8
$deployed = $false
for ($i = 0; $i -lt $retries; $i++) {
    try {
        if (Test-Path -LiteralPath $dest) {
            Remove-Item -LiteralPath $dest -Force
        }
        Copy-Item -LiteralPath $built -Destination $dest -Force
        $deployed = $true
        break
    }
    catch {
        Write-Host "[Deploy] Fichier verrouille (tentative $($i + 1)/$retries). Fermez Unreal Gaming Optimizer..."
        Stop-OwnUnrealProcesses
        Start-Sleep -Seconds 2
    }
}

if (-not $deployed) {
    $fallback = "$dest.new"
    Copy-Item -LiteralPath $built -Destination $fallback -Force
    Write-Host ""
    Write-Host "IMPOSSIBLE d'ecraser (processus actif) :" -ForegroundColor Yellow
    Write-Host "  $dest"
    Write-Host "Nouvelle build ecrite :" -ForegroundColor Yellow
    Write-Host "  $fallback"
    Write-Host ""
    Write-Host "Fermez l'application Unreal, puis relancez: build-exe.bat"
    exit 2
}

if (Test-BuildTag $dest "Une instance de Unreal Gaming Optimizer") {
    Write-Error "dist\EXE contient encore l'ancien popup - deploiement invalide."
}

Write-Host "[Deploy] OK -> $dest"
exit 0
