$ErrorActionPreference = 'SilentlyContinue'
$paths = @(
    'HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_054C&PID_0CE6&MI_03\6&2BA514F0&0&0003',
    'HKLM:\SYSTEM\CurrentControlSet\Enum\HID\VID_054C&PID_0CE6&MI_03\7&519DE54&0&0000',
    'HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_054C&PID_0CE6\5&30741CDD&0&4'
)
foreach ($p in $paths) {
    Write-Output "=== $p ==="
    if (-not (Test-Path -LiteralPath $p)) { Write-Output 'missing'; continue }
    Get-ItemProperty -LiteralPath $p | Format-List *
    Get-ChildItem -LiteralPath $p | ForEach-Object { Write-Output ('  subkey: ' + $_.PSChildName) }
}

Write-Output '=== Control\HIDUSBF full ==='
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF') {
    cmd /c 'reg query HKLM\SYSTEM\CurrentControlSet\Control\HIDUSBF /s'
}
