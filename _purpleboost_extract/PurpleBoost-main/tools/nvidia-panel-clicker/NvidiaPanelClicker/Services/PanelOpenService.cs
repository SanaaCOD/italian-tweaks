using System.Diagnostics;
using System.Windows.Automation;
using Microsoft.Win32;
using NvidiaPanelClicker.Models;

namespace NvidiaPanelClicker.Services;

public sealed class PanelOpenService
{
    private static readonly string[] PrimaryWindowTitles =
    {
        "Panneau de configuration NVIDIA",
        "NVIDIA Control Panel"
    };

    private static readonly TimeSpan PerMethodWait = TimeSpan.FromSeconds(8);

    public ClickerResult RunOpenPanel()
    {
        var result = new ClickerResult { Task = "open-panel" };
        FileLogger.Info("OPEN_PANEL start");

        var existing = FindPrimaryPanelWindow();
        if (existing != null)
        {
            FileLogger.Info("méthode testée : fenêtre déjà ouverte");
            FileLogger.Info("chemin lancé : (aucun — réutilisation)");
            FileLogger.Info("fenêtre trouvée : oui");
            FinishOpen(existing, result, "Panneau NVIDIA déjà ouvert", true);
            return result;
        }

        foreach (var method in BuildMethods())
        {
            FileLogger.Info("méthode testée : " + method.Label);
            FileLogger.Info("chemin lancé : " + method.LaunchPath);
            try
            {
                method.Launch();
            }
            catch (Exception ex)
            {
                FileLogger.Warn("lancement échoué : " + ex.Message);
            }

            var win = WaitForPrimaryPanelWindow(PerMethodWait);
            if (win != null)
            {
                FileLogger.Info("fenêtre trouvée : oui");
                FinishOpen(win, result, "Panneau NVIDIA ouvert (" + method.Label + ")", false);
                return result;
            }

            FileLogger.Info("fenêtre trouvée : non");
        }

        FileLogger.Error("OPEN_PANEL error");
        return Error(result, "Panneau NVIDIA : aucune méthode n'a ouvert la fenêtre");
    }

    private static IEnumerable<PanelOpenMethod> BuildMethods()
    {
        var list = new List<PanelOpenMethod>();

        const string pf64 = @"C:\Program Files\NVIDIA Corporation\Control Panel Client\nvcplui.exe";
        const string pf86 = @"C:\Program Files (x86)\NVIDIA Corporation\Control Panel Client\nvcplui.exe";

        if (File.Exists(pf64))
            list.Add(new PanelOpenMethod("Méthode 1 — Program Files", pf64, () => LaunchExecutable(pf64)));
        if (File.Exists(pf86))
            list.Add(new PanelOpenMethod("Méthode 2 — Program Files (x86)", pf86, () => LaunchExecutable(pf86)));

        var regPath = TryRegistryAppPath();
        if (!string.IsNullOrEmpty(regPath) && File.Exists(regPath)
            && !list.Any(m => string.Equals(m.LaunchPath, regPath, StringComparison.OrdinalIgnoreCase)))
        {
            list.Add(new PanelOpenMethod("Méthode 3 — Registre App Paths", regPath, () => LaunchExecutable(regPath)));
        }

        const string shellUri =
            "shell:AppsFolder\\NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel";
        list.Add(new PanelOpenMethod("Méthode 4 — explorer shell AppsFolder", shellUri, LaunchExplorerShell));

        list.Add(new PanelOpenMethod("Méthode 5 — PATH nvcplui.exe", "nvcplui.exe", LaunchPathFallback));

        return list;
    }

    private static void LaunchExecutable(string fullPath)
    {
        var workDir = Path.GetDirectoryName(fullPath) ?? "";
        Process.Start(new ProcessStartInfo
        {
            FileName = fullPath,
            WorkingDirectory = workDir,
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Normal
        });
    }

    private static void LaunchExplorerShell()
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments =
                "shell:AppsFolder\\NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj!NVIDIACorp.NVIDIAControlPanel",
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Normal
        });
    }

    private static void LaunchPathFallback()
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = "nvcplui.exe",
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Normal
        });
    }

    private static string? TryRegistryAppPath()
    {
        const string subKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\nvcplui.exe";
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(subKey);
            var value = key?.GetValue(null) as string;
            if (string.IsNullOrWhiteSpace(value)) return null;
            return value.Trim().Trim('"');
        }
        catch
        {
            return null;
        }
    }

    private static AutomationElement? WaitForPrimaryPanelWindow(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            var win = FindPrimaryPanelWindow();
            if (win != null) return win;
            Thread.Sleep(350);
        }
        return null;
    }

    private static AutomationElement? FindPrimaryPanelWindow()
    {
        var win = PanelLauncher.FindPanelWindow();
        if (win == null) return null;
        try
        {
            var name = win.Current.Name ?? "";
            if (PrimaryWindowTitles.Any(t => name.Contains(t, StringComparison.OrdinalIgnoreCase)))
                return win;
        }
        catch { }
        return win;
    }

    private static void FinishOpen(AutomationElement window, ClickerResult result, string message, bool verified)
    {
        PanelLauncher.FocusAndMaximize(window);
        Thread.Sleep(1500);
        FileLogger.Info("OPEN_PANEL success");
        Sent(result, message, verified);
    }

    private static ClickerResult Sent(ClickerResult r, string message, bool verified)
    {
        r.Success = true;
        r.UiStatus = verified ? "panel_verified" : "panel_action_sent";
        r.Verified = verified;
        r.Message = message;
        return r;
    }

    private static ClickerResult Error(ClickerResult r, string message)
    {
        r.Success = false;
        r.UiStatus = "error";
        r.Verified = false;
        r.Message = message;
        FileLogger.Error(message);
        return r;
    }

    private sealed class PanelOpenMethod
    {
        public PanelOpenMethod(string label, string launchPath, Action launch)
        {
            Label = label;
            LaunchPath = launchPath;
            Launch = launch;
        }

        public string Label { get; }
        public string LaunchPath { get; }
        public Action Launch { get; }
    }
}
