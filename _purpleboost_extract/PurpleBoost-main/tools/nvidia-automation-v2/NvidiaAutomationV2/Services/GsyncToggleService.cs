using System.Text.RegularExpressions;
using NvidiaAutomationV2.Models;

namespace NvidiaAutomationV2.Services;

public sealed class GsyncToggleService
{
    public const string ExpectedRelativeToolPath = "tools/GsyncToggle/gsync-toggle.exe";

    private readonly ToolLocator _tools;

    public GsyncToggleService(ToolLocator tools, string? _)
    {
        _tools = tools;
    }

    /// <summary>Désactive G-Sync via gsync-toggle.exe 0, puis vérifie avec status.</summary>
    public StepResult DisableGsync()
    {
        FileLogger.Info("G-Sync OFF: starting");

        var exe = _tools.FindGsyncToggleExe();
        if (exe == null)
        {
            var missing = "Outil G-Sync manquant : " + ExpectedRelativeToolPath;
            FileLogger.Info("G-Sync OFF failed: " + missing);
            return StepResult.Fail(missing);
        }

        FileLogger.Info("G-Sync tool found: " + exe);
        FileLogger.Info("Command: gsync-toggle.exe 0");

        var off = ProcessRunner.Run(exe, "0", 30_000);
        FileLogger.Info("Exit code: " + off.ExitCode);

        if (off.TimedOut)
        {
            FileLogger.Info("G-Sync OFF failed: timeout (commande 0)");
            return StepResult.Fail("G-Sync OFF failed: timeout");
        }

        if (off.ExitCode != 0)
        {
            FileLogger.Info("G-Sync OFF failed: exit " + off.ExitCode);
            return StepResult.Fail("G-Sync OFF failed: exit " + off.ExitCode);
        }

        FileLogger.Info("Command: gsync-toggle.exe status");
        var status = ProcessRunner.Run(exe, "status", 15_000);
        var statusText = (status.StdOut + status.StdErr).Trim();
        FileLogger.Info("G-Sync status after apply: " + (string.IsNullOrEmpty(statusText) ? "(empty)" : statusText));

        if (status.TimedOut)
        {
            FileLogger.Info("G-Sync OFF failed: status timeout");
            return StepResult.Fail("Statut inconnu");
        }

        if (IsGsyncVerifiedOff(statusText))
        {
            FileLogger.Info("G-Sync OFF applied");
            return StepResult.Ok("OFF", true);
        }

        FileLogger.Info("G-Sync OFF failed: statut non confirmé OFF");
        return StepResult.Fail("Statut inconnu");
    }

    public StepResult ApplyGsyncOff() => DisableGsync();

    /// <summary>Désactive G-Sync si l'outil est présent ; sinon ignore l'étape sans échec global.</summary>
    public StepResult DisableGsyncIfToolAvailable()
    {
        if (_tools.FindGsyncToggleExe() != null)
            return DisableGsync();

        FileLogger.Info("G-Sync tool missing, skipping G-Sync step");
        return StepResult.Skip("G-Sync : outil manquant, étape ignorée");
    }

    private static bool IsGsyncVerifiedOff(string output)
    {
        if (string.IsNullOrWhiteSpace(output))
            return false;

        var lower = output.ToLowerInvariant();

        if (lower.Contains("off") || lower.Contains("disabled") || lower.Contains("désactivé") || lower.Contains("desactive"))
            return true;

        if (Regex.IsMatch(output, @"(^|\s)0(\s|$)", RegexOptions.Multiline))
            return true;

        if (lower.Contains("enabled") || lower.Contains(" on") || Regex.IsMatch(lower, @"\b[12]\b"))
            return false;

        return false;
    }
}
