$ErrorActionPreference = 'SilentlyContinue'
$ids = @(
    'USB\VID_054C&PID_0CE6&MI_03\6&2BA514F0&0&0003',
    'HID\VID_054C&PID_0CE6&MI_03\7&519DE54&0&0000',
    'USB\VID_054C&PID_0CE6\5&30741CDD&0&4'
)
foreach ($id in $ids) {
    Write-Output "=== $id ==="
    $rp = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $id
    if (Test-Path -LiteralPath $rp) {
        $lf = (Get-ItemProperty -LiteralPath $rp -Name LowerFilters -ErrorAction SilentlyContinue).LowerFilters
        Write-Output ("LowerFilters: " + ($lf -join ', '))
    } else {
        Write-Output 'path missing'
    }
}
foreach ($kp in @(
    'HKLM:\SYSTEM\CurrentControlSet\Services\HIDUSBF\Parameters',
    'HKLM:\SYSTEM\CurrentControlSet\Control\HIDUSBF',
    'HKLM:\SYSTEM\CurrentControlSet\Services\hidusbf'
)) {
    Write-Output "=== $kp ==="
    if (Test-Path -LiteralPath $kp) {
        Get-ItemProperty -LiteralPath $kp | Format-List *
    } else {
        Write-Output 'missing'
    }
}
Write-Output '=== PnP entities 054C/0CE6 ==='
Get-CimInstance Win32_PnPEntity |
    Where-Object { $_.DeviceID -match 'VID_054C.*PID_0CE6' } |
    Select-Object Name, DeviceID, PNPClass, Service |
    Format-Table -AutoSize

Write-Output '=== hidusbf.sys locations ==='
@(
    "$env:SystemRoot\System32\drivers\hidusbf.sys",
    'C:\Users\Sanaa\.cursor\projects\empty-window\PurpleBoost\Tools\hidusbf\hidusbf\DRIVER\AMD64_AS\hidusbf.sys'
) | ForEach-Object {
    if (Test-Path -LiteralPath $_) {
        $i = Get-Item -LiteralPath $_
        Write-Output ("FOUND " + $i.FullName + " size=" + $i.Length + " modified=" + $i.LastWriteTime)
    } else {
        Write-Output ("MISSING " + $_)
    }
}
