using System.Diagnostics;
using System.Windows.Automation;
using NvidiaPanelClicker.Models;

namespace NvidiaPanelClicker.Services;

public sealed class PanelCloseService
{
    public ClickerResult CloseNvidiaControlPanelAtEnd()
    {
        var result = new ClickerResult
        {
            Task = "close-panel",
            Children = new Dictionary<string, string>()
        };
        FileLogger.Info("Fermeture panneau NVIDIA demandée");
        FileLogger.Info("Unreal laissé ouvert");

        var window = PanelLauncher.FindPanelWindowForClose();
        if (window == null)
        {
            result.Children!["nvcpluiKilled"] = "non";
            FileLogger.Info("nvcplui.exe fermé non");
            FileLogger.Info("Panneau NVIDIA fermé : oui (déjà absent)");
            return Sent(result, "Panneau NVIDIA déjà fermé", true);
        }

        var closed = TryCloseWindowGracefully(window);
        var nvcpluiKilled = false;
        if (!closed)
        {
            nvcpluiKilled = TryKillNvcpluiOnly();
            closed = nvcpluiKilled;
        }

        result.Children!["nvcpluiKilled"] = nvcpluiKilled ? "oui" : "non";
        FileLogger.Info("nvcplui.exe fermé " + (nvcpluiKilled ? "oui" : "non"));

        if (closed)
        {
            FileLogger.Info("Panneau NVIDIA fermé : oui");
            return Sent(result, "Panneau NVIDIA fermé", true);
        }

        FileLogger.Info("Panneau NVIDIA fermé : non");
        return Error(result, "Impossible de fermer le panneau NVIDIA");
    }

    private static bool TryCloseWindowGracefully(AutomationElement window)
    {
        if (!PanelWindowSafety.IsSafeNvidiaPanelWindow(window, forCloseOnly: true))
        {
            FileLogger.Warn("Fermeture refusée : fenêtre non identifiée comme panneau NVIDIA (nvcplui)");
            return false;
        }

        try
        {
            var hwnd = new IntPtr(window.Current.NativeWindowHandle);
            if (hwnd == IntPtr.Zero) return false;

            if (!PanelWindowSafety.TryGetProcessName(hwnd, out var procName) ||
                PanelWindowSafety.IsExcludedProcessName(procName) ||
                !procName.Equals("nvcplui", StringComparison.OrdinalIgnoreCase))
            {
                FileLogger.Warn("Fermeture refusée : processus=" + (procName ?? "?"));
                return false;
            }

            Win32Helper.PostMessage(hwnd, Win32Helper.WmClose, IntPtr.Zero, IntPtr.Zero);
            Thread.Sleep(400);
            Win32Helper.SendMessage(hwnd, Win32Helper.WmSysCommand, Win32Helper.ScClose, IntPtr.Zero);
            Thread.Sleep(400);

            return WaitForPanelClosed(TimeSpan.FromSeconds(3));
        }
        catch (Exception ex)
        {
            FileLogger.Warn("Fermeture gracieuse panneau : " + ex.Message);
            return false;
        }
    }

    private static bool TryKillNvcpluiOnly()
    {
        FileLogger.Info("Fermeture nvcplui.exe (processus panneau uniquement)");
        var killed = false;
        foreach (var proc in Process.GetProcessesByName("nvcplui"))
        {
            try
            {
                proc.Kill();
                killed = true;
            }
            catch (Exception ex)
            {
                FileLogger.Warn("Kill nvcplui pid=" + proc.Id + " : " + ex.Message);
            }
            finally
            {
                proc.Dispose();
            }
        }

        Thread.Sleep(500);
        return killed && WaitForPanelClosed(TimeSpan.FromSeconds(2));
    }

    private static bool WaitForPanelClosed(TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (PanelLauncher.FindPanelWindowForClose() == null) return true;
            Thread.Sleep(250);
        }
        return PanelLauncher.FindPanelWindowForClose() == null;
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
}
