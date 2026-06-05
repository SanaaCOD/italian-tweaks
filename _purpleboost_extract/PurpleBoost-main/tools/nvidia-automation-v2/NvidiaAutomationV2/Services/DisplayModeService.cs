using System.Runtime.InteropServices;
using NvidiaAutomationV2.Models;

namespace NvidiaAutomationV2.Services;

/// <summary>
/// Résolution / fréquence max via EnumDisplaySettings + ChangeDisplaySettingsEx (logique alignée sur UnrealNvidiaDisplayHelper).
/// </summary>
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
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DevMode
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public short dmOrientation, dmPaperSize, dmPaperLength, dmPaperWidth, dmScale, dmCopies, dmDefaultSource, dmPrintQuality;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
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

    private List<ModeCandidate>? _modesCache;

    public bool FindPrimaryDisplay()
    {
        var dd = new DisplayDevice { cb = Marshal.SizeOf<DisplayDevice>() };
        for (uint i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++)
        {
            if ((dd.StateFlags & DisplayDeviceAttachedToDesktop) != 0 &&
                (dd.StateFlags & DisplayDevicePrimaryDevice) != 0)
            {
                PrimaryDeviceName = dd.DeviceName;
                FileLogger.Info("Primary display: " + PrimaryDeviceName);
                return true;
            }
            dd = new DisplayDevice { cb = Marshal.SizeOf<DisplayDevice>() };
        }
        PrimaryDeviceName = @"\\.\DISPLAY1";
        return true;
    }

    public StepResult ApplyMaxResolution()
    {
        if (!PrepareModes(out var modes, out var current))
            return StepResult.Fail("Résolution maximale non appliquée");

        var maxPixels = modes.Max(m => m.Pixels);
        var maxRes = modes
            .Where(m => m.Pixels == maxPixels)
            .OrderBy(m => m.Refresh)
            .First();
        FileLogger.Info($"Selected max resolution: {maxRes.Width}x{maxRes.Height}");

        var target = CloneMode(maxRes);
        if (!ApplyMode(target, out var resOk, out var hzOk, out var after))
        {
            FileLogger.Info("Resolution applied: Failed");
            return StepResult.Fail($"{maxRes.Width}x{maxRes.Height} (non appliquée)");
        }

        var resVerified = after.Width == maxRes.Width && after.Height == maxRes.Height;
        FileLogger.Info("Resolution applied: " + (resVerified ? "OK" : "Failed"));
        FileLogger.Info($"Current mode after apply: {after.Width}x{after.Height} @ {after.Refresh} Hz");

        if (!resVerified)
            return StepResult.Fail($"{after.Width}x{after.Height} (résolution non vérifiée)");

        return StepResult.Ok($"{maxRes.Width}x{maxRes.Height}", true);
    }

    public StepResult ApplyMaxRefreshRate()
    {
        if (!PrepareModes(out var modes, out _))
            return StepResult.Fail("Fréquence maximale non appliquée");

        var maxRes = modes.OrderByDescending(m => m.Pixels).First();
        var bestAtRes = modes
            .Where(m => m.Width == maxRes.Width && m.Height == maxRes.Height)
            .OrderByDescending(m => m.Refresh)
            .First();

        FileLogger.Info($"Selected max refresh rate: {bestAtRes.Refresh} Hz");

        var target = CloneMode(bestAtRes);
        if (!ApplyMode(target, out _, out _, out var after))
        {
            FileLogger.Info("Refresh rate applied: Failed");
            return StepResult.Fail($"{bestAtRes.Refresh}Hz (non appliquée)");
        }

        var hzVerified = after.Refresh == bestAtRes.Refresh;
        var resOk = after.Width == bestAtRes.Width && after.Height == bestAtRes.Height;
        FileLogger.Info("Refresh rate applied: " + (hzVerified && resOk ? "OK" : "Failed"));
        FileLogger.Info($"Current mode after apply: {after.Width}x{after.Height} @ {after.Refresh} Hz");

        if (!hzVerified || !resOk)
            return StepResult.Fail($"{after.Refresh}Hz (non vérifiée, actif {after.Width}x{after.Height}@{after.Refresh}Hz)");

        return StepResult.Ok($"{bestAtRes.Refresh}Hz", true);
    }

    public (StepResult Resolution, StepResult RefreshRate) ApplyMaxResolutionAndRefreshRate()
    {
        var res = ApplyMaxResolution();
        var hz = ApplyMaxRefreshRate();
        return (res, hz);
    }

    private bool PrepareModes(out List<ModeCandidate> modes, out ModeCandidate? current)
    {
        modes = new List<ModeCandidate>();
        current = null;
        if (!FindPrimaryDisplay()) return false;

        current = ReadCurrentMode();
        if (current == null) return false;

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

        FileLogger.Info("Available display modes found: " + modes.Count);
        _modesCache = modes;
        return modes.Count > 0;
    }

    private bool ApplyMode(ModeCandidate target, out bool resOk, out bool hzOk, out ModeCandidate after)
    {
        resOk = false;
        hzOk = false;
        after = new ModeCandidate();

        var dm = target.DevMode;
        dm.dmFields = DmPelsWidth | DmPelsHeight | DmDisplayFrequency;
        if (target.BitsPerPel > 0) dm.dmFields |= DmBitsPerPel;
        var testRc = ChangeDisplaySettingsEx(PrimaryDeviceName, ref dm, IntPtr.Zero, CdsTest, IntPtr.Zero);
        if (testRc != DispChangeSuccessful)
        {
            FileLogger.Warn("ChangeDisplaySettingsEx test rc=" + testRc);
            return false;
        }

        var rc = ChangeDisplaySettingsEx(PrimaryDeviceName, ref dm, IntPtr.Zero, CdsUpdateregistry, IntPtr.Zero);
        if (rc != DispChangeSuccessful)
        {
            FileLogger.Warn("ChangeDisplaySettingsEx apply rc=" + rc);
            return false;
        }

        Thread.Sleep(1000);
        var cur = ReadCurrentMode();
        if (cur == null) return false;
        after = cur;
        resOk = cur.Width == target.Width && cur.Height == target.Height;
        hzOk = cur.Refresh == target.Refresh;
        return true;
    }

    private static ModeCandidate CloneMode(ModeCandidate m) =>
        new()
        {
            Width = m.Width,
            Height = m.Height,
            Refresh = m.Refresh,
            BitsPerPel = m.BitsPerPel,
            DevMode = m.DevMode
        };

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

    private sealed class ModeCandidate
    {
        public int Width { get; init; }
        public int Height { get; init; }
        public int Refresh { get; init; }
        public int BitsPerPel { get; init; }
        public DevMode DevMode { get; init; }
        public long Pixels => (long)Width * Height;
    }
}
