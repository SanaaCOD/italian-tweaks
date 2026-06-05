using System.Diagnostics;
using System.Windows.Automation;
using NvidiaPanelClicker.Models;

namespace NvidiaPanelClicker.Services;

public sealed class PanelClickerService
{
    private static readonly string[] ApplyAliases = { "Appliquer", "Apply" };
    private static readonly string[] VideoPageAliases =
    {
        "Régler les paramètres d'image vidéo",
        "Regler les parametres d'image video",
        "Adjust video image settings",
        "video image settings"
    };
    private static readonly string[] DesktopPageAliases =
    {
        "Régler la taille et la position du bureau",
        "Regler la taille et la position du bureau",
        "Adjust desktop size and position",
        "desktop size and position"
    };
    private static readonly string[] NoScalingAliases =
    {
        "Pas de mise à l'échelle",
        "Pas de mise a l'echelle",
        "No scaling",
        "Aucune mise à l'échelle"
    };

    private readonly TimeSpan _panelTimeout = TimeSpan.FromSeconds(20);

    public ClickerResult RunInverseTelecine()
    {
        var result = new ClickerResult { Task = "inverse-telecine" };
        try
        {
            FileLogger.Info("Début action téléciné inversée");
            var window = OpenPanel();
            if (window == null)
                return Error(result, "Panneau NVIDIA introuvable");

            FileLogger.Info("Panneau NVIDIA ouvert");

            var page = AutomationHelper.FindByAliases(window, VideoPageAliases,
                ControlType.TreeItem, ControlType.ListItem, ControlType.Hyperlink, ControlType.Text)
                ?? AutomationHelper.FindByAliases(window, VideoPageAliases);
            if (page == null)
                return Error(result, "Page image vidéo introuvable dans le panneau");

            if (!AutomationHelper.ClickElement(page))
                return Error(result, "Navigation page image vidéo impossible");

            FileLogger.Info("Page paramètres image vidéo sélectionnée");
            Thread.Sleep(1200);
            FileLogger.Info("Page vidéo atteinte");

            var telecine = TelecineCheckboxUia.TryFindAndUncheck(window, TimeSpan.FromSeconds(8));
            if (telecine == null || !telecine.Found)
                return Error(result, "Checkbox téléciné introuvable");

            Thread.Sleep(500);

            if (!ClickApply(window))
                return Error(result, "Appliquer introuvable ou clic impossible");

            FileLogger.Info("Appliquer cliqué");
            SendLeftEnterAfterApplyForInverseTelecine();
            FileLogger.Info("Action téléciné terminée");

            return Sent(result, "Téléciné inversée : action panneau envoyée", false);
        }
        catch (Exception ex)
        {
            FileLogger.Error("TASK inverse-telecine exception: " + ex.Message);
            return Error(result, "Erreur automatisation panneau : " + ex.Message);
        }
    }

    public ClickerResult RunPreviewPerformance()
    {
        var result = new ClickerResult { Task = "preview-performance" };
        try
        {
            FileLogger.Info("Début action mode performance aperçu");
            var window = OpenPanel();
            if (window == null)
                return Error(result, "Mode performance NVIDIA : contrôle panneau introuvable");

            FileLogger.Info("Panneau NVIDIA ouvert");

            var page = PreviewPerformanceUia.OpenPreviewPage(window);
            if (page == null)
                return Error(result, "Mode performance NVIDIA : contrôle panneau introuvable");

            if (!AutomationHelper.ClickElement(page))
                return Error(result, "Mode performance NVIDIA : contrôle panneau introuvable");

            Thread.Sleep(900);
            FileLogger.Info("Page « Régler les paramètres d'image avec aperçu » atteinte");

            if (!PreviewPerformanceUia.ApplySequence(window, out var failureStep))
            {
                FileLogger.Warn("Étape échouée : " + (failureStep ?? "inconnue"));
                return Error(result, "Mode performance NVIDIA : contrôle panneau introuvable");
            }

            Thread.Sleep(300);
            if (!ClickApply(window))
                return Error(result, "Mode performance NVIDIA : contrôle panneau introuvable");

            FileLogger.Info("Appliquer cliqué");
            FileLogger.Info("Action terminée");

            return Sent(result, "Mode performance NVIDIA : action panneau envoyée", false);
        }
        catch (Exception ex)
        {
            FileLogger.Error("TASK preview-performance exception: " + ex.Message);
            return Error(result, "Mode performance NVIDIA : contrôle panneau introuvable");
        }
    }

    public ClickerResult EnsureNvidiaControlPanelOpen()
    {
        var result = new ClickerResult { Task = "ensure-panel-open" };
        FileLogger.Info("Étape panneau NVIDIA : ouverture panneau");

        var launcher = new PanelLauncher();
        var existing = PanelLauncher.FindPanelWindow();
        var alreadyOpen = existing != null;
        FileLogger.Info("Panneau NVIDIA déjà ouvert : " + (alreadyOpen ? "oui" : "non"));

        if (alreadyOpen)
        {
            PanelLauncher.FocusAndMaximize(existing!);
            Thread.Sleep(1000);
            FileLogger.Info("Fenêtre panneau NVIDIA détectée : oui");
            FileLogger.Info("Panneau NVIDIA prêt");
            return Sent(result, "Panneau NVIDIA prêt", true);
        }

        if (!launcher.TryLaunchResolved())
            return Error(result, "Panneau NVIDIA introuvable — nvcplui.exe non trouvé");

        existing = launcher.WaitForPanelWindow(_panelTimeout);
        var windowFound = existing != null;
        FileLogger.Info("Fenêtre panneau NVIDIA détectée : " + (windowFound ? "oui" : "non"));
        if (!windowFound)
            return Error(result, "Panneau NVIDIA introuvable — fenêtre non détectée après 20 s");

        PanelLauncher.FocusAndMaximize(existing!);
        Thread.Sleep(1500);
        FileLogger.Info("Panneau NVIDIA prêt");
        return Sent(result, "Panneau NVIDIA prêt", false);
    }

    public ClickerResult RunCombinedPanelSettings(string purpleBoostRoot)
    {
        const string successMessage =
            "Réglages panneau NVIDIA : action envoyée — pas de mise à l'échelle, mode performance, téléciné inversée";
        var result = new ClickerResult { Task = "apply-panel-nvidia-settings" };
        var cfg = NvidiaOptimizationConfig.Load(purpleBoostRoot);
        var panel = cfg.PanelSettings;
        var finalLogDir = Path.Combine(purpleBoostRoot, "logs", "nvidia-final");
        Directory.CreateDirectory(finalLogDir);

        var children = new Dictionary<string, string>();

        FileLogger.Info("Début action combinée panneau NVIDIA");

        FileLogger.Info("Ouverture panneau NVIDIA depuis bouton combiné");
        if (OpenPanel() == null)
            return Error(result, "Panneau NVIDIA introuvable");
        FileLogger.Info("Panneau NVIDIA prêt");

        if (panel.RunNoScaling)
        {
            FileLogger.Info("progress=65 no-scaling");
            FileLogger.Info("Étape 1/3 : pas de mise à l'échelle");
            var log1 = Path.Combine(finalLogDir, "04a-no-scaling.log");
            if (!RunCombinedExternalTask(purpleBoostRoot, "no-scaling", "Étape 1/3", log1, out var exit1))
                return Error(result, "Réglages panneau NVIDIA : timeout ou échec lancement étape 1 (pas de mise à l'échelle)");
            children["noScaling"] = ChildStatus(exit1);

            FileLogger.Info("Étape 1 terminée");
            NvidiaCombinedConfirm.ConfirmNvidiaChangesIfVisible();
            FileLogger.Info("Confirmation NVIDIA vérifiée");
            var delay1 = Math.Max(0, panel.DelayAfterNoScalingMs);
            FileLogger.Info("Pause " + delay1 + " ms après étape 1");
            Thread.Sleep(delay1);
        }
        else
        {
            children["noScaling"] = "skipped";
            FileLogger.Info("Étape 1/3 ignorée (config)");
        }

        if (panel.RunPreviewPerformance)
        {
            FileLogger.Info("progress=80 preview-performance");
            FileLogger.Info("Étape 2/3 : mode performance NVIDIA");
            var log2 = Path.Combine(finalLogDir, "04b-preview-performance.log");
            if (!RunCombinedExternalTask(purpleBoostRoot, "preview-performance", "Étape 2/3", log2, out var exit2))
                return Error(result, "Réglages panneau NVIDIA : timeout ou échec lancement étape 2 (mode performance)");
            children["previewPerformance"] = ChildStatus(exit2);

            NvidiaCombinedConfirm.ConfirmNvidiaChangesIfVisible();
            FileLogger.Info("Confirmation NVIDIA vérifiée");
            var delay2 = Math.Max(0, panel.DelayBetweenPanelStepsMs);
            FileLogger.Info("Pause " + delay2 + " ms");
            Thread.Sleep(delay2);
        }
        else
        {
            children["previewPerformance"] = "skipped";
            FileLogger.Info("Étape 2/3 ignorée (config)");
        }

        if (panel.RunInverseTelecine)
        {
            FileLogger.Info("progress=95 inverse-telecine");
            FileLogger.Info("Étape 3/3 : téléciné inversée");
            var log3 = Path.Combine(finalLogDir, "04c-inverse-telecine.log");
            if (!RunCombinedExternalTask(purpleBoostRoot, "inverse-telecine", "Étape 3/3", log3, out var exit3))
                return Error(result, "Réglages panneau NVIDIA : timeout ou échec lancement étape 3 (téléciné inversée)");
            children["inverseTelecine"] = ChildStatus(exit3);

            NvidiaCombinedConfirm.ConfirmNvidiaChangesIfVisible();
            FileLogger.Info("Confirmation NVIDIA vérifiée");
        }
        else
        {
            children["inverseTelecine"] = "skipped";
            FileLogger.Info("Étape 3/3 ignorée (config)");
        }

        result.Children = children;
        var aggregate = AggregatePanelChildrenStatus(children);
        FileLogger.Info("Action combinée terminée — statut panneau=" + aggregate);
        if (aggregate == "error")
            return Error(result, "Réglages panneau NVIDIA : une ou plusieurs étapes en erreur");

        return Sent(result, "Réglages panneau NVIDIA : appliqué", aggregate == "applied");
    }

    private static string ChildStatus(int exitCode) => exitCode == 0 ? "applied" : "error";

    private static string AggregatePanelChildrenStatus(Dictionary<string, string> children)
    {
        var hasError = children.Values.Any(v => v == "error");
        if (hasError) return "error";
        var anyRan = children.Values.Any(v => v == "applied");
        if (!anyRan && children.Values.All(v => v == "skipped")) return "skipped";
        return "applied";
    }

    private static bool RunCombinedExternalTask(string purpleBoostRoot, string task, string stepLabel, string? childLogPath, out int exitCode)
    {
        exitCode = -1;
        const int timeoutMs = 45_000;

        var exe = ResolveNvidiaPanelClickerExePath();
        if (string.IsNullOrEmpty(exe))
        {
            FileLogger.Error(stepLabel + " : NvidiaPanelClicker.exe introuvable");
            return false;
        }

        var args = "--json --purpleboost-root \"" + purpleBoostRoot + "\" --task " + task;
        if (!string.IsNullOrWhiteSpace(childLogPath))
            args += " --log-file \"" + childLogPath + "\"";
        FileLogger.Info(stepLabel + " : lancement process " + task);

        try
        {
            using var proc = Process.Start(new ProcessStartInfo
            {
                FileName = exe,
                Arguments = args,
                WorkingDirectory = Path.GetDirectoryName(exe) ?? purpleBoostRoot,
                UseShellExecute = false,
                CreateNoWindow = true
            });

            if (proc == null)
            {
                FileLogger.Error(stepLabel + " : échec démarrage process");
                return false;
            }

            if (!proc.WaitForExit(timeoutMs))
            {
                try { proc.Kill(true); } catch { }
                FileLogger.Error(stepLabel + " : timeout après " + timeoutMs + " ms");
                return false;
            }

            exitCode = proc.ExitCode;
            FileLogger.Info(stepLabel + " : process terminé exitCode=" + exitCode);
            return true;
        }
        catch (Exception ex)
        {
            FileLogger.Error(stepLabel + " : exception " + ex.Message);
            return false;
        }
    }

    private static string? ResolveNvidiaPanelClickerExePath()
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(processPath) && File.Exists(processPath))
            return processPath;

        var baseDir = AppContext.BaseDirectory;
        foreach (var c in new[]
        {
            Path.Combine(baseDir, "NvidiaPanelClicker.exe"),
            Path.Combine(baseDir, "..", "NvidiaPanelClicker.exe"),
            Path.Combine(baseDir, "..", "..", "NvidiaPanelClicker.exe")
        })
        {
            var full = Path.GetFullPath(c);
            if (File.Exists(full)) return full;
        }

        return null;
    }

    public ClickerResult RunNoScaling()
    {
        var result = new ClickerResult { Task = "no-scaling" };
        try
        {
            var window = OpenPanel();
            if (window == null)
                return Error(result, "Panneau NVIDIA introuvable");

            FileLogger.Info("PAGE=desktop size and position");
            var page = AutomationHelper.FindByAliases(window, DesktopPageAliases,
                ControlType.TreeItem, ControlType.ListItem, ControlType.Hyperlink, ControlType.Text)
                ?? AutomationHelper.FindByAliases(window, DesktopPageAliases);
            if (page == null)
                return Error(result, "Page taille/position bureau introuvable");

            if (!AutomationHelper.ClickElement(page))
                return Error(result, "Navigation page bureau impossible");

            Thread.Sleep(900);
            FileLogger.Info("TARGET=no scaling radio");
            var radio = FindNoScalingRadioByAliases(window);
            if (radio == null)
                return Error(result, "Bouton « Pas de mise à l'échelle » introuvable");

            if (!ClickNoScalingRadio(radio))
                return Error(result, "Clic « Pas de mise à l'échelle » impossible");

            Thread.Sleep(400);
            var verified = AutomationHelper.IsRadioSelected(radio);
            FileLogger.Info("RADIO selected=" + verified);

            if (!ClickApply(window))
                FileLogger.Warn("APPLY button not clicked");
            else
                SendLeftEnterAfterApplyForNoScaling();

            return Sent(result,
                "Pas de mise à l'échelle : action panneau envoyée" + (verified ? " — radio sélectionnée" : " — vérification visuelle requise"),
                false);
        }
        catch (Exception ex)
        {
            FileLogger.Error("TASK no-scaling exception: " + ex.Message);
            return Error(result, "Erreur automatisation panneau : " + ex.Message);
        }
    }

    /// <summary>FindByAliases : en cas de doublons, garde le radio le plus à gauche dans le panneau droit (log OK ~620,502).</summary>
    private static AutomationElement? FindNoScalingRadioByAliases(AutomationElement window)
    {
        try
        {
            var wr = window.Current.BoundingRectangle;
            if (wr.Width < 10) return null;
            var minContentX = wr.Left + wr.Width * 0.22;

            AutomationElement? best = null;
            var bestAliasLen = 0;
            var bestLeft = double.MaxValue;

            foreach (AutomationElement el in window.FindAll(TreeScope.Descendants, System.Windows.Automation.Condition.TrueCondition))
            {
                try
                {
                    if (el.Current.ControlType != ControlType.RadioButton) continue;
                    var name = el.Current.Name ?? "";
                    if (string.IsNullOrWhiteSpace(name)) continue;

                    var aliasLen = 0;
                    foreach (var alias in NoScalingAliases)
                    {
                        if (name.Contains(alias, StringComparison.OrdinalIgnoreCase) && alias.Length > aliasLen)
                            aliasLen = alias.Length;
                    }
                    if (aliasLen == 0) continue;

                    var rect = el.Current.BoundingRectangle;
                    if (rect.Left < minContentX) continue;

                    if (aliasLen > bestAliasLen || (aliasLen == bestAliasLen && rect.Left < bestLeft))
                    {
                        best = el;
                        bestAliasLen = aliasLen;
                        bestLeft = rect.Left;
                    }
                }
                catch { }
            }

            return best
                ?? AutomationHelper.FindByAliases(window, NoScalingAliases, ControlType.RadioButton)
                ?? AutomationHelper.FindByAliases(window, NoScalingAliases);
        }
        catch
        {
            return AutomationHelper.FindByAliases(window, NoScalingAliases, ControlType.RadioButton)
                ?? AutomationHelper.FindByAliases(window, NoScalingAliases);
        }
    }

    /// <summary>Clic relatif au BoundingRectangle UIA, près du bord gauche (pas de coordonnées écran fixes).</summary>
    private static bool ClickNoScalingRadio(AutomationElement radio)
    {
        AutomationHelper.ScrollIntoView(radio);
        Thread.Sleep(200);

        try
        {
            if (radio.GetCurrentPattern(SelectionItemPattern.Pattern) is SelectionItemPattern sel && !sel.Current.IsSelected)
                sel.Select();
        }
        catch { }

        Thread.Sleep(150);

        try
        {
            var rect = radio.Current.BoundingRectangle;
            if (rect.Width >= 2 && rect.Height >= 2)
            {
                var x = (int)(rect.Left + rect.Width / 2);
                var y = (int)(rect.Top + rect.Height / 2);
                FileLogger.Info("[SAFE-UIA-RECT] clic centre radio UIA name=" + (radio.Current.Name ?? "")
                    + " rect=" + (int)rect.Left + "," + (int)rect.Top + "," + (int)rect.Width + "x" + (int)rect.Height);
                Win32Helper.ClickScreenPoint(x, y);
                return true;
            }
        }
        catch { }

        return AutomationHelper.ClickElement(radio);
    }

    private AutomationElement? OpenPanel()
    {
        var launcher = new PanelLauncher();
        var existing = PanelLauncher.FindPanelWindow();
        if (existing == null)
        {
            if (!launcher.TryLaunch())
            {
                FileLogger.Error("nvcplui.exe not found");
                return null;
            }
            existing = launcher.WaitForPanelWindow(_panelTimeout);
        }
        else
        {
            FileLogger.Info("WINDOW already open: " + existing.Current.Name);
        }

        if (existing == null) return null;
        PanelLauncher.FocusAndMaximize(existing);
        Thread.Sleep(500);
        return existing;
    }

    private static bool ClickApply(AutomationElement window)
    {
        var apply = AutomationHelper.FindByAliases(window, ApplyAliases, ControlType.Button);
        if (apply == null)
        {
            FileLogger.Warn("APPLY button not found");
            return false;
        }
        try
        {
            if (!apply.Current.IsEnabled)
            {
                FileLogger.Info("APPLY disabled (maybe unchanged)");
                return true;
            }
        }
        catch { }

        var ok = AutomationHelper.ClickElement(apply);
        FileLogger.Info("APPLY clicked=" + ok);
        Thread.Sleep(500);
        return ok;
    }

    /// <summary>Uniquement pas de mise à l'échelle : après Appliquer, LEFT puis ENTER (pas de détection fenêtre).</summary>
    private static void SendLeftEnterAfterApplyForNoScaling()
    {
        Thread.Sleep(1000);
        System.Windows.Forms.SendKeys.SendWait("{LEFT}");
        Thread.Sleep(150);
        System.Windows.Forms.SendKeys.SendWait("{ENTER}");
        FileLogger.Info("no-scaling: LEFT puis ENTER après Appliquer");
    }

    /// <summary>Uniquement téléciné inversée : même séquence que pas de mise à l'échelle.</summary>
    private static void SendLeftEnterAfterApplyForInverseTelecine()
    {
        Thread.Sleep(1000);
        System.Windows.Forms.SendKeys.SendWait("{LEFT}");
        Thread.Sleep(150);
        System.Windows.Forms.SendKeys.SendWait("{ENTER}");
        FileLogger.Info("LEFT + ENTER envoyés");
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
