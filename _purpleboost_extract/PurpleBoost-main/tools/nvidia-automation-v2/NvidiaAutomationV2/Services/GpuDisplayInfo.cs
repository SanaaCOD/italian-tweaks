using System.Management;
using System.Runtime.InteropServices;

namespace NvidiaAutomationV2.Services;

internal static class GpuDisplayInfo
{
    private const int DisplayDeviceAttachedToDesktop = 0x1;
    private const int DisplayDevicePrimaryDevice = 0x4;

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

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    private static extern bool EnumDisplayDevices(string? lpDevice, uint iDevNum, ref DisplayDevice lpDisplayDevice, uint dwFlags);

    public static string GetPrimaryGpuName()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name FROM Win32_VideoController WHERE Name LIKE '%NVIDIA%'");
            foreach (var obj in searcher.Get())
            {
                var name = obj["Name"]?.ToString();
                if (!string.IsNullOrWhiteSpace(name))
                    return name.Trim();
            }
        }
        catch (Exception ex)
        {
            FileLogger.Warn("GPU WMI read failed: " + ex.Message);
        }
        return "unknown";
    }

    public static (string DeviceName, string DeviceString) GetPrimaryDisplay()
    {
        var dd = new DisplayDevice { cb = Marshal.SizeOf<DisplayDevice>() };
        for (uint i = 0; EnumDisplayDevices(null, i, ref dd, 0); i++)
        {
            if ((dd.StateFlags & DisplayDeviceAttachedToDesktop) != 0 &&
                (dd.StateFlags & DisplayDevicePrimaryDevice) != 0)
                return (dd.DeviceName, dd.DeviceString);
            dd = new DisplayDevice { cb = Marshal.SizeOf<DisplayDevice>() };
        }
        return (@"\\.\DISPLAY1", "primary-fallback");
    }
}
