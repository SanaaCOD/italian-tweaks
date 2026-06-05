using System.Windows.Automation;
using NvidiaPanelClicker.Models;

namespace NvidiaPanelClicker.Services;

/// <summary>First-run NVIDIA Control Panel software license — non-blocking for full optimization.</summary>
public sealed class PanelLicenseAcceptService
{
    private static bool _hasAcceptedNvidiaControlPanelLicense;

    private static readonly string[] LicensePageMarkers =
    {
        "Contrat de licence logiciel NVIDIA",
        "NVIDIA Software License Agreement",
        "License For Customer Use of NVIDIA Software"
    };

    private static readonly string[] AcceptButtonAliases =
    {
        "Accepter et continuer",
        "Agree and Continue",
        "Accept and Continue"
    };

    public ClickerResult Run()
    {
        var result = new ClickerResult
        {
            Task = "accept-panel-license",
            Children = new Dictionary<string, string>()
        };

        if (_hasAcceptedNvidiaControlPanelLicense)
        {
            result.Success = true;
            result.UiStatus = "license_already_accepted";
            result.Message = "Licence déjà traitée dans cette session.";
            result.Children["licenseSkipped"] = "already_accepted";
            return result;
        }

        FileLogger.Info("ACCEPT_PANEL_LICENSE start (wait 1000ms)");
        Thread.Sleep(1000);

        var deadline = DateTime.UtcNow.AddSeconds(3);
        AutomationElement? panelWin = null;
        var licenseVisible = false;

        while (DateTime.UtcNow < deadline)
        {
            panelWin = FindNvidiaPanelWindow();
            if (panelWin != null && TestLicensePageVisible(panelWin))
            {
                licenseVisible = true;
                break;
            }
            Thread.Sleep(200);
        }

        if (!licenseVisible)
        {
            const string noLic = "[NVIDIA Control Panel] Aucune licence détectée, continuité normale.";
            FileLogger.Info(noLic);
            result.LogLines.Add(noLic);
            result.Success = true;
            result.UiStatus = "license_not_detected";
            result.Message = "Aucune page de licence détectée.";
            result.Children["licenseDetected"] = "non";
            return result;
        }

        const string detected = "[NVIDIA Control Panel] Licence détectée.";
        FileLogger.Info(detected);
        result.LogLines.Add(detected);

        if (panelWin == null)
        {
            result.Success = true;
            result.UiStatus = "license_window_lost";
            result.Message = "Licence détectée puis fenêtre perdue.";
            result.Children["licenseDetected"] = "oui";
            return result;
        }

        PanelLauncher.FocusAndMaximize(panelWin);
        Thread.Sleep(200);

        var acceptBtn = AutomationHelper.FindByAliases(panelWin, AcceptButtonAliases, ControlType.Button);
        if (acceptBtn != null && AutomationHelper.InvokeElement(acceptBtn))
        {
            const string clicked = "[NVIDIA Control Panel] Bouton Accepter et continuer cliqué.";
            FileLogger.Info(clicked);
            result.LogLines.Add(clicked);
            _hasAcceptedNvidiaControlPanelLicense = true;
            Thread.Sleep(800);
            result.Success = true;
            result.UiStatus = "license_accepted";
            result.Verified = true;
            result.Message = "Licence NVIDIA acceptée.";
            result.Children["licenseDetected"] = "oui";
            result.Children["licenseAccepted"] = "oui";
            return result;
        }

        FileLogger.Warn("Bouton Accepter introuvable — fallback clavier Entrée");
        try
        {
            var hwnd = new IntPtr(panelWin.Current.NativeWindowHandle);
            if (hwnd != IntPtr.Zero)
            {
                Win32Helper.SetForegroundWindow(hwnd);
                Thread.Sleep(200);
                Win32Helper.SendEnter();
                const string kb = "[NVIDIA Control Panel] Licence validée via fallback clavier.";
                FileLogger.Info(kb);
                result.LogLines.Add(kb);
                _hasAcceptedNvidiaControlPanelLicense = true;
                Thread.Sleep(800);
                result.Success = true;
                result.UiStatus = "license_accepted_keyboard";
                result.Message = "Licence validée via clavier.";
                result.Children["licenseDetected"] = "oui";
                result.Children["licenseAccepted"] = "keyboard";
                return result;
            }
        }
        catch (Exception ex)
        {
            FileLogger.Warn("Fallback clavier licence : " + ex.Message);
        }

        result.Success = true;
        result.UiStatus = "license_detected_not_accepted";
        result.Message = "Licence détectée — acceptation manuelle requise.";
        result.Children["licenseDetected"] = "oui";
        result.Children["licenseAccepted"] = "non";
        return result;
    }

    private static AutomationElement? FindNvidiaPanelWindow()
    {
        var win = PanelLauncher.FindPanelWindow();
        if (win == null) return null;
        try
        {
            var name = win.Current.Name ?? "";
            if (name.Contains("Panneau de configuration NVIDIA", StringComparison.OrdinalIgnoreCase)
                || name.Contains("NVIDIA Control Panel", StringComparison.OrdinalIgnoreCase))
                return win;
            if (TestLicensePageVisible(win))
                return win;
        }
        catch { }
        return win;
    }

    private static bool TestLicensePageVisible(AutomationElement root)
    {
        var blob = CollectVisibleText(root);
        if (string.IsNullOrWhiteSpace(blob)) return false;
        foreach (var marker in LicensePageMarkers)
        {
            if (blob.Contains(marker, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    private static string CollectVisibleText(AutomationElement root)
    {
        var parts = new List<string>();
        try
        {
            foreach (AutomationElement el in root.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
            {
                try
                {
                    var n = el.Current.Name;
                    if (!string.IsNullOrWhiteSpace(n))
                        parts.Add(n);
                }
                catch { }
            }
        }
        catch { }
        return string.Join("\n", parts);
    }
}
