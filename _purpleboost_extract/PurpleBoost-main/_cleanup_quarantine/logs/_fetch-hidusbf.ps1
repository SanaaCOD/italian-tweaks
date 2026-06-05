$ErrorActionPreference = 'Stop'
$zip = 'C:\Users\Sanaa\.cursor\projects\empty-window\PurpleBoost\logs\_hidusbf.zip'
$dest = 'C:\Users\Sanaa\.cursor\projects\empty-window\PurpleBoost\logs\_hidusbf_extract'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/LordOfMice/hidusbf/master/hidusbf.zip' -OutFile $zip
if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
Get-ChildItem -Recurse $dest | Where-Object { -not $_.PSIsContainer } | Select-Object -ExpandProperty FullName
