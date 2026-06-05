using System.Windows;
using System.Windows.Automation;

namespace NvidiaPanelClicker.Services;

internal static class PreviewPerformanceUia
{
    private static readonly string[] PreviewPageAliases =
    {
        "Régler les paramètres d'image avec aperçu",
        "Regler les parametres d'image avec apercu",
        "Ajuster les paramètres d'image avec aperçu",
        "Adjust image settings with preview",
        "image settings with preview"
    };

    private static readonly string[] NavParentAliases =
    {
        "3D Settings",
        "Paramètres 3D",
        "Gérer les paramètres 3D",
        "Manage 3D settings",
        "Adjust image settings"
    };

    private static readonly string[] PreferenceRadioAliases =
    {
        "Utiliser mes préférences pour améliorer",
        "Utiliser mes preferences pour ameliorer",
        "Utiliser ma préférence en mettant l'accent sur",
        "Utiliser ma preference en mettant l'accent sur",
        "Utiliser mes préférences pour accentuer",
        "Use my preference emphasizing",
        "my preference emphasizing"
    };

    private static readonly string[] Advanced3DRadioAliases =
    {
        "Utiliser les paramètres d'image 3D avancés",
        "Utiliser les parametres d'image 3D avances",
        "Use the advanced 3D image settings",
        "advanced 3D image settings",
        "paramètres d'image 3D avancés",
        "parametres d'image 3D avances"
    };

    private static readonly TimeSpan ControlTimeout = TimeSpan.FromSeconds(8);

    public static bool ApplySequence(AutomationElement window, out string? failureStep)
    {
        failureStep = null;

        var prefRadio = WaitFor(() => FindRadio(window, PreferenceRadioAliases), ControlTimeout);
        if (prefRadio == null)
        {
            failureStep = "radio préférence";
            FileLogger.Info("Radio préférence performance trouvée non");
            return false;
        }

        FileLogger.Info("Radio préférence performance trouvée oui");
        if (!AutomationHelper.SelectRadio(prefRadio))
        {
            failureStep = "sélection radio préférence";
            return false;
        }

        FileLogger.Info("Radio préférence performance sélectionnée");
        Thread.Sleep(300);

        var slider = WaitFor(() => FindPerformanceSlider(window), ControlTimeout);
        if (slider == null)
        {
            failureStep = "slider";
            FileLogger.Info("Slider trouvé non");
            return false;
        }

        FileLogger.Info("Slider trouvé oui");
        var before = ReadSliderValue(slider);
        FileLogger.Info("Valeur slider avant : " + before);

        if (!SetSliderToPerformance(window, slider))
        {
            failureStep = "curseur performance";
            return false;
        }

        Thread.Sleep(300);
        var after = ReadSliderValue(slider);
        FileLogger.Info("Valeur slider après : " + after);

        var advancedRadio = WaitFor(() => FindRadio(window, Advanced3DRadioAliases), ControlTimeout);
        if (advancedRadio == null)
        {
            failureStep = "radio paramètres 3D avancés";
            FileLogger.Info("Radio paramètres 3D avancés trouvée non");
            return false;
        }

        FileLogger.Info("Radio paramètres 3D avancés trouvée oui");
        if (!AutomationHelper.SelectRadio(advancedRadio))
        {
            failureStep = "sélection radio 3D avancés";
            return false;
        }

        FileLogger.Info("Radio paramètres 3D avancés sélectionnée");
        return true;
    }

    public static AutomationElement? OpenPreviewPage(AutomationElement window)
    {
        var types = new[]
        {
            ControlType.TreeItem,
            ControlType.ListItem,
            ControlType.Hyperlink,
            ControlType.MenuItem,
            ControlType.Text
        };

        var page = AutomationHelper.FindByAliases(window, PreviewPageAliases, types)
            ?? AutomationHelper.FindByAliases(window, PreviewPageAliases);
        if (page != null) return page;

        var parent = AutomationHelper.FindByAliases(window, NavParentAliases, types)
            ?? AutomationHelper.FindByAliases(window, NavParentAliases);
        if (parent != null)
        {
            FileLogger.Info("Navigation parent 3D/image pour page aperçu");
            AutomationHelper.ClickElement(parent);
            Thread.Sleep(600);
            page = AutomationHelper.FindByAliases(window, PreviewPageAliases, types)
                ?? AutomationHelper.FindByAliases(window, PreviewPageAliases);
        }

        return page;
    }

    private static AutomationElement? WaitFor(Func<AutomationElement?> find, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            var el = find();
            if (el != null) return el;
            Thread.Sleep(250);
        }
        return null;
    }

    private static AutomationElement? FindRadio(AutomationElement root, string[] aliases)
    {
        return AutomationHelper.FindByAliases(root, aliases, ControlType.RadioButton)
            ?? AutomationHelper.FindByAliases(root, aliases);
    }

    private static AutomationElement? FindPerformanceSlider(AutomationElement root)
    {
        AutomationElement? best = null;
        var bestScore = -1;

        foreach (AutomationElement el in root.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
        {
            try
            {
                if (el.GetCurrentPattern(RangeValuePattern.Pattern) is not RangeValuePattern rv) continue;
                if (rv.Current.Maximum <= rv.Current.Minimum) continue;

                var score = 0;
                if (el.Current.ControlType == ControlType.Slider) score += 3;
                var name = el.Current.Name ?? "";
                if (name.Contains("Perform", StringComparison.OrdinalIgnoreCase)
                    || name.Contains("Qualit", StringComparison.OrdinalIgnoreCase)
                    || name.Contains("Quality", StringComparison.OrdinalIgnoreCase)
                    || name.Contains("accent", StringComparison.OrdinalIgnoreCase)
                    || name.Contains("image", StringComparison.OrdinalIgnoreCase)
                    || name.Contains("aperçu", StringComparison.OrdinalIgnoreCase)
                    || name.Contains("preview", StringComparison.OrdinalIgnoreCase))
                    score += 2;

                if (score > bestScore)
                {
                    best = el;
                    bestScore = score;
                }
            }
            catch { }
        }

        if (best != null) return best;

        foreach (AutomationElement el in root.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
        {
            if (el.Current.ControlType == ControlType.Slider)
                return el;
        }

        return null;
    }

    private static string ReadSliderValue(AutomationElement slider)
    {
        try
        {
            if (slider.GetCurrentPattern(RangeValuePattern.Pattern) is RangeValuePattern rv)
                return rv.Current.Value.ToString("0.##") + " (min=" + rv.Current.Minimum + " max=" + rv.Current.Maximum + ")";
        }
        catch { }
        return "inconnue";
    }

    private static bool SetSliderToPerformance(AutomationElement window, AutomationElement slider)
    {
        AutomationHelper.ScrollIntoView(slider);
        Thread.Sleep(150);

        try
        {
            if (slider.GetCurrentPattern(RangeValuePattern.Pattern) is RangeValuePattern rv)
            {
                var target = rv.Current.Minimum;
                FileLogger.Info("Slider RangeValue → Performance (minimum)=" + target);
                rv.SetValue(target);
                Thread.Sleep(200);
                if (Math.Abs(rv.Current.Value - target) <= 1.0) return true;
            }
        }
        catch (Exception ex)
        {
            FileLogger.Warn("RangeValuePattern slider : " + ex.Message);
        }

        try
        {
            var rect = slider.Current.BoundingRectangle;
            if (rect.Width >= 4 && rect.Height >= 2)
            {
                var x = (int)(rect.Left + rect.Width / 2);
                var y = (int)(rect.Top + rect.Height / 2);
                FileLogger.Info("[SAFE-UIA-RECT] clic centre slider UIA name="
                    + (slider.Current.Name ?? "")
                    + " rect=" + (int)rect.Left + "," + (int)rect.Top + "," + (int)rect.Width + "x" + (int)rect.Height);
                Win32Helper.ClickScreenPoint(x, y);
                return true;
            }
        }
        catch (Exception ex)
        {
            FileLogger.Warn("Clic BoundingRectangle slider : " + ex.Message);
        }

        return false;
    }
}
