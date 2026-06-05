# Convertit le PNG logo existant en icon.ico (aucun dessin — format uniquement).
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$pngPath = Join-Path $root "assets\images\unreal-logo.png"
$icoPath = Join-Path $root "assets\images\icon.ico"
$icoLauncher = Join-Path (Split-Path $PSScriptRoot -Parent) "Assets\unreal.ico"

if (-not (Test-Path -LiteralPath $pngPath)) {
    Write-Error "Logo introuvable : $pngPath"
}

$src = [System.Drawing.Image]::FromFile($pngPath)
try {
    $size = 256
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $fs = [System.IO.File]::Create($icoPath)
    $icon.Save($fs)
    $fs.Close()
    $icon.Dispose()
    $bmp.Dispose()
}
finally {
    $src.Dispose()
}

New-Item -ItemType Directory -Force -Path (Split-Path $icoLauncher -Parent) | Out-Null
Copy-Item -LiteralPath $icoPath -Destination $icoLauncher -Force

Write-Host "OK icon.ico : $icoPath"
