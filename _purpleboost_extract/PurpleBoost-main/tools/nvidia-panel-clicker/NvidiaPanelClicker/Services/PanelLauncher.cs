using System.Diagnostics;
using System.Windows.Automation;

namespace NvidiaPanelClicker.Services;

internal sealed class PanelLauncher
{
    private static readonly string[] WindowTitles =
    {
        "Panneau de configuration NVIDIA",
        "NVIDIA Control Panel",
        "NVIDIA Settings",
        "Centre de configuration NVIDIA"
    };

    public string? LaunchedExePath { get; private set; }

    public bool TryLaunchResolved()
    {
        var locator = new NvcpluiLocator();
        if (!locator.TryResolve(out var fullPath) || string.IsNullOrEmpty(fullPath))
            return false;

        try
        {
            var workDir = Path.GetDirectoryName(fullPath) ?? "";
            var psi = new ProcessStartInfo
            {
                FileName = fullPath,
                WorkingDirectory = workDir,
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Normal
            };
            Process.Start(psi);
            LaunchedExePath = fullPath;
            FileLogger.Info("Lancement panneau NVIDIA : " + fullPath);
            FileLogger.Info("WorkingDirectory : " + workDir);
            return true;
        }
        catch (Exception ex)
        {
            FileLogger.Error("Lancement panneau NVIDIA échoué : " + ex.Message);
            return false;
        }
    }

    public bool TryLaunchProgramFilesOnly() => TryLaunchResolved();

    public bool TryLaunch()
    {
        if (TryLaunchProgramFilesOnly()) return true;

        try
        {
            var psi = new ProcessStartInfo("nvcplui.exe")
            {
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Normal
            };
            Process.Start(psi);
            LaunchedExePath = "nvcplui.exe (PATH)";
            FileLogger.Info("LAUNCH nvcplui via PATH");
            return true;
        }
        catch (Exception ex)
        {
            FileLogger.Error("LAUNCH PATH fail: " + ex.Message);
            return false;
        }
    }

    public AutomationElement? WaitForPanelWindow(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            var win = FindPanelWindow();
            if (win != null) return win;
            Thread.Sleep(350);
        }
        return null;
    }

    public static AutomationElement? FindPanelWindow() => FindPanelWindow(forCloseOnly: false);

    /// <summary>Strict finder for end-of-flow close — NVIDIA Control Panel titles and nvcplui.exe only.</summary>
    public static AutomationElement? FindPanelWindowForClose() => FindPanelWindow(forCloseOnly: true);

    private static AutomationElement? FindPanelWindow(bool forCloseOnly)
    {
        var procNames = forCloseOnly
            ? new[] { "nvcplui" }
            : new[] { "nvcplui", "NVDisplay.Container" };

        foreach (var procName in procNames)
        {
            foreach (var proc in Process.GetProcessesByName(procName))
            {
                try
                {
                    if (proc.MainWindowHandle == IntPtr.Zero) continue;
                    var el = AutomationElement.FromHandle(proc.MainWindowHandle);
                    if (PanelWindowSafety.IsSafeNvidiaPanelWindow(el, forCloseOnly))
                        return el;
                }
                catch { }
                finally { proc.Dispose(); }
            }
        }

        foreach (AutomationElement w in AutomationElement.RootElement.FindAll(TreeScope.Children, System.Windows.Automation.Condition.TrueCondition))
        {
            try
            {
                var name = w.Current.Name ?? "";
                if (!PanelWindowSafety.MatchesNvidiaPanelTitle(name, forCloseOnly)) continue;
                if (!PanelWindowSafety.IsSafeNvidiaPanelWindow(w, forCloseOnly)) continue;
                return w;
            }
            catch { }
        }

        return null;
    }

    public static void FocusAndMaximize(AutomationElement window)
    {
        try
        {
            var hwnd = new IntPtr(window.Current.NativeWindowHandle);
            if (hwnd == IntPtr.Zero) return;
            Win32Helper.ShowWindow(hwnd, Win32Helper.SwRestore);
            Thread.Sleep(150);
            Win32Helper.ShowWindow(hwnd, Win32Helper.SwMaximize);
            Thread.Sleep(200);
            Win32Helper.SetForegroundWindow(hwnd);
            if (Win32Helper.GetWindowRect(hwnd, out var r))
            {
                FileLogger.Info("WINDOW rect=" + r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top));
            }
        }
        catch (Exception ex)
        {
            FileLogger.Warn("WINDOW focus/maximize: " + ex.Message);
        }
    }
}
