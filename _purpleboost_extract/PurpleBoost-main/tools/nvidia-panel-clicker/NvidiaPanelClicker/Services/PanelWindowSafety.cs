using System.Diagnostics;
using System.Windows.Automation;

namespace NvidiaPanelClicker.Services;

/// <summary>
/// Ensures NVIDIA panel automation never targets Unreal HTA, mshta, or other app windows.
/// </summary>
internal static class PanelWindowSafety
{
    private static readonly string[] ExcludedProcessNames =
    {
        "mshta",
        "iexplore",
        "powershell",
        "pwsh",
        "cmd",
        "wscript",
        "cscript"
    };

    private static readonly string[] ExcludedTitleFragments =
    {
        "unreal",
        "unreal gaming optimizer",
        "purpleboost",
        "mshta",
        "gaming optimizer"
    };

    private static readonly string[] PanelAutomationTitleFragments =
    {
        "Panneau de configuration NVIDIA",
        "NVIDIA Control Panel",
        "NVIDIA Settings",
        "Centre de configuration NVIDIA"
    };

    private static readonly string[] PanelCloseTitleFragments =
    {
        "Panneau de configuration NVIDIA",
        "NVIDIA Control Panel"
    };

    public static bool IsExcludedProcessName(string? processName)
    {
        if (string.IsNullOrWhiteSpace(processName)) return true;
        return ExcludedProcessNames.Any(p =>
            processName.Equals(p, StringComparison.OrdinalIgnoreCase) ||
            processName.StartsWith(p, StringComparison.OrdinalIgnoreCase));
    }

    public static bool IsExcludedWindowTitle(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return true;
        return ExcludedTitleFragments.Any(f =>
            title.Contains(f, StringComparison.OrdinalIgnoreCase));
    }

    public static bool MatchesNvidiaPanelTitle(string? title, bool forCloseOnly)
    {
        if (string.IsNullOrWhiteSpace(title)) return false;
        if (IsExcludedWindowTitle(title)) return false;
        var allowed = forCloseOnly ? PanelCloseTitleFragments : PanelAutomationTitleFragments;
        return allowed.Any(t => title.Contains(t, StringComparison.OrdinalIgnoreCase));
    }

    public static bool TryGetProcessName(IntPtr hwnd, out string processName)
    {
        processName = "";
        if (hwnd == IntPtr.Zero || !Win32Helper.IsWindow(hwnd)) return false;
        try
        {
            Win32Helper.GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == 0) return false;
            using var proc = Process.GetProcessById((int)pid);
            processName = proc.ProcessName ?? "";
            return !string.IsNullOrEmpty(processName);
        }
        catch
        {
            return false;
        }
    }

    public static bool IsSafeNvidiaPanelWindow(AutomationElement? window, bool forCloseOnly)
    {
        if (window == null) return false;
        try
        {
            var title = window.Current.Name ?? "";
            if (!MatchesNvidiaPanelTitle(title, forCloseOnly)) return false;

            var hwnd = new IntPtr(window.Current.NativeWindowHandle);
            if (hwnd == IntPtr.Zero) return false;
            if (!TryGetProcessName(hwnd, out var procName)) return false;
            if (IsExcludedProcessName(procName)) return false;

            if (forCloseOnly)
                return procName.Equals("nvcplui", StringComparison.OrdinalIgnoreCase);

            return procName.Equals("nvcplui", StringComparison.OrdinalIgnoreCase) ||
                   procName.Equals("NVDisplay.Container", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }
}
