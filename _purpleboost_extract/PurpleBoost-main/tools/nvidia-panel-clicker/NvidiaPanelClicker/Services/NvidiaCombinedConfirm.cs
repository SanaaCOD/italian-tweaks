using System.Text;
using System.Windows.Automation;

namespace NvidiaPanelClicker.Services;

/// <summary>Confirmation « enregistrer les modifications bureau » — uniquement pour le bouton combiné.</summary>
internal static class NvidiaCombinedConfirm
{
    private static readonly string[] ConfirmPhrases =
    {
        "La configuration de votre bureau a été modifiée",
        "La configuration de votre bureau a ete modifiee",
        "Voulez-vous enregistrer les modifications",
        "configuration de votre bureau",
        "save changes",
        "keep changes",
        "desktop settings have been changed",
        "save the changes"
    };

    private static readonly string[] MainPanelTitleHints =
    {
        "Panneau de configuration NVIDIA",
        "NVIDIA Control Panel",
        "Centre de configuration NVIDIA"
    };

    public static bool ConfirmNvidiaChangesIfVisible()
    {
        FileLogger.Info("Recherche confirmation NVIDIA");
        Thread.Sleep(500);

        var deadline = DateTime.UtcNow + TimeSpan.FromMilliseconds(6000);
        while (DateTime.UtcNow < deadline)
        {
            var dialog = FindSaveChangesDialog();
            if (dialog != null)
            {
                FileLogger.Info("Confirmation détectée oui");
                try
                {
                    var hwnd = new IntPtr(dialog.Current.NativeWindowHandle);
                    if (hwnd != IntPtr.Zero)
                        Win32Helper.SetForegroundWindow(hwnd);
                }
                catch { }

                Thread.Sleep(200);
                System.Windows.Forms.SendKeys.SendWait("{LEFT}");
                Thread.Sleep(150);
                System.Windows.Forms.SendKeys.SendWait("{ENTER}");
                FileLogger.Info("Confirmation NVIDIA détectée — LEFT + ENTER envoyé");
                Thread.Sleep(1000);
                return true;
            }

            Thread.Sleep(250);
        }

        FileLogger.Info("Aucune confirmation NVIDIA détectée");
        FileLogger.Info("Confirmation détectée non");
        return false;
    }

    private static AutomationElement? FindSaveChangesDialog()
    {
        try
        {
            foreach (AutomationElement w in AutomationElement.RootElement.FindAll(
                         TreeScope.Children, System.Windows.Automation.Condition.TrueCondition))
            {
                var match = TryMatchDialog(w);
                if (match != null) return match;
            }

            foreach (AutomationElement el in AutomationElement.RootElement.FindAll(
                         TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
            {
                try
                {
                    var ct = el.Current.ControlType;
                    if (ct != ControlType.Window && ct != ControlType.Pane) continue;
                    var match = TryMatchDialog(el);
                    if (match != null) return match;
                }
                catch { }
            }
        }
        catch { }

        return null;
    }

    private static AutomationElement? TryMatchDialog(AutomationElement el)
    {
        try
        {
            var title = el.Current.Name ?? "";
            if (IsMainNvidiaPanelTitle(title)) return null;

            var blob = BuildTextBlob(el);
            if (!MatchesSaveChangesPrompt(blob)) return null;

            if (el.Current.ControlType == ControlType.Window
                || el.Current.ClassName.Contains("32770", StringComparison.Ordinal)
                || title.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase)
                || blob.Contains("modifications", StringComparison.OrdinalIgnoreCase))
                return el;
        }
        catch { }

        return null;
    }

    private static bool IsMainNvidiaPanelTitle(string title)
    {
        if (string.IsNullOrWhiteSpace(title)) return false;
        foreach (var hint in MainPanelTitleHints)
        {
            if (title.Contains(hint, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    private static string BuildTextBlob(AutomationElement root)
    {
        var sb = new StringBuilder();
        try
        {
            var n = root.Current.Name;
            if (!string.IsNullOrWhiteSpace(n)) sb.Append(n).Append(' ');
        }
        catch { }

        var count = 0;
        foreach (AutomationElement el in root.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
        {
            if (count++ > 120) break;
            try
            {
                var name = el.Current.Name;
                if (!string.IsNullOrWhiteSpace(name))
                    sb.Append(name).Append(' ');
            }
            catch { }
        }

        return sb.ToString();
    }

    private static bool MatchesSaveChangesPrompt(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;
        foreach (var phrase in ConfirmPhrases)
        {
            if (text.Contains(phrase, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }
}
