using System.Runtime.InteropServices;
using UnrealNvidiaDisplayHelper.Models;

namespace UnrealNvidiaDisplayHelper.Services;

public sealed class DisplayModeService
{
    private const int EnumCurrentSettings = -1;
    private const int DmPelsWidth = 0x80000;
    private const int DmPelsHeight = 0x100000;
    private const int DmDisplayFrequency = 0x400000;
    private const int DmBitsPerPel = 0x40000;
    private const int CdsTest = 0x02;
    private const int CdsUpdateregistry = 0x01;
    private const int DispChangeSuccessful = 0;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DisplayDevice
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DevMode
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public short dmOrientation;
        public short dmPaperSize;
        public short dmPaperLength;
        public short dmPaperWidth;
        public short dmScale;
        public short dmCopies;
        public short dmDefaultSource;
        public short dmPrintQuality;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    private static extern bool EnumDisplayDevices(string? lpDevice, uint iDevNum, ref DisplayDevice lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    private static extern bool EnumDisplaySettings(string? deviceName, int modeNum, ref DevMode devMode);

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    private static extern int ChangeDisplaySettingsEx(string? lpszDeviceName, ref DevMode lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);

    private const int DisplayDeviceAttachedToDesktop = 0x1;
    private const int DisplayDevicePrimaryDevice = 0x4;

    public string PrimaryDeviceName { get; private set; } = @"\\.\DISPLAY1";

    public bool FindPrimaryDisplay()
    {
        var dd = new DisplayDevice { cb = Marshal.SizeOf<DisplayDevice>() };
        for (uint i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++)
        {
            if ((dd.StateFlags & DisplayDeviceAttachedToDesktop) != 0 &&
                (dd.StateFlags & DisplayDevicePrimaryDevice) != 0)
            {
                PrimaryDeviceName = dd.DeviceName;
                FileLogger.Info("Écran principal : " + PrimaryDeviceName + " (" + dd.DeviceString + ")");
                return true;
            }
            dd = new DisplayDevice { cb = Marshal.SizeOf<DisplayDevice>() };
        }
        PrimaryDeviceName = @"\\.\DISPLAY1";
        FileLogger.Warn("Écran principal non trouvé, repli sur " + PrimaryDeviceName);
        return true;
    }

    private sealed class ModeCandidate
    {
        public int Width { get; init; }
        public int Height { get; init; }
        public int Refresh { get; init; }
        public int BitsPerPel { get; init; }
        public DevMode DevMode { get; init; }
        public long Pixels => (long)Width * Height;
    }

    private (ModeCandidate? Best, int ModeCount) FindBestMode()
    {
        var current = ReadCurrentMode();
        if (current == null) return (null, 0);

        var modes = new List<ModeCandidate>();
        for (var i = 0; ; i++)
        {
            var dm = new DevMode { dmSize = (short)Marshal.SizeOf<DevMode>() };
            if (!EnumDisplaySettings(PrimaryDeviceName, i, ref dm)) break;
            if (dm.dmPelsWidth <= 0 || dm.dmPelsHeight <= 0 || dm.dmDisplayFrequency <= 0) continue;
            if (current.BitsPerPel > 0 && dm.dmBitsPerPel != current.BitsPerPel) continue;
            modes.Add(new ModeCandidate
            {
                Width = dm.dmPelsWidth,
                Height = dm.dmPelsHeight,
                Refresh = dm.dmDisplayFrequency,
                BitsPerPel = dm.dmBitsPerPel,
                DevMode = dm
            });
        }

        if (modes.Count == 0) return (null, 0);

        FileLogger.Info("Available display modes found: " + modes.Count);

        var best = modes
            .OrderByDescending(m => m.Pixels)
            .ThenByDescending(m => m.Refresh)
            .First();

        FileLogger.Info($"Selected max resolution: {best.Width}x{best.Height}");
        FileLogger.Info($"Selected max refresh rate: {best.Refresh} Hz");
        return (best, modes.Count);
    }

    private ModeCandidate? ReadCurrentMode()
    {
        var dm = new DevMode { dmSize = (short)Marshal.SizeOf<DevMode>() };
        if (!EnumDisplaySettings(PrimaryDeviceName, EnumCurrentSettings, ref dm))
        {
            if (!EnumDisplaySettings(null, EnumCurrentSettings, ref dm))
                return null;
        }
        return new ModeCandidate
        {
            Width = dm.dmPelsWidth,
            Height = dm.dmPelsHeight,
            Refresh = dm.dmDisplayFrequency,
            BitsPerPel = dm.dmBitsPerPel,
            DevMode = dm
        };
    }

    private (bool Applied, bool Verified, string Resolution, string RefreshRate, string? Error) ApplyMode(ModeCandidate target, bool dryRun)
    {
        var targetDm = target.DevMode;
        targetDm.dmFields = DmPelsWidth | DmPelsHeight | DmDisplayFrequency;
        if (target.BitsPerPel > 0)
            targetDm.dmFields |= DmBitsPerPel;

        var current = ReadCurrentMode();
        if (current != null &&
            current.Width == target.Width &&
            current.Height == target.Height &&
            current.Refresh == target.Refresh)
        {
            return (true, true, $"{target.Width}x{target.Height}", $"{target.Refresh}Hz", null);
        }

        if (dryRun)
        {
            var testCode = ChangeDisplaySettingsEx(PrimaryDeviceName, ref targetDm, IntPtr.Zero, CdsTest, IntPtr.Zero);
            if (testCode != DispChangeSuccessful)
                return (false, false, "", "", $"Mode refusé par Windows (code {testCode})");
            return (false, false, $"{target.Width}x{target.Height}", $"{target.Refresh}Hz", "dry-run");
        }

        var applyCode = ChangeDisplaySettingsEx(PrimaryDeviceName, ref targetDm, IntPtr.Zero, CdsUpdateregistry, IntPtr.Zero);
        if (applyCode != DispChangeSuccessful)
            return (false, false, "", "", $"ChangeDisplaySettingsEx échec (code {applyCode})");

        Thread.Sleep(1000);
        var after = ReadCurrentMode();
        if (after == null)
            return (true, false, $"{target.Width}x{target.Height}", $"{target.Refresh}Hz", "Relecture impossible");

        var resOk = after.Width == target.Width && after.Height == target.Height;
        var hzOk = after.Refresh == target.Refresh;
        FileLogger.Info("Resolution applied: " + (resOk ? "OK" : "Failed"));
        FileLogger.Info("Refresh rate applied: " + (hzOk ? "OK" : "Failed"));
        FileLogger.Info($"Current mode after apply: {after.Width}x{after.Height} @ {after.Refresh} Hz");

        var verified = resOk && hzOk;
        return (true, verified,
            $"{after.Width}x{after.Height}",
            $"{after.Refresh}Hz",
            verified ? null : $"Actif {after.Width}x{after.Height} @ {after.Refresh}Hz, attendu {target.Width}x{target.Height} @ {target.Refresh}Hz");
    }

    public void FillDisplayModeStatus(HelperResult result, bool apply, bool dryRun)
    {
        if (!FindPrimaryDisplay())
        {
            result.Messages.Add("Aucun écran principal Windows détecté");
            return;
        }

        var (best, modeCount) = FindBestMode();
        if (best == null)
        {
            result.Messages.Add("Impossible d'énumérer les modes d'affichage");
            return;
        }

        result.Messages.Add("Available display modes found: " + modeCount);
        result.Messages.Add($"Selected max resolution: {best.Width}x{best.Height}");
        result.Messages.Add($"Selected max refresh rate: {best.Refresh} Hz");

        if (!apply)
        {
            var cur = ReadCurrentMode();
            if (cur != null)
            {
                result.DisplayMode.Applied = false;
                result.DisplayMode.Verified = true;
                result.DisplayMode.Resolution = $"{cur.Width}x{cur.Height}";
                result.DisplayMode.RefreshRate = $"{cur.Refresh}Hz";
            }
            return;
        }

        var (applied, verified, res, hz, err) = ApplyMode(best, dryRun);
        result.DisplayMode.Applied = applied;
        result.DisplayMode.Verified = verified;
        result.DisplayMode.Resolution = res;
        result.DisplayMode.RefreshRate = hz;
        if (!string.IsNullOrEmpty(err) && err != "dry-run")
            result.Messages.Add(err);
    }
}
