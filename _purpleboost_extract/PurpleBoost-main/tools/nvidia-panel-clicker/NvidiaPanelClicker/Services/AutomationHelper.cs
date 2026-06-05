using System.Windows;
using System.Windows.Automation;

namespace NvidiaPanelClicker.Services;

internal static class AutomationHelper
{
    public static AutomationElement? FindByAliases(
        AutomationElement root,
        IEnumerable<string> aliases,
        params ControlType[] types)
    {
        var typeSet = types.Length > 0 ? new HashSet<ControlType>(types) : null;
        AutomationElement? best = null;
        var bestLen = 0;
        foreach (AutomationElement el in root.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
        {
            try
            {
                var name = el.Current.Name ?? "";
                if (string.IsNullOrWhiteSpace(name)) continue;
                if (typeSet != null && !typeSet.Contains(el.Current.ControlType)) continue;
                foreach (var alias in aliases)
                {
                    if (name.Contains(alias, StringComparison.OrdinalIgnoreCase) && alias.Length > bestLen)
                    {
                        best = el;
                        bestLen = alias.Length;
                    }
                }
            }
            catch { }
        }
        return best;
    }

    public static void ScrollIntoView(AutomationElement? el)
    {
        if (el == null) return;
        try
        {
            if (el.GetCurrentPattern(ScrollItemPattern.Pattern) is ScrollItemPattern sp)
                sp.ScrollIntoView();
        }
        catch { }
    }

    public static bool ClickElement(AutomationElement? el, bool useMouse = true)
    {
        if (el == null) return false;
        ScrollIntoView(el);
        Thread.Sleep(200);
        if (!useMouse)
            return InvokeElement(el);

        try
        {
            var rect = el.Current.BoundingRectangle;
            if (rect.Width > 2 && rect.Height > 2)
            {
                var x = (int)(rect.Left + rect.Width / 2);
                var y = (int)(rect.Top + rect.Height / 2);
                FileLogger.Info("[SAFE-UIA-RECT] clic centre élément UIA name=" + el.Current.Name
                    + " rect=" + (int)rect.Left + "," + (int)rect.Top + "," + (int)rect.Width + "x" + (int)rect.Height);
                Win32Helper.ClickScreenPoint(x, y);
                return true;
            }
        }
        catch { }

        return InvokeElement(el);
    }

    public static bool InvokeElement(AutomationElement el)
    {
        try
        {
            if (el.GetCurrentPattern(InvokePattern.Pattern) is InvokePattern inv)
            {
                inv.Invoke();
                FileLogger.Info("[SAFE-UIA] InvokePattern name=" + el.Current.Name);
                return true;
            }
        }
        catch { }
        try
        {
            if (el.GetCurrentPattern(SelectionItemPattern.Pattern) is SelectionItemPattern sel)
            {
                sel.Select();
                FileLogger.Info("[SAFE-UIA] SelectionItemPattern name=" + el.Current.Name);
                return true;
            }
        }
        catch { }
        try
        {
            if (el.GetCurrentPattern(ExpandCollapsePattern.Pattern) is ExpandCollapsePattern ec
                && ec.Current.ExpandCollapseState == ExpandCollapseState.Collapsed)
            {
                ec.Expand();
                return true;
            }
        }
        catch { }
        return false;
    }

    public static bool IsCheckboxChecked(AutomationElement? el)
    {
        if (el == null) return false;
        try
        {
            if (el.GetCurrentPattern(TogglePattern.Pattern) is TogglePattern tog)
                return tog.Current.ToggleState == ToggleState.On;
        }
        catch { }
        return false;
    }

    public static bool UncheckCheckbox(AutomationElement? el)
    {
        if (el == null) return false;
        if (!IsCheckboxChecked(el))
        {
            FileLogger.Info("CHECKBOX already unchecked: " + el.Current.Name);
            return true;
        }
        try
        {
            if (el.GetCurrentPattern(TogglePattern.Pattern) is TogglePattern tog)
            {
                tog.Toggle();
                Thread.Sleep(300);
                return !IsCheckboxChecked(el);
            }
        }
        catch { }
        return ClickElement(el);
    }

    public static bool SelectRadio(AutomationElement? el)
    {
        if (el == null) return false;
        ScrollIntoView(el);
        try
        {
            if (el.GetCurrentPattern(SelectionItemPattern.Pattern) is SelectionItemPattern sel)
            {
                if (!sel.Current.IsSelected) sel.Select();
                Thread.Sleep(250);
                return sel.Current.IsSelected;
            }
        }
        catch { }
        return ClickElement(el);
    }

    public static bool IsRadioSelected(AutomationElement? el)
    {
        if (el == null) return false;
        try
        {
            if (el.GetCurrentPattern(SelectionItemPattern.Pattern) is SelectionItemPattern sel)
                return sel.Current.IsSelected;
        }
        catch { }
        return false;
    }

    public static void LogWindowRect(AutomationElement window, string label)
    {
        try
        {
            var r = window.Current.BoundingRectangle;
            FileLogger.Info(label + " left=" + (int)r.Left + " top=" + (int)r.Top
                + " width=" + (int)r.Width + " height=" + (int)r.Height);
        }
        catch (Exception ex)
        {
            FileLogger.Warn(label + " rect unavailable: " + ex.Message);
        }
    }

}
