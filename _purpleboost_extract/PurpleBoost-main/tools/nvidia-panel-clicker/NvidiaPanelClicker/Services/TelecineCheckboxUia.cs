using System.Windows.Automation;

namespace NvidiaPanelClicker.Services;

public sealed class TelecineUncheckResult
{
    public bool Found { get; set; }
    public bool WasChecked { get; set; }
    public string Action { get; set; } = "";
}

internal static class TelecineCheckboxUia
{
    private static readonly string[] NameVariants =
    {
        "Utiliser téléciné inversé",
        "Utiliser la téléciné inversée",
        "Utiliser telecine inverse",
        "Utiliser la telecine inversee",
        "téléciné",
        "telecine",
        "inverse telecine",
        "Use inverse telecine"
    };

    public static TelecineUncheckResult? TryFindAndUncheck(AutomationElement window, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            var checkboxes = EnumerateCheckBoxes(window);
            var match = SelectTelecineCheckbox(window, checkboxes);
            if (match != null)
            {
                LogAllCheckBoxes(window);
                FileLogger.Info("Checkbox téléciné trouvée oui");
                return UncheckCheckbox(window, match);
            }

            Thread.Sleep(250);
        }

        FileLogger.Info("Checkbox téléciné trouvée non");
        LogAllCheckBoxes(window);
        return null;
    }

    private static List<(AutomationElement Element, string DisplayName, int Score)> EnumerateCheckBoxes(AutomationElement window)
    {
        var list = new List<(AutomationElement, string, int)>();
        foreach (AutomationElement el in window.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
        {
            try
            {
                if (el.Current.ControlType != ControlType.CheckBox) continue;
                var displayName = GetCheckBoxDisplayName(el);
                var score = ScoreNameMatch(displayName);
                list.Add((el, displayName, score));
            }
            catch { }
        }
        return list;
    }

    private static AutomationElement? SelectTelecineCheckbox(
        AutomationElement window,
        List<(AutomationElement Element, string DisplayName, int Score)> checkboxes)
    {
        AutomationElement? best = null;
        var bestScore = 0;
        foreach (var cb in checkboxes)
        {
            if (cb.Score <= 0) continue;
            if (cb.Score > bestScore)
            {
                best = cb.Element;
                bestScore = cb.Score;
            }
        }

        if (best != null) return best;
        return FindCheckboxAdjacentToTelecineLabel(window);
    }

    private static AutomationElement? FindCheckboxAdjacentToTelecineLabel(AutomationElement window)
    {
        foreach (AutomationElement el in window.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
        {
            try
            {
                if (el.Current.ControlType == ControlType.CheckBox) continue;
                var label = el.Current.Name ?? "";
                if (ScoreNameMatch(label) <= 0) continue;

                var parent = TreeWalker.ControlViewWalker.GetParent(el);
                if (parent == null) continue;

                foreach (AutomationElement sib in parent.FindAll(TreeScope.Children, System.Windows.Automation.Condition.TrueCondition))
                {
                    if (sib.Current.ControlType != ControlType.CheckBox) continue;
                    FileLogger.Info("Checkbox téléciné via libellé UIA adjacent : \"" + label + "\"");
                    return sib;
                }
            }
            catch { }
        }

        return null;
    }

    private static TelecineUncheckResult UncheckCheckbox(AutomationElement window, AutomationElement checkbox)
    {
        AutomationHelper.ScrollIntoView(checkbox);
        Thread.Sleep(150);

        var wasChecked = ReadIsChecked(checkbox);
        FileLogger.Info("État avant : " + (wasChecked ? "cochée" : "décochée"));
        LogCheckBoxEntry("Checkbox téléciné cible", checkbox);

        if (!wasChecked)
        {
            FileLogger.Info("Action : déjà décochée");
            return new TelecineUncheckResult { Found = true, WasChecked = false, Action = "déjà décochée" };
        }

        if (TryToggleOff(checkbox) || TryInvoke(checkbox) || TryClickBoundingRectangle(window, checkbox))
        {
            Thread.Sleep(200);
            var nowOff = !ReadIsChecked(checkbox);
            FileLogger.Info("Action : " + (nowOff ? "décochée" : "décochée (toggle envoyé)"));
            return new TelecineUncheckResult { Found = true, WasChecked = true, Action = "décochée" };
        }

        FileLogger.Warn("Impossible de décocher via UIA");
        return new TelecineUncheckResult { Found = true, WasChecked = true, Action = "échec décochage" };
    }

    private static bool ReadIsChecked(AutomationElement checkbox)
    {
        try
        {
            if (checkbox.GetCurrentPattern(TogglePattern.Pattern) is TogglePattern tog)
                return tog.Current.ToggleState == ToggleState.On;
        }
        catch { }
        return AutomationHelper.IsCheckboxChecked(checkbox);
    }

    private static bool TryToggleOff(AutomationElement checkbox)
    {
        try
        {
            if (checkbox.GetCurrentPattern(TogglePattern.Pattern) is TogglePattern tog)
            {
                if (tog.Current.ToggleState == ToggleState.On)
                    tog.Toggle();
                return true;
            }
        }
        catch { }
        return false;
    }

    private static bool TryInvoke(AutomationElement checkbox)
    {
        try
        {
            if (checkbox.GetCurrentPattern(InvokePattern.Pattern) is InvokePattern inv)
            {
                inv.Invoke();
                return true;
            }
        }
        catch { }
        return false;
    }

    private static bool TryClickBoundingRectangle(AutomationElement window, AutomationElement checkbox)
    {
        try
        {
            var rect = checkbox.Current.BoundingRectangle;
            if (rect.Width < 2 || rect.Height < 2) return false;
            var x = (int)(rect.Left + rect.Width / 2);
            var y = (int)(rect.Top + rect.Height / 2);
            var wr = window.Current.BoundingRectangle;
            FileLogger.Info("[SAFE-UIA-RECT] clic centre checkbox UIA name="
                + (checkbox.Current.Name ?? "")
                + " rect=" + (int)rect.Left + "," + (int)rect.Top + "," + (int)rect.Width + "x" + (int)rect.Height);
            Win32Helper.ClickScreenPoint(x, y);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void LogAllCheckBoxes(AutomationElement window)
    {
        FileLogger.Info("CheckBox trouvées :");
        var checkboxes = EnumerateCheckBoxes(window);
        if (checkboxes.Count == 0)
        {
            FileLogger.Info("  (aucune CheckBox dans le panneau)");
            return;
        }

        foreach (var cb in checkboxes)
            LogCheckBoxEntry("  -", cb.Element, cb.DisplayName);
    }

    private static void LogCheckBoxEntry(string prefix, AutomationElement cb, string? displayName = null)
    {
        try
        {
            var name = displayName ?? GetCheckBoxDisplayName(cb);
            var state = ReadIsChecked(cb) ? "cochée" : "décochée";
            var r = cb.Current.BoundingRectangle;
            FileLogger.Info(prefix + " nom=\"" + name + "\" état=" + state
                + " rect=" + (int)r.Left + "," + (int)r.Top + "," + (int)r.Width + "x" + (int)r.Height);
        }
        catch (Exception ex)
        {
            FileLogger.Info(prefix + " (illisible: " + ex.Message + ")");
        }
    }

    private static string GetCheckBoxDisplayName(AutomationElement checkbox)
    {
        var direct = checkbox.Current.Name ?? "";
        if (!string.IsNullOrWhiteSpace(direct)) return direct.Trim();

        try
        {
            var parent = TreeWalker.ControlViewWalker.GetParent(checkbox);
            if (parent == null) return "";

            foreach (AutomationElement sib in parent.FindAll(TreeScope.Children, System.Windows.Automation.Condition.TrueCondition))
            {
                if (sib.Equals(checkbox)) continue;
                var n = sib.Current.Name ?? "";
                if (!string.IsNullOrWhiteSpace(n)) return n.Trim();
            }

            for (var d = 0; d < 4 && parent != null; d++)
            {
                foreach (AutomationElement el in parent.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
                {
                    if (el.Current.ControlType == ControlType.CheckBox) continue;
                    var n = el.Current.Name ?? "";
                    if (!string.IsNullOrWhiteSpace(n) && ScoreNameMatch(n) > 0)
                        return n.Trim();
                }
                parent = TreeWalker.ControlViewWalker.GetParent(parent);
            }
        }
        catch { }

        return "";
    }

    private static int ScoreNameMatch(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return 0;
        var best = 0;
        foreach (var variant in NameVariants)
        {
            if (!name.Contains(variant, StringComparison.OrdinalIgnoreCase)) continue;
            if (variant.Length > best) best = variant.Length;
        }
        return best;
    }
}
