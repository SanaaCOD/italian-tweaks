# Résolution et fréquence maximales (API Windows uniquement). Pas de réglages panneau NVIDIA.
param(
    [string]$LogPath = '',
    [string]$ResultPath = ''
)

$ErrorActionPreference = 'Continue'

function Write-ProfileLog([string]$line) {
    if (-not $LogPath) { return }
    try {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch {}
}

function Ensure-NvDispEnumType {
    if ('NvDispEnum' -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class NvDispEnum {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
    }
    public const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x1;
    public const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x4;
    [DllImport("user32.dll", CharSet=CharSet.Ansi)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
}
"@ -ErrorAction Stop | Out-Null
}

function Get-PrimaryDisplayDeviceName {
    Ensure-NvDispEnumType
    $dd = New-Object NvDispEnum+DISPLAY_DEVICE
    $dd.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($dd)
    $i = 0
    while ([NvDispEnum]::EnumDisplayDevices($null, [uint32]$i, [ref]$dd, 0)) {
        $flags = $dd.StateFlags
        if (($flags -band [NvDispEnum]::DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) -ne 0) {
            if (($flags -band [NvDispEnum]::DISPLAY_DEVICE_PRIMARY_DEVICE) -ne 0) {
                return $dd.DeviceName
            }
        }
        $i++
        $dd = New-Object NvDispEnum+DISPLAY_DEVICE
        $dd.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($dd)
    }
    return '\\.\DISPLAY1'
}

function Ensure-NvDispModeType {
    if ('NvDispMode' -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class NvDispMode {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public short dmOrientation, dmPaperSize, dmPaperLength, dmPaperWidth;
        public short dmScale, dmCopies, dmDefaultSource, dmPrintQuality;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel;
        public int dmPelsWidth, dmPelsHeight;
        public int dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType;
        public int dmReserved1, dmReserved2;
        public int dmPanningWidth, dmPanningHeight;
    }
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int DM_PELSWIDTH = 0x80000;
    public const int DM_PELSHEIGHT = 0x100000;
    public const int DM_DISPLAYFREQUENCY = 0x400000;
    public const int DM_BITSPERPEL = 0x40000;
    public const int CDS_UPDATEREGISTRY = 0x01;
    public const int CDS_TEST = 0x02;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
    [DllImport("user32.dll", CharSet=CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);
}
"@ -ErrorAction Stop | Out-Null
}

function Get-DisplayModeInfo([string]$deviceName) {
    Ensure-NvDispModeType
    $tryDevices = @()
    if ($deviceName) { $tryDevices += $deviceName }
    $tryDevices += $null

    foreach ($dev in $tryDevices) {
        $current = New-Object NvDispMode+DEVMODE
        $current.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($current)
        if (-not [NvDispMode]::EnumDisplaySettings($dev, [NvDispMode]::ENUM_CURRENT_SETTINGS, [ref]$current)) {
            continue
        }

        $modes = New-Object System.Collections.Generic.List[object]
        $i = 0
        while ($true) {
            $dm = New-Object NvDispMode+DEVMODE
            $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($dm)
            if (-not [NvDispMode]::EnumDisplaySettings($dev, $i, [ref]$dm)) { break }
            if ($dm.dmPelsWidth -gt 0 -and $dm.dmPelsHeight -gt 0 -and $dm.dmDisplayFrequency -gt 0) {
                if ($current.dmBitsPerPel -le 0 -or $dm.dmBitsPerPel -eq $current.dmBitsPerPel) {
                    $modes.Add([PSCustomObject]@{
                        Width = [int]$dm.dmPelsWidth
                        Height = [int]$dm.dmPelsHeight
                        Refresh = [int]$dm.dmDisplayFrequency
                        DevMode = $dm
                    }) | Out-Null
                }
            }
            $i++
        }

        if ($modes.Count -gt 0) {
            $useDev = $dev
            if (-not $useDev) { $useDev = $deviceName }
            return [PSCustomObject]@{
                DeviceName = $useDev
                Current = [PSCustomObject]@{
                    Width = [int]$current.dmPelsWidth
                    Height = [int]$current.dmPelsHeight
                    Refresh = [int]$current.dmDisplayFrequency
                }
                Modes = $modes
                ChangeDisplaySettingsEx = {
                    param($targetDm, $testOnly)
                    $flags = [NvDispMode]::CDS_UPDATEREGISTRY
                    if ($testOnly) { $flags = $flags -bor [NvDispMode]::CDS_TEST }
                    return [NvDispMode]::ChangeDisplaySettingsEx($useDev, [ref]$targetDm, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
                }
            }
        }
    }
    return $null
}

function Apply-MaxResolutionAndRefreshRate {
    $result = @{
        currentResolution = ''
        currentRefresh = ''
        targetResolution = ''
        targetRefresh = ''
        activeResolution = ''
        activeRefresh = ''
        applyResult = 'error'
        verified = $false
        statusText = ''
        displayDetected = ''
    }
    try {
        $device = Get-PrimaryDisplayDeviceName
        $result.displayDetected = $device
        $info = Get-DisplayModeInfo $device
        if (-not $info -or $info.Modes.Count -eq 0) {
            $result.statusText = 'Échec : impossible de lire les modes affichage.'
            return $result
        }

        $cur = $info.Current
        $result.currentResolution = '{0}x{1}' -f $cur.Width, $cur.Height
        $result.currentRefresh = [string]$cur.Refresh

        $best = $info.Modes | Sort-Object { $_.Width * $_.Height }, { $_.Refresh } -Descending | Select-Object -First 1
        $result.targetResolution = '{0}x{1}' -f $best.Width, $best.Height
        $result.targetRefresh = [string]$best.Refresh

        if ($cur.Width -eq $best.Width -and $cur.Height -eq $best.Height -and $cur.Refresh -eq $best.Refresh) {
            $result.activeResolution = $result.targetResolution
            $result.activeRefresh = $result.targetRefresh
            $result.applyResult = 'ok'
            $result.verified = $true
            $result.statusText = 'OK : {0} @ {1} Hz (déjà actif)' -f $result.targetResolution, $result.targetRefresh
            return $result
        }

        $targetDm = $best.DevMode
        $targetDm.dmFields = [NvDispMode]::DM_PELSWIDTH -bor [NvDispMode]::DM_PELSHEIGHT -bor [NvDispMode]::DM_DISPLAYFREQUENCY
        $testCode = & $info.ChangeDisplaySettingsEx $targetDm $true
        if ($testCode -ne 0) {
            $result.statusText = 'Échec : mode affichage refusé par Windows (code ' + $testCode + ').'
            return $result
        }
        $applyCode = & $info.ChangeDisplaySettingsEx $targetDm $false
        if ($applyCode -ne 0) {
            $result.statusText = 'Échec : ChangeDisplaySettingsEx a échoué (code ' + $applyCode + ').'
            return $result
        }

        Start-Sleep -Milliseconds 1000
        $verify = Get-DisplayModeInfo $device
        if (-not $verify) {
            $result.statusText = 'Échec : relecture du mode actif impossible.'
            return $result
        }

        $result.activeResolution = '{0}x{1}' -f $verify.Current.Width, $verify.Current.Height
        $result.activeRefresh = [string]$verify.Current.Refresh

        if ($verify.Current.Width -eq $best.Width -and $verify.Current.Height -eq $best.Height -and $verify.Current.Refresh -eq $best.Refresh) {
            $result.applyResult = 'ok'
            $result.verified = $true
            $result.statusText = 'OK : {0} @ {1} Hz' -f $result.targetResolution, $result.targetRefresh
        } else {
            $result.applyResult = 'error'
            $result.verified = $false
            $result.statusText = 'Échec : actif {0} @ {1} Hz, attendu {2} @ {3} Hz' -f `
                $result.activeResolution, $result.activeRefresh, $result.targetResolution, $result.targetRefresh
        }
    } catch {
        $result.statusText = 'Échec : ' + $_.Exception.Message
    }
    return $result
}

Write-ProfileLog ('DATE=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-ProfileLog 'ACTION=apply_windows_display_profile'

$device = ''
try { $device = Get-PrimaryDisplayDeviceName } catch {}
Write-ProfileLog ('DISPLAY_DETECTED=' + $(if ($device) { $device } else { 'non' }))

$res = Apply-MaxResolutionAndRefreshRate
Write-ProfileLog ('CURRENT_RESOLUTION=' + $res.currentResolution)
Write-ProfileLog ('CURRENT_REFRESH=' + $res.currentRefresh)
Write-ProfileLog ('TARGET_RESOLUTION=' + $res.targetResolution)
Write-ProfileLog ('TARGET_REFRESH=' + $res.targetRefresh)
Write-ProfileLog ('ACTIVE_RESOLUTION=' + $res.activeResolution)
Write-ProfileLog ('ACTIVE_REFRESH=' + $res.activeRefresh)
Write-ProfileLog ('RESOLUTION_APPLY_RESULT=' + $res.applyResult)
Write-ProfileLog ('RESOLUTION_VERIFIED=' + $(if ($res.verified) { 'oui' } else { 'non' }))
Write-ProfileLog ('GLOBAL_RESULT=' + $(if ($res.verified) { 'ok' } else { 'error' }))

$payload = @{
    displayDetected = $device
    resolution = $res
    globalResult = $(if ($res.verified) { 'ok' } else { 'error' })
}

if ($ResultPath) {
    try {
        $dir = Split-Path -Parent $ResultPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        ($payload | ConvertTo-Json -Depth 6 -Compress) | Out-File -LiteralPath $ResultPath -Encoding utf8 -Force
    } catch {}
}

exit 0
